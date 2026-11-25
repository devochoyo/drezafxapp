import '../contracts/chart_contracts.dart';

/// Aggregates lower-timeframe candles into higher ones (primarily D1 → W1).
///
/// Weekly buckets start on **Monday 00:00 UTC** (Unix epoch is a Thursday,
/// so the offset is 4 days).
class CandleAggregator {
  CandleAggregator._();

  /// Aggregate a list of source candles (already sorted oldest→newest) into
  /// the target [timeframe]. Only `ChartTimeframe.w1` is currently derived.
  static List<Candle> aggregate(
    List<Candle> source,
    ChartTimeframe target,
  ) {
    if (source.isEmpty) return const [];
    if (!target.isDerived) return List<Candle>.from(source);

    final buckets = <int, _Bucket>{};
    for (final c in source) {
      final start = target.bucketStart(c.time);
      final b = buckets.putIfAbsent(start, () => _Bucket(start));
      b.add(c);
    }

    final keys = buckets.keys.toList()..sort();
    return [for (final k in keys) buckets[k]!.toCandle()];
  }

  /// Apply a live D1 (or lower) update into an existing weekly series.
  /// Returns a new list (or the same list if nothing changed).
  static List<Candle> applyLiveUpdate(
    List<Candle> weekly,
    Candle liveSource,
    ChartTimeframe target,
  ) {
    if (!target.isDerived) return weekly;
    final start = target.bucketStart(liveSource.time);
    if (weekly.isEmpty) {
      return [Candle(
        time: start,
        open: liveSource.open,
        high: liveSource.high,
        low: liveSource.low,
        close: liveSource.close,
      )];
    }

    final last = weekly.last;
    if (last.time == start) {
      // Update forming week.
      final updated = Candle(
        time: start,
        open: last.open,
        high: liveSource.high > last.high ? liveSource.high : last.high,
        low: liveSource.low < last.low ? liveSource.low : last.low,
        close: liveSource.close,
      );
      if (updated == last) return weekly;
      final copy = List<Candle>.from(weekly);
      copy[copy.length - 1] = updated;
      return copy;
    }
    if (start > last.time) {
      // New week started.
      return [
        ...weekly,
        Candle(
          time: start,
          open: liveSource.open,
          high: liveSource.high,
          low: liveSource.low,
          close: liveSource.close,
        ),
      ];
    }
    // Older update — ignore.
    return weekly;
  }
}

class _Bucket {
  _Bucket(this.start);
  final int start;
  double? open;
  double high = double.negativeInfinity;
  double low = double.infinity;
  double? close;

  void add(Candle c) {
    open ??= c.open;
    if (c.high > high) high = c.high;
    if (c.low < low) low = c.low;
    close = c.close;
  }

  Candle toCandle() => Candle(
        time: start,
        open: open!,
        high: high,
        low: low,
        close: close!,
      );
}
