import '../contracts/chart_contracts.dart';

/// Helpers for choosing which time labels to draw and how to format them.
class TimeScale {
  TimeScale._();

  /// Pick label epochs so they never overlap given [candlePixelWidth].
  ///
  /// Returns a subset of candle times (plus any day-boundary markers).
  static List<int> selectLabelTimes({
    required List<Candle> candles,
    required int firstIndex,
    required int lastIndex,
    required double candlePixelWidth,
    required ChartTimeframe timeframe,
  }) {
    if (candles.isEmpty || firstIndex > lastIndex) return const [];

    // Minimum pixels between labels.
    const minPx = 72.0;
    final step = mathMax(1, (minPx / candlePixelWidth).ceil());

    final out = <int>[];
    var nextAllowed = firstIndex;
    for (var i = firstIndex; i <= lastIndex; i++) {
      if (i < nextAllowed) continue;
      out.add(candles[i].time);
      nextAllowed = i + step;
    }
    return out;
  }

  /// Format [epochSeconds] (UTC) for the axis, in the **device local** zone.
  static String formatLabel(int epochSeconds, ChartTimeframe tf) {
    final dt = DateTime.fromMillisecondsSinceEpoch(
      epochSeconds * 1000,
      isUtc: true,
    ).toLocal();

    if (tf == ChartTimeframe.d1 || tf == ChartTimeframe.w1) {
      return _monthDay(dt);
    }

    // Intraday: show date at day boundaries, otherwise HH:mm.
    if (dt.hour == 0 && dt.minute == 0) {
      return _monthDay(dt);
    }
    return '${_two(dt.hour)}:${_two(dt.minute)}';
  }

  static String _monthDay(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }

  static String _two(int n) => n < 10 ? '0$n' : '$n';

  static int mathMax(int a, int b) => a > b ? a : b;
}
