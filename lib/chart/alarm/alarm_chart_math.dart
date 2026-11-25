import 'dart:math' as math;

import '../../models/currency_pair.dart';

/// Price rounding / clamping helpers for chart alarm lines.
class AlarmChartMath {
  AlarmChartMath._();

  /// Round [price] to the pair's [pricePrecision] (tick-aligned).
  static double roundToPrecision(double price, int pricePrecision) {
    if (!price.isFinite || pricePrecision < 0) return price;
    final factor = math.pow(10, pricePrecision).toDouble();
    return (price * factor).round() / factor;
  }

  /// Round using a symbol string (e.g. "GBPJPY").
  static double roundForSymbol(double price, String symbol) {
    final pair = CurrencyPair.tryParse(symbol);
    final prec = pair?.pricePrecision ?? 5;
    return roundToPrecision(price, prec);
  }

  /// Clamp [price] into [min]..[max] and ensure > 0.
  static double clampPrice(double price, double min, double max) {
    var p = price;
    if (p < min) p = min;
    if (p > max) p = max;
    if (p <= 0) p = min > 0 ? min : 0.00001;
    return p;
  }

  /// Distance label from [linePrice] to [lastPrice], e.g. `+0.162 (0.08%)`.
  static String distanceLabel(double linePrice, double lastPrice, int prec) {
    final delta = linePrice - lastPrice;
    final pct = lastPrice == 0 ? 0.0 : (delta / lastPrice) * 100;
    final sign = delta >= 0 ? '+' : '';
    final arrow = delta >= 0 ? '▲' : '▼';
    return '$arrow $sign${delta.toStringAsFixed(prec)} '
        '(${pct.toStringAsFixed(2)}%)';
  }

  /// True when [y] is within [hitSlop] of the horizontal line at [lineY].
  static bool hitsHorizontalLine(double y, double lineY, {double hitSlop = 22}) {
    return (y - lineY).abs() <= hitSlop;
  }
}
