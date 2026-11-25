import 'dart:ui';

import '../contracts/chart_contracts.dart';
import 'viewport.dart';

/// Pure-arithmetic coordinate mapper. Allocation-free in the hot path.
class MapperImpl implements ChartCoordinateMapper {
  MapperImpl({
    required this.viewport,
    required List<Candle> candles,
    required this.timeframe,
    required this.pricePrecision,
  }) : _candles = candles;

  final Viewport viewport;
  List<Candle> _candles;
  ChartTimeframe timeframe;
  @override
  int pricePrecision;

  void updateCandles(List<Candle> candles) {
    _candles = candles;
  }

  @override
  List<Candle> get candles => _candles;

  @override
  Rect get plotRect => viewport.plotRect;

  @override
  double get visibleMinPrice => viewport.minPrice;

  @override
  double get visibleMaxPrice => viewport.maxPrice;

  // ---- price ↔ y --------------------------------------------------------

  @override
  double priceToY(double price) {
    final plot = plotRect;
    final range = viewport.maxPrice - viewport.minPrice;
    if (range <= 0 || plot.height <= 0) return plot.center.dy;
    final t = (viewport.maxPrice - price) / range;
    return plot.top + t * plot.height;
  }

  @override
  double yToPrice(double y) {
    final plot = plotRect;
    final range = viewport.maxPrice - viewport.minPrice;
    if (range <= 0 || plot.height <= 0) return viewport.minPrice;
    final t = ((y - plot.top) / plot.height).clamp(0.0, 1.0);
    return viewport.maxPrice - t * range;
  }

  // ---- time ↔ x  (candle-index space) -----------------------------------

  @override
  double timeToX(int epochSeconds) {
    final plot = plotRect;
    if (plot.width <= 0 || _candles.isEmpty) return plot.left;

    final index = _indexForTime(epochSeconds);
    final slotWidth = plot.width / viewport.visibleCount;
    return plot.left + (index - viewport.startIndex) * slotWidth;
  }

  @override
  int xToTime(double x) {
    final plot = plotRect;
    if (plot.width <= 0 || _candles.isEmpty) {
      return _candles.isEmpty ? 0 : _candles.last.time;
    }
    final slotWidth = plot.width / viewport.visibleCount;
    final index = viewport.startIndex + (x - plot.left) / slotWidth;
    return _timeForIndex(index);
  }

  @override
  Candle? candleAtX(double x) {
    if (_candles.isEmpty) return null;
    final plot = plotRect;
    if (plot.width <= 0) return null;
    final slotWidth = plot.width / viewport.visibleCount;
    final index = (viewport.startIndex + (x - plot.left) / slotWidth)
        .round()
        .clamp(0, _candles.length - 1);
    return _candles[index];
  }

  // ---- helpers (binary search, no allocations beyond locals) ------------

  /// Returns a fractional index for [epoch]. Future times extrapolate;
  /// gaps between candles are linearly interpolated in index space
  /// (weekend compression like TradingView).
  double _indexForTime(int epoch) {
    final n = _candles.length;
    if (n == 0) return 0;
    if (epoch <= _candles.first.time) {
      // Before first candle: extrapolate left.
      final dt = timeframe.seconds;
      if (dt <= 0) return 0;
      return (epoch - _candles.first.time) / dt;
    }
    if (epoch >= _candles.last.time) {
      // After / at last candle: extrapolate right.
      final dt = timeframe.seconds;
      if (dt <= 0) return (n - 1).toDouble();
      return (n - 1) + (epoch - _candles.last.time) / dt;
    }

    // Binary search for the rightmost candle with time <= epoch.
    var lo = 0;
    var hi = n - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_candles[mid].time <= epoch) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }

    if (lo >= n - 1) return (n - 1).toDouble();
    final t0 = _candles[lo].time;
    final t1 = _candles[lo + 1].time;
    if (t1 == t0) return lo.toDouble();
    final frac = (epoch - t0) / (t1 - t0);
    return lo + frac;
  }

  int _timeForIndex(double index) {
    final n = _candles.length;
    if (n == 0) return 0;
    if (index <= 0) {
      final dt = timeframe.seconds;
      return _candles.first.time + (index * dt).round();
    }
    if (index >= n - 1) {
      final dt = timeframe.seconds;
      return _candles.last.time + ((index - (n - 1)) * dt).round();
    }
    final i0 = index.floor();
    final frac = index - i0;
    final t0 = _candles[i0].time;
    final t1 = _candles[i0 + 1].time;
    return t0 + ((t1 - t0) * frac).round();
  }
}
