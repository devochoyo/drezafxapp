import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../contracts/chart_contracts.dart';
import 'candle_aggregator.dart';
import 'candle_cache.dart';
import 'deriv_candle_parser.dart';

/// Real candle feed from Deriv public WebSocket.
///
/// Connection patterns mirror the project's [DerivMarketDataService]
/// (same endpoints, ping keep-alive, stale watchdog, generation counter).
/// Owns its own socket; does **not** share state with the tick service.
class DerivChartDataService implements ChartDataService {
  DerivChartDataService({
    this.endpoints = defaultEndpoints,
    this.staleAfter = const Duration(seconds: 45),
    this.connectTimeout = const Duration(seconds: 15),
    CandleCache? cache,
  }) : _cache = cache ?? CandleCache();

  static const List<String> defaultEndpoints = [
    'wss://api.derivws.com/trading/v1/options/ws/public',
    'wss://ws.derivws.com/websockets/v3?app_id=1089',
  ];

  final List<String> endpoints;
  final Duration staleAfter;
  final Duration connectTimeout;
  final CandleCache _cache;

  // ---- connection -------------------------------------------------------
  final _linkCtrl = StreamController<ChartLinkState>.broadcast();
  ChartLinkState _link = ChartLinkState.offline;
  bool _wanted = false;
  int _generation = 0;
  int _requestId = 0;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSub;
  Timer? _watchdog;
  DateTime _lastActivity = DateTime.now();
  Future<void> _ops = Future.value();

  // Every decoded map is pushed here so history waiters can filter by req_id.
  final _msgCtrl = StreamController<Map<Object?, Object?>>.broadcast();

  // ---- live subscription ------------------------------------------------
  String? _liveSymbol;
  ChartTimeframe? _liveTf;
  String? _liveSubId;
  final _liveCtrl = StreamController<Candle>.broadcast();

  // ---- previous-day close -----------------------------------------------
  final Map<String, double> _prevCloseCache = {};

  @override
  Stream<ChartLinkState> get linkState => _linkCtrl.stream;

  // ========================================================================
  // Public API
  // ========================================================================

  @override
  Future<List<Candle>> loadInitial(
    String symbol,
    ChartTimeframe timeframe, {
    int count = 500,
  }) async {
    final sym = symbol.toUpperCase();
    final cached = _cache.get(sym, timeframe);
    try {
      final remote = await _loadHistory(sym, timeframe, count: count);
      if (remote.isNotEmpty) {
        _cache.put(sym, timeframe, remote);
        return remote;
      }
    } catch (e) {
      if (cached != null && cached.isNotEmpty) return cached;
      rethrow;
    }
    return cached ?? const [];
  }

  @override
  Future<List<Candle>> loadOlder(
    String symbol,
    ChartTimeframe timeframe, {
    required int beforeTime,
    int count = 500,
  }) async {
    final sym = symbol.toUpperCase();
    final remote = await _loadHistory(
      sym,
      timeframe,
      count: count,
      endEpoch: beforeTime - 1,
    );
    if (remote.isNotEmpty) {
      _cache.merge(sym, timeframe, remote);
    }
    return remote;
  }

  @override
  Stream<Candle> watchLive(String symbol, ChartTimeframe timeframe) {
    final sym = symbol.toUpperCase();
    if (_liveSymbol != sym || _liveTf != timeframe) {
      _forgetLive();
      _liveSymbol = sym;
      _liveTf = timeframe;
      _ensureConnected().then((_) {
        if (_liveSymbol == sym && _liveTf == timeframe && _socket != null) {
          _subscribeLive(sym, timeframe);
        }
      });
    }
    return _liveCtrl.stream;
  }

  @override
  Future<double?> previousDailyClose(String symbol) async {
    final sym = symbol.toUpperCase();
    final hit = _prevCloseCache[sym];
    if (hit != null) return hit;

    final d1 = await _loadHistory(sym, ChartTimeframe.d1, count: 3);
    if (d1.length < 2) return null;
    final prev = d1[d1.length - 2].close;
    _prevCloseCache[sym] = prev;
    return prev;
  }

