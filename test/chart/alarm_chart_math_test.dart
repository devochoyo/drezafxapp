import 'package:flutter_test/flutter_test.dart';
import 'package:drezafx/chart/alarm/alarm_chart_math.dart';

void main() {
  group('AlarmChartMath', () {
    test('roundToPrecision', () {
      expect(AlarmChartMath.roundToPrecision(208.2624, 3), 208.262);
      expect(AlarmChartMath.roundToPrecision(1.0850123, 5), 1.08501);
    });

    test('roundForSymbol uses pair precision', () {
      // JPY pairs → 3 decimals
      expect(AlarmChartMath.roundForSymbol(208.26249, 'GBPJPY'), 208.262);
      // Standard → 5
      expect(AlarmChartMath.roundForSymbol(1.085012, 'EURUSD'), 1.08501);
      // XAU → 2
      expect(AlarmChartMath.roundForSymbol(2345.678, 'XAUUSD'), 2345.68);
    });

    test('clampPrice', () {
      expect(AlarmChartMath.clampPrice(50, 100, 200), 100);
      expect(AlarmChartMath.clampPrice(250, 100, 200), 200);
      expect(AlarmChartMath.clampPrice(150, 100, 200), 150);
      expect(AlarmChartMath.clampPrice(-1, 0.001, 10), 0.001);
    });

    test('hitsHorizontalLine', () {
      expect(AlarmChartMath.hitsHorizontalLine(100, 100), isTrue);
      expect(AlarmChartMath.hitsHorizontalLine(110, 100, hitSlop: 22), isTrue);
      expect(AlarmChartMath.hitsHorizontalLine(130, 100, hitSlop: 22), isFalse);
    });

    test('distanceLabel', () {
      final s = AlarmChartMath.distanceLabel(208.45, 208.288, 3);
      expect(s.contains('0.162') || s.contains('+'), isTrue);
    });
  });
}
