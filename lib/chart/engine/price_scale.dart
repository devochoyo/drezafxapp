import 'dart:math' as math;

/// Generates "nice" price-axis steps using a 1-2-5 progression.
class PriceScale {
  PriceScale._();

  /// Returns a list of price levels (lowest → highest) that cover
  /// [minPrice]..[maxPrice] with approximately [targetCount] labels.
  static List<double> niceSteps(
    double minPrice,
    double maxPrice, {
    int targetCount = 6,
  }) {
    if (maxPrice <= minPrice || !minPrice.isFinite || !maxPrice.isFinite) {
      return const [];
    }
    final range = maxPrice - minPrice;
    if (range <= 0) return [minPrice];

    final rawStep = range / math.max(1, targetCount - 1);
    final nice = _niceNumber(rawStep);

    // Align first step to a multiple of `nice` at or below minPrice.
    var start = (minPrice / nice).floor() * nice;
    if (start < minPrice - nice * 0.01) start += nice;

    final steps = <double>[];
    // Guard against infinite loops on pathological floats.
    for (var i = 0; i < 40; i++) {
      final v = start + i * nice;
      if (v > maxPrice + nice * 0.01) break;
      if (v >= minPrice - nice * 0.01) steps.add(v);
    }
    return steps;
  }

  /// Round [value] to the nearest "nice" magnitude (1, 2 or 5 × 10^n).
  static double _niceNumber(double value) {
    if (value <= 0 || !value.isFinite) return 1.0;
    final exp = (math.log(value) / math.ln10).floor();
    final frac = value / math.pow(10, exp);
    double niceFrac;
    if (frac <= 1.0) {
      niceFrac = 1.0;
    } else if (frac <= 2.0) {
      niceFrac = 2.0;
    } else if (frac <= 5.0) {
      niceFrac = 5.0;
    } else {
      niceFrac = 10.0;
    }
    return niceFrac * math.pow(10, exp).toDouble();
  }

  /// Compute a padded auto-fit range that gives ~8 % headroom top and bottom.
  static (double min, double max) autoFitRange(
    double dataMin,
    double dataMax, {
    double padFraction = 0.08,
  }) {
    if (!dataMin.isFinite || !dataMax.isFinite) {
      return (0.0, 1.0);
    }
    if (dataMax <= dataMin) {
      final mid = dataMin;
      final pad = mid.abs() * 0.001 + 0.0001;
      return (mid - pad, mid + pad);
    }
    final range = dataMax - dataMin;
    final pad = range * padFraction;
    return (dataMin - pad, dataMax + pad);
  }
}