  @override
  Future<void> dispose() async {
    _wanted = false;
    _generation++;
    _forgetLive();
    await _closeSocket();
    await _linkCtrl.close();
    await _liveCtrl.close();
    await _msgCtrl.close();
  }

  // ========================================================================
  // History request
  // ========================================================================

  Future<List<Candle>> _loadHistory(
    String symbol,
    ChartTimeframe timeframe, {
    int count = 500,
    int? endEpoch,
  }) async {
    await _ensureConnected();
    final socket = _socket;
    if (socket == null) {
      throw const ChartDataException('Not connected to market data.');
    }

    final granularity = timeframe.sourceGranularity;
    final reqId = ++_requestId;
    final body = <String, Object?>{
      'ticks_history': _derivSymbol(symbol),
      'adjust_start_time': 1,
      'count': count.clamp(1, 5000),
      'end': endEpoch ?? 'latest',
      'granularity': granularity,
      'style': 'candles',
      'req_id': reqId,
    };

    final completer = Completer<List<Candle>>();
    late final StreamSubscription sub;
    final timer = Timer(const Duration(seconds: 20), () {
      if (!completer.isCompleted) {
        completer.completeError(
          const ChartDataException('History request timed out.'),
        );
      }
    });

    sub = _msgCtrl.stream.listen((decoded) {
      final echo = decoded['echo_req'];
      final echoId = echo is Map ? echo['req_id'] : null;
      final topId = decoded['req_id'];
      final matches = echoId == reqId || topId == reqId;
      // Also accept a bare candles payload (some hosts omit req_id).
      final isCandles = decoded['msg_type'] == 'candles' ||
          decoded['candles'] is List;

      if (!matches && !(isCandles && echoId == null && topId == null)) {
        return;
      }

      final err = decoded['error'];
      if (err is Map) {
        final msg = err['message'] is String
            ? err['message'] as String
            : 'Unknown Deriv error';
        if (!completer.isCompleted) {
          completer.completeError(ChartDataException(msg));
        }
        return;
      }

      if (isCandles) {
        final list = DerivCandleParser.parseCandlesMessage(decoded);
        if (!completer.isCompleted) completer.complete(list);
      }
    });

    try {
      socket.add(jsonEncode(body));
      var candles = await completer.future;
      if (timeframe.isDerived) {
        candles = CandleAggregator.aggregate(candles, timeframe);
      }
      return candles;
    } finally {
      timer.cancel();
      await sub.cancel();
    }
  }

  // ========================================================================
  // Live
  // ========================================================================

  void _subscribeLive(String symbol, ChartTimeframe timeframe) {
    final socket = _socket;
    if (socket == null) return;
    final body = <String, Object?>{
      'ticks_history': _derivSymbol(symbol),
      'adjust_start_time': 1,
      'count': 1,
      'end': 'latest',
      'granularity': timeframe.sourceGranularity,
      'style': 'candles',
      'subscribe': 1,
      'req_id': ++_requestId,
    };
    try {
      socket.add(jsonEncode(body));
    } catch (_) {}
  }

  void _forgetLive() {
    final id = _liveSubId;
    _liveSubId = null;
    if (id != null) _send({'forget': id});
  }

  void _handleLiveOhlc(Map<Object?, Object?> decoded) {
    final subId = DerivCandleParser.subscriptionId(decoded);
    if (subId != null) _liveSubId = subId;

    final candle = DerivCandleParser.parseOhlcMessage(decoded);
    if (candle == null || _liveTf == null || _liveSymbol == null) return;

    if (_liveTf!.isDerived) {
      // Fold D1 into weekly.
      final existing = _cache.get(_liveSymbol!, _liveTf!) ?? const [];
      final updated =
          CandleAggregator.applyLiveUpdate(existing, candle, _liveTf!);
      if (updated.isNotEmpty) {
        _cache.put(_liveSymbol!, _liveTf!, updated);
        if (!_liveCtrl.isClosed) _liveCtrl.add(updated.last);
      }
    } else {
      _cache.merge(_liveSymbol!, _liveTf!, [candle]);
      if (!_liveCtrl.isClosed) _liveCtrl.add(candle);
    }
  }

