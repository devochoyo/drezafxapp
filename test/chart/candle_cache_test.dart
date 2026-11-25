import 'package:flutter_test/flutter_test.dart';
import 'package:drezafx/chart/contracts/chart_contracts.dart';
import 'package:drezafx/chart/data/candle_cache.dart';

void main() {
  group('CandleCache', () {
    test('put / get round-trip', () {
      final cache = CandleCache(maxEntries: 4);
      final candles = [
        const Candle(time: 100, open: 1, high: 2, low: 0.5, close: 1.5),
        const Candle(time: 200, open: 1.5, high: 2.5, low: 1.2, close: 2.0),
      ];
      cache.put('GBPJPY', ChartTimeframe.h1, candles);
      final got = cache.get('GBPJPY', ChartTimeframe.h1);
      expect(got, isNotNull);
      expect(got!.length, 2);
      expect(got.first.time, 100);
    });

    test('merge replaces same time, appends newer', () {
      final cache = CandleCache();
      cache.put('EURUSD', ChartTimeframe.m15, [
        const Candle(time: 100, open: 1, high: 2, low: 0.5, close: 1.5),
      ]);
      cache.merge('EURUSD', ChartTimeframe.m15, [
        const Candle(time: 100, open: 1, high: 3, low: 0.5, close: 2.5),
        const Candle(time: 200, open: 2.5, high: 3, low: 2, close: 2.8),
      ]);
      final got = cache.get('EURUSD', ChartTimeframe.m15)!;
      expect(got.length, 2);
      expect(got.first.high, 3);
      expect(got.last.time, 200);
    });

    test('rejects invalid candles', () {
      final cache = CandleCache();
      cache.put('XAUUSD', ChartTimeframe.h1, [
        const Candle(time: 100, open: 1, high: 2, low: 0.5, close: 1.5),
        const Candle(time: 200, open: double.nan, high: 2, low: 1, close: 1.5),
        const Candle(time: 300, open: 1, high: 0.5, low: 2, close: 1), // high < low
      ]);
      final got = cache.get('XAUUSD', ChartTimeframe.h1)!;
      expect(got.length, 1);
    });

    test('LRU eviction', () {
      final cache = CandleCache(maxEntries: 2);
      cache.put('A', ChartTimeframe.h1, [
        const Candle(time: 1, open: 1, high: 1, low: 1, close: 1),
      ]);
      cache.put('B', ChartTimeframe.h1, [
        const Candle(time: 1, open: 1, high: 1, low: 1, close: 1),
      ]);
      cache.put('C', ChartTimeframe.h1, [
        const Candle(time: 1, open: 1, high: 1, low: 1, close: 1),
      ]);
      expect(cache.get('A', ChartTimeframe.h1), isNull);
      expect(cache.get('B', ChartTimeframe.h1), isNotNull);
      expect(cache.get('C', ChartTimeframe.h1), isNotNull);
    });
  });
}
