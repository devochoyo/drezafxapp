import 'package:flutter_test/flutter_test.dart';
import 'package:drezafx/chart/engine/price_scale.dart';

void main() {
  group('PriceScale', () {
    test('niceSteps produces 1-2-5 progression', () {
      final steps = PriceScale.niceSteps(100, 200, targetCount: 5);
      expect(steps, isNotEmpty);
      expect(steps.first, lessThanOrEqualTo(100));
      expect(steps.last, greaterThanOrEqualTo(200));
      // Differences should be constant.
      if (steps.length >= 2) {
        final d = steps[1] - steps[0];
        for (var i = 2; i < steps.length; i++) {
          expect(steps[i] - steps[i - 1], closeTo(d, 1e-9));
        }
      }
    });

    test('autoFitRange adds padding', () {
      final (lo, hi) = PriceScale.autoFitRange(100, 110);
      expect(lo, lessThan(100));
      expect(hi, greaterThan(110));
    });

    test('autoFitRange handles flat data', () {
      final (lo, hi) = PriceScale.autoFitRange(50, 50);
      expect(hi, greaterThan(lo));
    });
  });
}