  // ========================================================================
  // Connection
  // ========================================================================

  Future<void> _ensureConnected() {
    _wanted = true;
    if (_socket != null && _link == ChartLinkState.live) {
      return Future.value();
    }
    return _serialize(_open);
  }

  Future<void> _serialize(Future<void> Function() action) {
    final next = _ops.then((_) => action());
    _ops = next.catchError((_) {});
    return next;
  }

  void _setLink(ChartLinkState s) {
    _link = s;
    if (!_linkCtrl.isClosed) _linkCtrl.add(s);
  }

  Future<void> _open() async {
    if (!_wanted) return;
    await _closeSocket();
    final generation = ++_generation;
    _setLink(ChartLinkState.connecting);

    Object? lastError;
    for (final url in endpoints) {
      try {
        final socket =
            await WebSocket.connect(url).timeout(connectTimeout);
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
    _setLink(ChartLinkState.offline);
    throw ChartDataException('Could not reach Deriv: $lastError');
  }

  void _attach(WebSocket socket, int generation) {
    _socket = socket;
    _lastActivity = DateTime.now();
    _socketSub = socket.listen(
      (Object? data) => _onMessage(data, generation),
      onError: (Object e) =>
          _onLost('Connection error: $e', generation),
      onDone: () =>
          _onLost('The price connection was closed.', generation),
      cancelOnError: true,
    );
    _watchdog = Timer.periodic(const Duration(seconds: 12), (_) {
      if (generation != _generation) return;
      if (DateTime.now().difference(_lastActivity) > staleAfter) {
        _onLost(
          'No data from Deriv for ${staleAfter.inSeconds}s.',
          generation,
        );
      } else {
        _send({'ping': 1});
      }
    });
    _setLink(ChartLinkState.live);

    if (_liveSymbol != null && _liveTf != null) {
      _subscribeLive(_liveSymbol!, _liveTf!);
    }
  }

  void _onLost(String reason, int generation) {
    if (generation != _generation || !_wanted) return;
    _generation++;
    _closeSocket();
    _setLink(ChartLinkState.reconnecting);
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (_wanted) {
        _serialize(_open).catchError((_) {});
      }
    });
    if (kDebugMode) {
      debugPrint('[DerivChartDataService] lost: $reason');
    }
  }

  void _onMessage(Object? data, int generation) {
    if (generation != _generation) return;
    _lastActivity = DateTime.now();
    if (data is! String) return;
    final decoded = DerivCandleParser.decode(data);
    if (decoded is! Map) return;

    // Forward to history waiters.
    if (!_msgCtrl.isClosed) {
      _msgCtrl.add(Map<Object?, Object?>.from(decoded));
    }

    final err = decoded['error'];
    if (err is Map) {
      if (kDebugMode) {
        debugPrint('[DerivChartDataService] error: ${err['message']}');
      }
      return;
    }

    final msgType = decoded['msg_type'];
    if (msgType == 'ohlc' || decoded['ohlc'] is Map) {
      _handleLiveOhlc(Map<Object?, Object?>.from(decoded));
    }
  }

  void _send(Map<String, Object?> message) {
    final socket = _socket;
    if (socket == null) return;
    try {
      socket.add(jsonEncode(message));
    } catch (_) {}
  }

  Future<void> _closeSocket() async {
    _watchdog?.cancel();
    _watchdog = null;
    final sub = _socketSub;
    _socketSub = null;
    final socket = _socket;
    _socket = null;
    try {
      await sub?.cancel();
    } catch (_) {}
    try {
      await socket?.close();
    } catch (_) {}
  }

  static String _derivSymbol(String symbol) => 'frx$symbol';
}
