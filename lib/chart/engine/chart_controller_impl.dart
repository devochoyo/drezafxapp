import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' hide Viewport;

import '../../models/currency_pair.dart';
import '../contracts/chart_contracts.dart';
import 'mapper_impl.dart';
import 'viewport.dart';

/// Concrete [ChartController] that owns the data service, viewport and overlays.
class ChartControllerImpl extends ChartController {
  ChartControllerImpl({
    required ChartDataService data,
    required String symbol,
    ChartTimeframe timeframe = ChartTimeframe.defaultTimeframe,
  })  : _data = data,
        _symbol = symbol.toUpperCase(),
        _timeframe = timeframe {
    _mapper = MapperImpl(
      viewport: _viewport,
      candles: const [],
      timeframe: _timeframe,
      pricePrecision: _precisionFor(_symbol),
    );
    _viewport.addListener(_onViewportChanged);
    _linkSub = _data.linkState.listen((s) {
      _linkState = s;
      notifyListeners();
    });
  }

  final ChartDataService _data;
  final Viewport _viewport = Viewport();
  late MapperImpl _mapper;
  final List<ChartOverlay> _overlays = [];
  final _viewportNotifier = _ViewportNotifier();

  // ---- state ------------------------------------------------------------
  String _symbol;
  ChartTimeframe _timeframe;
  ChartLoadState _loadState = ChartLoadState.idle;
  String? _errorMessage;
  ChartLinkState _linkState = ChartLinkState.offline;
  List<Candle> _candles = const [];
  double? _prevDailyClose;
  Candle? _crosshairCandle;

  StreamSubscription<Candle>? _liveSub;
  StreamSubscription<ChartLinkState>? _linkSub;
  bool _disposed = false;
  int _loadGen = 0;

  // Cap loaded candles to keep memory bounded.
  static const int _maxCandles = 20000;

  // ---- ChartController --------------------------------------------------

  @override
  String get symbol => _symbol;

  @override
  ChartTimeframe get timeframe => _timeframe;

  @override
  ChartLoadState get loadState => _loadState;

  @override
  String? get errorMessage => _errorMessage;

  @override
  ChartLinkState get linkState => _linkState;

  @override
  List<Candle> get candles => _candles;

  @override
  Candle? get lastCandle => _candles.isEmpty ? null : _candles.last;

  @override
  double? get lastPrice => lastCandle?.close;

  @override
  double? get dailyChange {
    final lp = lastPrice;
    final prev = _prevDailyClose;
    if (lp == null || prev == null) return null;
    return lp - prev;
  }

  @override
  double? get dailyChangePercent {
    final ch = dailyChange;
    final prev = _prevDailyClose;
    if (ch == null || prev == null || prev == 0) return null;
    return (ch / prev) * 100;
  }

  @override
  Candle? get crosshairCandle => _crosshairCandle;

  @override
  ChartCoordinateMapper get mapper => _mapper;

  @override
  double? get centerPrice {
    final plot = _mapper.plotRect;
    if (plot.height <= 0) return lastPrice;
    return _mapper.yToPrice(plot.center.dy);
  }

  @override
  bool get isAtLiveEdge => _viewport.isAtLiveEdge;

  @override
  bool get isPriceScaleManual => _viewport.isPriceScaleManual;

  @override
  Listenable get viewportChanges => _viewportNotifier;

  @override
  Future<void> setSymbol(String symbol) async {
    final s = symbol.toUpperCase();
    if (s == _symbol) return;
    _symbol = s;
    _mapper.pricePrecision = _precisionFor(s);
    _crosshairCandle = null;
    await _reload(keepViewport: false);
  }

  @override
  Future<void> setTimeframe(ChartTimeframe timeframe) async {
    if (timeframe == _timeframe) return;
    _timeframe = timeframe;
    _mapper.timeframe = timeframe;
    _crosshairCandle = null;
    await _reload(keepViewport: false);
  }

  @override
  Future<void> reload() => _reload(keepViewport: true);

