import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/currency_pair.dart';
import '../models/market_connection_status.dart';
import '../models/market_credentials.dart';
import '../models/market_price.dart';
import 'market_data_service.dart';

/// Real market-data provider: OANDA v20 pricing stream.
///
/// Endpoint (OANDA developer docs, "Pricing Endpoints"):
///   GET https://stream-fxpractice.oanda.com/v3/accounts/{accountID}/pricing/stream  (practice)
///   GET https://stream-fxtrade.oanda.com/v3/accounts/{accountID}/pricing/stream     (live)
///   header  Authorization: Bearer <token>
///   query   instruments=EUR_USD,USD_JPY,...   snapshot=true
/// The response is a long-lived chunked HTTP response with one JSON object per
/// line: PRICE objects (bids/asks/instrument/time/tradeable) and HEARTBEAT
/// objects every 5 seconds.
///
/// Rules of this class:
///  * Only prices received from OANDA are published. Nothing is generated.
///  * Bid is used as the evaluation price (MarketPrice.fromBidAsk).
///  * Non-tradeable / invalid quotes are ignored.
///  * No data (not even a heartbeat) for [staleAfter] = connection lost.
///  * Never falls back to any other data source.
///
/// The stream's instrument list is fixed per request, so a change of the
/// subscribed pairs re-opens the stream (debounced).
class OandaMarketDataService implements MarketDataService {
  OandaMarketDataService({
    required Future<MarketCredentials?> Function() loadCredentials,
    this.staleAfter = const Duration(seconds: 15),
    this.connectTimeout = const Duration(seconds: 15),
  }) : _loadCredentials = loadCredentials;

  final Future<MarketCredentials?> Function() _loadCredentials;

  /// OANDA sends a heartbeat every 5 s; 15 s of silence means a dead link.
  final Duration staleAfter;
  final Duration connectTimeout;

  final _statusCtrl = StreamController<MarketConnectionStatus>.broadcast();
  final _priceCtrl = StreamController<MarketPrice>.broadcast();
  final Set<CurrencyPair> _subscribed = {};
  final Map<CurrencyPair, MarketPrice> _latest = {};

  MarketConnectionStatus _status = MarketConnectionStatus.disconnected;
  bool _wanted = false; // connect() was called and disconnect() was not
  int _generation = 0; // identifies the current stream; old ones are ignored
  HttpClient? _client;
  StreamSubscription<String>? _lineSub;
  Timer? _watchdog;
  Timer? _restartTimer;
  DateTime _lastActivity = DateTime.now();
  Future<void> _ops = Future.value();

  @override
  MarketConnectionStatus get status => _status;

  @override
  Stream<MarketConnectionStatus> get statusStream => _statusCtrl.stream;

  @override
  Stream<MarketPrice> get priceStream => _priceCtrl.stream;

  @override
  Set<CurrencyPair> get subscribedPairs => Set.unmodifiable(_subscribed);

  // ------------------------------------------------------------ public API

  @override
  Future<void> connect() {
    _wanted = true;
    return _serialize(_open);
  }

  @override
  Future<void> disconnect() async {
    _wanted = false;
    _restartTimer?.cancel();
    await _serialize(() async {
      await _closeStream();
      _setStatus(MarketConnectionStatus.disconnected);
    });
  }

  @override
  Future<void> subscribe(CurrencyPair pair) async {
    if (_subscribed.add(pair)) _scheduleRestart();
  }

  @override
  Future<void> unsubscribe(CurrencyPair pair) async {
    if (_subscribed.remove(pair)) {
      _latest.remove(pair);
      _scheduleRestart();
    }
  }

  /// Latest price received from OANDA, or null if none arrived recently.
  @override
  MarketPrice? getLatestPrice(CurrencyPair pair) {
    final price = _latest[pair];
    if (price == null) return null;
    return DateTime.now().difference(price.timestamp) > const Duration(minutes: 2)
        ? null
        : price;
  }

