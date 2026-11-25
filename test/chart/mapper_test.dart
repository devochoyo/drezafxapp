import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:drezafx/chart/contracts/chart_contracts.dart';
import 'package:drezafx/chart/engine/mapper_impl.dart';
import 'package:drezafx/chart/engine/viewport.dart';

void main() {
  group('MapperImpl', () {
    late Viewport vp;
    late MapperImpl mapper;
    late List<Candle> candles;

    setUp(() {
      candles = [
        for (var i = 0; i < 100; i++)
          Candle(
            time: 1700000000 + i * 3600,
            open: 100 + i * 0.1,
            high: 101 + i * 0.1,
            low: 99 + i * 0.1,
            close: 100.5 + i * 0.1,
          ),
      ];
      vp = Viewport();
      vp.setSize(const Size(400, 300), priceAxisWidth: 68, timeAxisHeight: 22);
      vp.setCandleCount(candles.length);
      vp.setVisibleCount(50);
      vp.scrollToLatest();
      vp.setPriceRange(90, 120);
      mapper = MapperImpl(
        viewport: vp,
        candles: candles,
        timeframe: ChartTimeframe.h1,
        pricePrecision: 5,
      );
    });

    test('priceToY / yToPrice round-trip', () {
      for (final p in [95.0, 100.0, 110.0, 115.0]) {
        final y = mapper.priceToY(p);
        final back = mapper.yToPrice(y);
        expect(back, closeTo(p, 1e-6));
      }
    });

    test('timeToX / xToTime round-trip for existing candles', () {
      for (final c in [candles[10], candles[50], candles[90]]) {
        final x = mapper.timeToX(c.time);
        final back = mapper.xToTime(x);
        expect(back, closeTo(c.time, 2));
      }
    });

    test('future time extrapolates', () {
      final last = candles.last;
      final future = last.time + 3600 * 5;
      final x = mapper.timeToX(future);
      final lastX = mapper.timeToX(last.time);
      expect(x, greaterThan(lastX));
    });

    test('candleAtX returns nearest', () {
      final c = candles[60];
      final x = mapper.timeToX(c.time);
      final found = mapper.candleAtX(x);
      expect(found, isNotNull);
      expect(found!.time, c.time);
    });
  });
}