  @override
  void scrollToLatest({bool animate = true}) {
    _viewport.scrollToLatest();
    if (!_viewport.isPriceScaleManual) {
      _viewport.autoFitPrice(_candles);
    }
  }

  @override
  void resetPriceScale() {
    _viewport.resetPriceScale();
    _viewport.autoFitPrice(_candles);
  }

  @override
  void addOverlay(ChartOverlay overlay) {
    if (_overlays.contains(overlay)) return;
    _overlays.add(overlay);
    _overlays.sort((a, b) => a.zOrder.compareTo(b.zOrder));
    overlay.addListener(_onOverlayChanged);
    _viewportNotifier.notify();
  }

  @override
  void removeOverlay(ChartOverlay overlay) {
    if (_overlays.remove(overlay)) {
      overlay.removeListener(_onOverlayChanged);
      _viewportNotifier.notify();
    }
  }

  @override
  void expandPriceRangeToInclude(double price) {
    _viewport.expandPriceRangeToInclude(price);
  }

  // ---- internal API used by ChartView -----------------------------------

  Viewport get viewport => _viewport;
  List<ChartOverlay> get overlays => _overlays;
  MapperImpl get mapperImpl => _mapper;

  void setCrosshair(Candle? c) {
    if (_crosshairCandle == c) return;
    _crosshairCandle = c;
    notifyListeners();
  }

  Size? _pendingSize;