  @override
  Future<void> dispose() async {
    _wanted = false;
    _restartTimer?.cancel();
    await _closeStream();
    await _statusCtrl.close();
    await _priceCtrl.close();
  }

  // -------------------------------------------------------------- internals

  Future<void> _serialize(Future<void> Function() action) {
    final next = _ops.then((_) => action());
    _ops = next.catchError((_) {});
    return next;
  }

  void _setStatus(MarketConnectionStatus status) {
    _status = status;
    if (!_statusCtrl.isClosed) _statusCtrl.add(status);
  }

  /// The pair set changed: re-open the stream shortly (several changes in a
  /// row, e.g. at start-up, produce a single reconnect).
  void _scheduleRestart() {
    if (!_wanted) return;
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(milliseconds: 500), () {
      if (!_wanted) return;
      _serialize(_open).catchError((_) {
        // The status stream already reports the failure; the monitoring
        // engine reconnects with back-off.
      });
    });
  }

  Future<void> _open() async {
    if (!_wanted) return;
    await _closeStream();

    final credentials = await _loadCredentials();
    if (credentials == null || !credentials.isComplete) {
      const message = 'OANDA account ID and API token are not set. '
          'Open Settings > Market data and enter them.';
      _setStatus(MarketConnectionStatus(MarketConnectionState.disconnected,
          message: message, at: DateTime.now()));
      throw const MarketDataCredentialsException(message);
    }
    if (_subscribed.isEmpty) {
      // Nothing to watch yet; the stream opens as soon as a pair is added.
      _setStatus(MarketConnectionStatus(MarketConnectionState.disconnected,
          message: 'No alerts to watch yet. Prices start when you add one.',
          at: DateTime.now()));
      return;
    }

    final generation = ++_generation;
    _setStatus(MarketConnectionStatus(MarketConnectionState.connecting,
        at: DateTime.now()));

    final host = credentials.live
        ? 'stream-fxtrade.oanda.com'
        : 'stream-fxpractice.oanda.com';
    final instruments = _subscribed.map(instrumentName).toList()..sort();
    final uri = Uri.https(
      host,
      '/v3/accounts/${Uri.encodeComponent(credentials.accountId)}/pricing/stream',
      {'instruments': instruments.join(','), 'snapshot': 'true'},
    );

    final client = HttpClient()..connectionTimeout = connectTimeout;
    _client = client;
    try {
      final request = await client.getUrl(uri).timeout(connectTimeout);
      request.headers.set(HttpHeaders.authorizationHeader,
          'Bearer ${credentials.token}');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(connectTimeout);

      if (generation != _generation) {
        client.close(force: true);
        return;
      }
      if (response.statusCode != HttpStatus.ok) {
        final body = await _readBody(response);
        throw _exceptionForStatus(response.statusCode, body);
      }

      _lastActivity = DateTime.now();
      _lineSub = response
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) => _onLine(line, generation),
            onError: (Object e) => _onStreamLost('Stream error: $e', generation),
            onDone: () => _onStreamLost('The price stream was closed.', generation),
            cancelOnError: true,
          );
      _watchdog = Timer.periodic(const Duration(seconds: 5), (_) {
        if (DateTime.now().difference(_lastActivity) > staleAfter) {
          _onStreamLost(
              'No data from OANDA for ${staleAfter.inSeconds} seconds.',
              generation);
        }
      });
      _setStatus(
          MarketConnectionStatus(MarketConnectionState.connected, at: DateTime.now()));
    } on MarketDataException catch (e) {
      await _closeStream();
      _reportFailure(e);
      rethrow;
    } on TimeoutException {
      await _closeStream();
      const e = MarketDataException('Timed out connecting to OANDA.');
      _reportFailure(e);
      throw e;
    } catch (e) {
      await _closeStream();
      final wrapped = MarketDataException('Could not reach OANDA: $e');
      _reportFailure(wrapped);
      throw wrapped;
    }
  }

  /// Permanent problems (bad credentials / account / instrument) are shown as
  /// "disconnected" with the reason, so the engine does not hammer OANDA with
  /// retries. Temporary problems are "error": the engine retries with back-off.
  void _reportFailure(MarketDataException e) {
    _setStatus(MarketConnectionStatus(
      e.isPermanent
          ? MarketConnectionState.disconnected
          : MarketConnectionState.error,
      message: e.message,
      at: DateTime.now(),
    ));
  }

  void _onStreamLost(String reason, int generation) {
    if (generation != _generation || !_wanted) return;
    _generation++; // ignore anything else from the dead stream
    _closeStream();
    _setStatus(MarketConnectionStatus(MarketConnectionState.error,
        message: reason, at: DateTime.now()));
  }

  void _onLine(String line, int generation) {
    if (generation != _generation) return;
    _lastActivity = DateTime.now();
    final price = parsePriceLine(line, _subscribed);
    if (price == null) return;
    _latest[price.pair] = price;
    if (!_priceCtrl.isClosed) _priceCtrl.add(price);
  }

  Future<void> _closeStream() async {
    _watchdog?.cancel();
    _watchdog = null;
    final sub = _lineSub;
    _lineSub = null;
    await sub?.cancel();
    _client?.close(force: true);
    _client = null;
  }

  Future<String> _readBody(HttpClientResponse response) async {
    try {
      return await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      return '';
    }
  }

  MarketDataException _exceptionForStatus(int code, String body) {
    String detail = '';
    try {
      final json = jsonDecode(body);
      if (json is Map && json['errorMessage'] != null) {
        detail = ' ${json['errorMessage']}';
      }
    } catch (_) {}
    if (code == HttpStatus.unauthorized || code == HttpStatus.forbidden) {
      return MarketDataCredentialsException(
          'OANDA rejected the account ID or API token (HTTP $code).$detail '
          'Check them in Settings > Market data.');
    }
    if (code == HttpStatus.tooManyRequests || code >= 500) {
      return MarketDataException('OANDA is temporarily unavailable (HTTP $code).$detail');
    }
    return MarketDataCredentialsException(
        'OANDA refused the price request (HTTP $code).$detail');
  }

  // ---------------------------------------------------------------- parsing

  /// OANDA instrument name for a pair: EURUSD -> EUR_USD, XAUUSD -> XAU_USD.
  static String instrumentName(CurrencyPair pair) => '${pair.base}_${pair.quote}';

  /// Parses one line of the stream. Returns null for heartbeats, blank or
  /// unreadable lines, non-tradeable quotes, pairs nobody subscribed to, and
  /// anything without a valid bid and ask.
  static MarketPrice? parsePriceLine(String line, Set<CurrencyPair> wanted) {
    if (line.trim().isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    if (decoded['type'] == 'HEARTBEAT') return null;
    if (decoded['tradeable'] == false) return null;
    final status = decoded['status'];
    if (status != null && status != 'tradeable') return null;

    final instrument = decoded['instrument'];
    if (instrument is! String) return null;
    final pair = CurrencyPair.tryParse(instrument.replaceAll('_', ''));
    if (pair == null || !wanted.contains(pair)) return null;

    final bid = _bestPrice(decoded['bids']);
    final ask = _bestPrice(decoded['asks']);
    if (bid == null || ask == null || bid <= 0 || ask <= 0) return null;

    final time = decoded['time'];
    final timestamp =
        (time is String ? DateTime.tryParse(time)?.toLocal() : null) ??
            DateTime.now();
    final price = MarketPrice.fromBidAsk(
        pair: pair, bid: bid, ask: ask, timestamp: timestamp);
    return price.isValid ? price : null;
  }

  static double? _bestPrice(Object? buckets) {
    if (buckets is! List || buckets.isEmpty) return null;
    final first = buckets.first;
    if (first is! Map) return null;
    final value = first['price'];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

/// Missing or rejected credentials / account / instrument. Retrying cannot
/// fix this, so the engine does not retry automatically.
class MarketDataCredentialsException extends MarketDataException {
  const MarketDataCredentialsException(super.message);

  @override
  bool get isPermanent => true;
}
