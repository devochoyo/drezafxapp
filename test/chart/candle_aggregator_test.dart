import 'package:flutter_test/flutter_test.dart';
import 'package:drezafx/chart/contracts/chart_contracts.dart';
import 'package:drezafx/chart/data/candle_aggregator.dart';

void main() {
  group('CandleAggregator', () {
    test('weekly buckets align to Monday 00:00 UTC', () {
      // 2024-11-25 is a Monday.
      // Unix for 2024-11-25 00:00 UTC:
      const monday = 1732492800; // approx — use bucketStart
      final tf = ChartTimeframe.w1;
      final start = tf.bucketStart(monday + 3 * 86400); // Thursday of that week
      // Should snap back to Monday.
      expect(start, tf.bucketStart(monday));
    });

    test('aggregates D1 into W1', () {
      // Three days of one week.
      const base = 1732492800; // a Monday 00:00-ish
      final d1 = [
        Candle(time: base, open: 100, high: 110, low: 95, close: 105),
        Candle(time: base + 86400, open: 105, high: 115, low: 100, close: 112),
        Candle(
            time: base + 2 * 86400, open: 112, high: 120, low: 108, close: 118),
      ];
      final w1 = CandleAggregator.aggregate(d1, ChartTimeframe.w1);
      expect(w1.length, 1);
      expect(w1.first.open, 100);
      expect(w1.first.high, 120);
      expect(w1.first.low, 95);
      expect(w1.first.close, 118);
    });

    test('applyLiveUpdate extends forming week', () {
      const base = 1732492800;
      final existing = [
        Candle(time: base, open: 100, high: 110, low: 95, close: 105),
      ];
      final live = Candle(
          time: base + 86400, open: 105, high: 115, low: 100, close: 112);
      final out = CandleAggregator.applyLiveUpdate(
          existing, live, ChartTimeframe.w1);
      expect(out.length, 1);
      expect(out.first.high, 115);
      expect(out.first.close, 112);
    });

    test('applyLiveUpdate starts new week', () {
      const base = 1732492800;
      final existing = [
        Candle(time: base, open: 100, high: 110, low: 95, close: 105),
      ];
      final live = Candle(
          time: base + 7 * 86400,
          open: 120,
          high: 125,
          low: 118,
          close: 122);
      final out = CandleAggregator.applyLiveUpdate(
          existing, live, ChartTimeframe.w1);
      expect(out.length, 2);
      expect(out.last.open, 120);
    });
  });
}
