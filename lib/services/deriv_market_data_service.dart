import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/currency_pair.dart';
import '../models/market_connection_status.dart';
import '../models/market_price.dart';
import 'market_data_service.dart';

/// Real market-data provider: Deriv public WebSocket tick stream.
///
/// No account, token or app ID is needed for public market data.
///
/// Endpoints, tried in order (the first one that connects is used):
///   wss://api.derivws.com/trading/v1/options/ws/public
///   wss://ws.derivws.com/websockets/v3?app_id=1089        (classic host)
///
/// Messages:
///   send     {"ticks": "frxEURUSD", "subscribe": 1}
///   receive  {"msg_type": "tick", "tick": {"symbol", "quote", "bid", "ask",
///             "epoch", "id", ...}, "subscription": {"id": ...}}
///   send     {"forget": "<subscription id>"}   (unsubscribe)
///   send     {"ping": 1}                       (keep-alive, answered by pong)
///
/// Rules of this class:
///  * Only prices received from Deriv are published. Nothing is generated.
///  * Bid is used as the evaluation price (MarketPrice.fromBidAsk). If a tick
///    carries no bid/ask, its quote is used for both.
///  * Any message, including a pong, counts as activity. No message for
///    [staleAfter] = connection lost (the engine then reconnects with back-off).
///  * Never falls back to any other data source.
///
/// Forex is closed at weekends: the connection stays open (pongs keep it
/// alive) but no ticks arrive until the market reopens.
class DerivMarketDataService implements MarketDataService {
  DerivMarketDataService({
    this.endpoints = defaultEndpoints,
    this.staleAfter = const Duration(seconds: 40),
    this.connectTimeout = const Duration(seconds: 15),
  });

  static const List<String> defaultEndpoints = [
    'wss://api.derivws.com/trading/v1/options/ws/public',
    'wss://ws.derivws.com/websockets/v3?app_id=1089',
  ];

  final List<String> endpoints;
  final Duration staleAfter;
  final Duration connectTimeout;

  final _statusCtrl = StreamController<MarketConnectionStatus>.broadcast();
  final _priceCtrl = StreamController<MarketPrice>.broadcast();
  final Set<CurrencyPair> _subscribed = {};
  final Map<CurrencyPair, MarketPrice> _latest = {};
  final Map<CurrencyPair, String> _subscriptionIds = {};

