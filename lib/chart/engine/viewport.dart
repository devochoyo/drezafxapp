import 'dart:math' as math;
import 'dart:ui' show Rect, Size;

import 'package:flutter/foundation.dart';

import '../contracts/chart_contracts.dart';
import 'price_scale.dart';

/// Mutable view window over a candle series.
///
/// Horizontal position is expressed in **candle-index space**:
///   - index 0 = oldest loaded candle
///   - index N-1 = newest candle
///   - fractional indices are allowed (for smooth pan/zoom)
///
/// [startIndex] is the left edge of the plot; [visibleCount] is how many
/// candle slots fit in the plot width.
class Viewport extends ChangeNotifier {
  Viewport();

  // ---- layout (set by ChartView on size change) --------------------------
  Size _size = Size.zero;
  double _priceAxisWidth = 68;
  double _timeAxisHeight = 22;
  double _paddingTop = 8;
  double _paddingBottom = 0;

  Size get size => _size;
  double get priceAxisWidth => _priceAxisWidth;
  double get timeAxisHeight => _timeAxisHeight;

  Rect get plotRect {
    if (_size == Size.zero) return Rect.zero;
    return Rect.fromLTRB(
      0,
      _paddingTop,
      _size.width - _priceAxisWidth,
      _size.height - _timeAxisHeight - _paddingBottom,
    );
  }

  // ---- horizontal window ------------------------------------------------
  double _startIndex = 0;
  double _visibleCount = 80;

  double get startIndex => _startIndex;
  double get visibleCount => _visibleCount;
  double get endIndex => _startIndex + _visibleCount;

  // ---- vertical window --------------------------------------------------
  double _minPrice = 0;
  double _maxPrice = 1;
  bool _manualPriceScale = false;

  double get minPrice => _minPrice;
  double get maxPrice => _maxPrice;
  bool get isPriceScaleManual => _manualPriceScale;

  // ---- candle count (set by controller) ---------------------------------
  int _candleCount = 0;
  int get candleCount => _candleCount;

  void setCandleCount(int n) {
    _candleCount = n;
  }

  // ---- public mutations -------------------------------------------------

  void setSize(Size size, {double? priceAxisWidth, double? timeAxisHeight}) {
    var changed = false;
    if (size != _size) {
      _size = size;
      changed = true;
    }
    if (priceAxisWidth != null && priceAxisWidth != _priceAxisWidth) {
      _priceAxisWidth = priceAxisWidth;
      changed = true;
    }
    if (timeAxisHeight != null && timeAxisHeight != _timeAxisHeight) {
      _timeAxisHeight = timeAxisHeight;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Pan by [dx] pixels (positive = content moves right = look at older).
  void panByPixels(double dx) {
    final plot = plotRect;
    if (plot.width <= 0 || _visibleCount <= 0) return;
    final dIndex = -dx / (plot.width / _visibleCount);
    _startIndex = (_startIndex + dIndex).clamp(
      _minStart(),
      _maxStart(),
    );
    notifyListeners();
  }

  /// Pinch-zoom anchored at [focalX] (local plot coordinate).
  void zoomAt(double focalX, double scaleDelta) {
    final plot = plotRect;
    if (plot.width <= 0) return;

    final fraction = ((focalX - plot.left) / plot.width).clamp(0.0, 1.0);
    final focalIndex = _startIndex + fraction * _visibleCount;

    final newCount = (_visibleCount / scaleDelta)
        .clamp(10.0, math.max(10.0, _candleCount * 1.5))
        .toDouble();
    _visibleCount = newCount;
    _startIndex = (focalIndex - fraction * _visibleCount).clamp(
      _minStart(),
      _maxStart(),
    );
    notifyListeners();
  }

  /// Jump so the newest candle is at the right edge (with a small right pad).
  void scrollToLatest({double rightPadSlots = 3}) {
    if (_candleCount == 0) return;
    _startIndex = (_candleCount - _visibleCount + rightPadSlots)
        .clamp(_minStart(), _maxStart());
    notifyListeners();
  }

  /// True when the newest candle is near the right edge.
  bool get isAtLiveEdge {
    if (_candleCount == 0) return true;
    return endIndex >= _candleCount - 2;
  }

  void setVisibleCount(double count) {
    _visibleCount = count.clamp(10.0, 5000.0);
    _startIndex = _startIndex.clamp(_minStart(), _maxStart());
    notifyListeners();
  }

  /// Auto-fit price range to the currently visible candles.
  void autoFitPrice(List<Candle> candles) {
    if (_manualPriceScale) return;
    if (candles.isEmpty) return;
    final first = startIndex.floor().clamp(0, candles.length - 1);
    final last = endIndex.ceil().clamp(0, candles.length - 1);
    if (first > last) return;

    var lo = double.infinity;
    var hi = double.negativeInfinity;
    for (var i = first; i <= last; i++) {
      final c = candles[i];
      if (c.low < lo) lo = c.low;
      if (c.high > hi) hi = c.high;
    }
    if (!lo.isFinite || !hi.isFinite) return;
    final fitted = PriceScale.autoFitRange(lo, hi);
    _minPrice = fitted.$1;
    _maxPrice = fitted.$2;
    notifyListeners();
  }

  /// Manual vertical scale: drag on the price axis.
  void scalePriceBy(double dy, double centreY) {
    final plot = plotRect;
    if (plot.height <= 0) return;
    _manualPriceScale = true;

    final range = _maxPrice - _minPrice;
    if (range <= 0) return;

    // Positive dy (finger down) → expand range (zoom out).
    final factor = 1.0 + dy / plot.height;
    final newRange = (range * factor).clamp(range * 0.01, range * 100);

    final centrePrice =
        _maxPrice - ((centreY - plot.top) / plot.height) * range;
    _minPrice = centrePrice - newRange * ((centreY - plot.top) / plot.height);
    _maxPrice = _minPrice + newRange;
    notifyListeners();
  }

  void resetPriceScale() {
    _manualPriceScale = false;
    notifyListeners();
  }

  void expandPriceRangeToInclude(double price) {
    if (price >= _minPrice && price <= _maxPrice) return;
    final pad = (_maxPrice - _minPrice) * 0.05;
    if (price < _minPrice) _minPrice = price - pad;
    if (price > _maxPrice) _maxPrice = price + pad;
    _manualPriceScale = true;
    notifyListeners();
  }

  void setPriceRange(double min, double max, {bool manual = false}) {
    _minPrice = min;
    _maxPrice = max;
    _manualPriceScale = manual;
    notifyListeners();
  }

  // ---- internal ---------------------------------------------------------

  double _minStart() => -_visibleCount * 0.1;
  double _maxStart() {
    if (_candleCount == 0) return 0;
    return math.max(0, _candleCount - _visibleCount * 0.5);
  }
}
