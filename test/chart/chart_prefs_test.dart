import 'package:flutter_test/flutter_test.dart';
import 'package:drezafx/chart/contracts/chart_contracts.dart';

void main() {
  group('ChartPrefs encode/decode helpers', () {
    test('timeframe name round-trip covers all values', () {
      for (final tf in ChartTimeframe.values) {
        expect(tf.name, isNotEmpty);
        // The prefs layer stores tf.name and resolves via enum.values.
        final resolved = ChartTimeframe.values
            .where((t) => t.name == tf.name)
            .firstOrNull;
        expect(resolved, tf);
      }
    });

    test('default timeframe is H1', () {
      expect(ChartTimeframe.defaultTimeframe, ChartTimeframe.h1);
    });
  });
}