  MarketConnectionStatus _status = MarketConnectionStatus.disconnected;
  bool _wanted = false; // connect() was called and disconnect() was not
  int _generation = 0; // identifies the current socket; old ones are ignored
  int _requestId = 0;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSub;
  Timer? _watchdog;
  Timer? _openTimer;
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
    _openTimer?.cancel();
    await _serialize(() async {
      _generation++;
      await _closeSocket();
      _setStatus(MarketConnectionStatus.disconnected);
    });
  }

  @override
  Future<void> subscribe(CurrencyPair pair) async {
    if (!_subscribed.add(pair)) return;
    if (_socket != null) {
      _sendSubscribe(pair);
    } else {
      _scheduleOpen();
    }
  }

  @override
  Future<void> unsubscribe(CurrencyPair pair) async {
    if (!_subscribed.remove(pair)) return;
    _latest.remove(pair);
    final id = _subscriptionIds.remove(pair);
    if (id != null) _send({'forget': id});
  }

  /// Latest price received from Deriv, or null if none arrived recently.
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
    _openTimer?.cancel();
    _generation++;
    await _closeSocket();
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

  /// A pair was added while no socket is open (for example the very first
  /// alert): open shortly, so several additions in a row make one connection.
  void _scheduleOpen() {
    if (!_wanted) return;
    _openTimer?.cancel();
    _openTimer = Timer(const Duration(milliseconds: 500), () {
      if (!_wanted || _socket != null) return;
      _serialize(_open).catchError((_) {
        // The status stream already reports the failure; the monitoring
        // engine reconnects with back-off.
      });
    });
  }

  Future<void> _open() async {
    if (!_wanted) return;
    await _closeSocket();

    if (_subscribed.isEmpty) {
      // Nothing to watch yet; the socket opens as soon as a pair is added.
      _setStatus(MarketConnectionStatus(MarketConnectionState.disconnected,
          message: 'No alerts to watch yet. Prices start when you add one.',
          at: DateTime.now()));
      return;
    }

    final generation = ++_generation;
    _setStatus(MarketConnectionStatus(MarketConnectionState.connecting,
        at: DateTime.now()));

    Object? lastError;
    for (final url in endpoints) {
      try {
        final socket = await WebSocket.connect(url).timeout(connectTimeout);
        if (generation != _generation || !_wanted) {
          await socket.close();
          return;
        }
        _attach(socket, generation);
        return;
      } on TimeoutException {
        lastError = 'timed out';
      } catch (e) {
        lastError = e;
      }
    }

    final failure = MarketDataException('Could not reach Deriv: $lastError');
    _setStatus(MarketConnectionStatus(MarketConnectionState.error,
        message: failure.message, at: DateTime.now()));
    throw failure;
  }

  void _attach(WebSocket socket, int generation) {
    _socket = socket;
    _lastActivity = DateTime.now();
    _socketSub = socket.listen(
      (Object? data) => _onMessage(data, generation),
      onError: (Object e) => _onLost('Connection error: $e', generation),
      onDone: () => _onLost('The price connection was closed.', generation),
      cancelOnError: true,
    );
    for (final pair in _subscribed) {
      _sendSubscribe(pair);
    }
    _watchdog = Timer.periodic(const Duration(seconds: 10), (_) {
      if (generation != _generation) return;
      if (DateTime.now().difference(_lastActivity) > staleAfter) {
        _onLost('No data from Deriv for ${staleAfter.inSeconds} seconds.',
            generation);
      } else {
        _send({'ping': 1});
      }
    });
    _setStatus(
        MarketConnectionStatus(MarketConnectionState.connected, at: DateTime.now()));
  }

  void _onLost(String reason, int generation) {
    if (generation != _generation || !_wanted) return;
    _generation++; // ignore anything else from the dead socket
    _closeSocket();
    _setStatus(MarketConnectionStatus(MarketConnectionState.error,
        message: reason, at: DateTime.now()));
  }

  void _sendSubscribe(CurrencyPair pair) {
    _send({
      'ticks': derivSymbol(pair),
      'subscribe': 1,
      'req_id': ++_requestId,
    });
  }

  void _send(Map<String, Object?> message) {
    final socket = _socket;
    if (socket == null) return;
    try {
      socket.add(jsonEncode(message));
    } catch (_) {
      // A broken socket is detected by the listener / watchdog.
    }
  }

  void _onMessage(Object? data, int generation) {
    if (generation != _generation) return;
    _lastActivity = DateTime.now();
    if (data is! String) return;

    final Object? decoded;
    try {
      decoded = jsonDecode(data);
    } catch (_) {
      return;
    }
    if (decoded is! Map) return;

    final error = decoded['error'];
    if (error is Map) {
      _onSymbolError(decoded, error);
      return;
    }

    final price = parseTick(decoded['tick'], _subscribed);
    if (price == null) return;

    final subscription = decoded['subscription'];
    if (subscription is Map && subscription['id'] is String) {
      _subscriptionIds[price.pair] = subscription['id'] as String;
    }
    _latest[price.pair] = price;
    if (!_priceCtrl.isClosed) _priceCtrl.add(price);
  }

  /// Deriv rejected a request (for example a symbol it does not offer). The
  /// connection stays up for the other pairs; the reason is kept in the status.
  void _onSymbolError(Map<Object?, Object?> reply, Map<Object?, Object?> error) {
    final echo = reply['echo_req'];
    final symbol = echo is Map ? echo['ticks'] : null;
    final text = error['message'] is String ? error['message'] as String : 'error';
    final what = symbol is String ? 'Deriv rejected $symbol: $text' : 'Deriv: $text';
    if (_status.isConnected) {
      _setStatus(MarketConnectionStatus(MarketConnectionState.connected,
          message: what, at: DateTime.now()));
    }
  }

  Future<void> _closeSocket() async {
    _watchdog?.cancel();
    _watchdog = null;
    final sub = _socketSub;
    _socketSub = null;
    final socket = _socket;
    _socket = null;
    _subscriptionIds.clear();
    await sub?.cancel();
    if (socket != null) {
      try {
        await socket.close().timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------- parsing

  /// Deriv symbol for a pair: EURUSD -> frxEURUSD, XAUUSD -> frxXAUUSD.
  static String derivSymbol(CurrencyPair pair) => 'frx${pair.base}${pair.quote}';

  /// Pair for a Deriv symbol, or null when it is not a forex symbol.
  static CurrencyPair? pairFromDerivSymbol(String symbol) {
    if (!symbol.startsWith('frx')) return null;
    return CurrencyPair.tryParse(symbol.substring(3));
  }

  /// Parses the "tick" object of a message. Returns null for anything that is
  /// not a valid price for a subscribed pair.
  static MarketPrice? parseTick(Object? tick, Set<CurrencyPair> wanted) {
    if (tick is! Map) return null;
    final symbol = tick['symbol'];
    if (symbol is! String) return null;
    final pair = pairFromDerivSymbol(symbol);
    if (pair == null || !wanted.contains(pair)) return null;

    final quote = _number(tick['quote']);
    final bid = _number(tick['bid']) ?? quote;
    final ask = _number(tick['ask']) ?? quote;
    if (bid == null || ask == null || bid <= 0 || ask <= 0) return null;

    final epoch = tick['epoch'];
    final timestamp = epoch is num
        ? DateTime.fromMillisecondsSinceEpoch(epoch.toInt() * 1000)
        : DateTime.now();
    final price = MarketPrice.fromBidAsk(
        pair: pair, bid: bid, ask: ask, timestamp: timestamp);
    return price.isValid ? price : null;
  }

  static double? _number(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