  /// Called from a LayoutBuilder. Applied after the frame so no listener
  /// rebuilds while the framework is still building/laying out.
  void onSizeChanged(Size size) {
    if (size == _viewport.size || size == _pendingSize) return;
    _pendingSize = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = _pendingSize;
      _pendingSize = null;
      if (s == null || _disposed) return;
      final labelW = 12.0 + _mapper.pricePrecision * 7.0 + 20;
      _viewport.setSize(
        s,
        priceAxisWidth: labelW.clamp(60, 80).toDouble(),
        timeAxisHeight: 22,
      );
      if (!_viewport.isPriceScaleManual) {
        _viewport.autoFitPrice(_candles);
      }
    });
  }

  // ---- loading ----------------------------------------------------------

  Future<void> _reload({required bool keepViewport}) async {
    final gen = ++_loadGen;
    _errorMessage = null;
    _loadState = ChartLoadState.loading;
    notifyListeners();

    // Cancel previous live sub.
    await _liveSub?.cancel();
    _liveSub = null;

    try {
      // Show cache instantly if present.
      final list = await _data.loadInitial(_symbol, _timeframe, count: 500);
      if (gen != _loadGen || _disposed) return;

      _setCandles(list, resetView: !keepViewport);
      _loadState =
          list.isEmpty ? ChartLoadState.empty : ChartLoadState.ready;
      notifyListeners();

      // Previous daily close (non-blocking).
      _data.previousDailyClose(_symbol).then((v) {
        if (gen != _loadGen || _disposed) return;
        _prevDailyClose = v;
        notifyListeners();
      });

      // Live stream.
      _liveSub = _data.watchLive(_symbol, _timeframe).listen(
        _onLiveCandle,
        onError: (Object e) {
          if (kDebugMode) debugPrint('[ChartController] live error: $e');
        },
      );
    } catch (e) {
      if (gen != _loadGen || _disposed) return;
      _errorMessage = e is ChartDataException ? e.message : e.toString();
      _loadState = ChartLoadState.error;
      notifyListeners();
    }
  }

  void _onLiveCandle(Candle c) {
    if (_disposed) return;
    if (_candles.isEmpty) {
      _setCandles([c], resetView: true);
      _loadState = ChartLoadState.ready;
      notifyListeners();
      return;
    }

    final last = _candles.last;
    if (c.time == last.time) {
      // Update forming candle.
      final copy = List<Candle>.from(_candles);
      copy[copy.length - 1] = c;
      _candles = copy;
      _mapper.updateCandles(_candles);
      if (!_viewport.isPriceScaleManual && _viewport.isAtLiveEdge) {
        _viewport.autoFitPrice(_candles);
      }
      // Live tick: only notify viewport (candle + last-price layers).
      _viewportNotifier.notify();
      // Header price also needs an update.
      notifyListeners();
    } else if (c.time > last.time) {
      // New candle.
      final copy = List<Candle>.from(_candles)..add(c);
      if (copy.length > _maxCandles) {
        copy.removeRange(0, copy.length - _maxCandles);
      }
      _candles = copy;
      _mapper.updateCandles(_candles);
      _viewport.setCandleCount(_candles.length);
      if (_viewport.isAtLiveEdge) {
        _viewport.scrollToLatest(rightPadSlots: 3);
        if (!_viewport.isPriceScaleManual) {
          _viewport.autoFitPrice(_candles);
        }
      }
      notifyListeners();
    }
    // Older → ignore.
  }

  void _setCandles(List<Candle> list, {required bool resetView}) {
    _candles = List<Candle>.from(list);
    if (_candles.length > _maxCandles) {
      _candles = _candles.sublist(_candles.length - _maxCandles);
    }
    _mapper.updateCandles(_candles);
    _viewport.setCandleCount(_candles.length);
    if (resetView) {
      _viewport.setVisibleCount(80);
      _viewport.scrollToLatest(rightPadSlots: 3);
      _viewport.resetPriceScale();
      _viewport.autoFitPrice(_candles);
    } else if (!_viewport.isPriceScaleManual) {
      _viewport.autoFitPrice(_candles);
    }
  }

  // ---- history pagination (called by ChartView on left-edge reach) ------

  bool _loadingOlder = false;

  Future<void> loadOlderIfNeeded() async {
    if (_loadingOlder || _candles.isEmpty) return;
    if (_viewport.startIndex > 30) return; // not near left edge
    _loadingOlder = true;
    try {
      final older = await _data.loadOlder(
        _symbol,
        _timeframe,
        beforeTime: _candles.first.time,
        count: 500,
      );
      if (_disposed || older.isEmpty) return;
      final merged = [...older, ..._candles];
      // Dedup by time.
      final map = <int, Candle>{};
      for (final c in merged) {
        map[c.time] = c;
      }
      final keys = map.keys.toList()..sort();
      var result = [for (final k in keys) map[k]!];
      if (result.length > _maxCandles) {
        result = result.sublist(result.length - _maxCandles);
      }
      final shift = result.length - _candles.length;
      _candles = result;
      _mapper.updateCandles(_candles);
      _viewport.setCandleCount(_candles.length);
      // Keep visual position stable.
      _viewport.panByPixels(
        -shift * (_mapper.plotRect.width / _viewport.visibleCount),
      );
      notifyListeners();
    } catch (_) {
      // Silent — user can still interact with what is loaded.
    } finally {
      _loadingOlder = false;
    }
  }

  // ---- listeners --------------------------------------------------------

  void _onViewportChanged() {
    _viewportNotifier.notify();
    // Trigger older history when near left edge.
    if (_viewport.startIndex < 40) {
      loadOlderIfNeeded();
    }
  }

  void _onOverlayChanged() {
    _viewportNotifier.notify();
  }

  static int _precisionFor(String symbol) {
    final pair = CurrencyPair.tryParse(symbol);
    return pair?.pricePrecision ?? 5;
  }

  // ---- lifecycle --------------------------------------------------------

  @override
  void dispose() {
    _disposed = true;
    _loadGen++;
    _liveSub?.cancel();
    _linkSub?.cancel();
    _viewport.removeListener(_onViewportChanged);
    for (final o in _overlays) {
      o.removeListener(_onOverlayChanged);
    }
    _overlays.clear();
    _data.dispose();
    _viewportNotifier.dispose();
    super.dispose();
  }
}

/// Lightweight notifier so overlay / candle layers can repaint without
/// going through the heavier [ChartController] ChangeNotifier.
class _ViewportNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}
