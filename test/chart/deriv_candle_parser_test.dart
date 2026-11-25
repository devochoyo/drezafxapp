import 'package:flutter_test/flutter_test.dart';
import 'package:drezafx/chart/data/deriv_candle_parser.dart';

void main() {
  group('DerivCandleParser', () {
    test('parses candles history message', () {
      final decoded = {
        'msg_type': 'candles',
        'candles': [
          {
            'epoch': 1700000000,
            'open': 1.0850,
            'high': 1.0860,
            'low': 1.0840,
            'close': 1.0855,
          },
          {
            'epoch': 1700003600,
            'open': 1.0855,
            'high': 1.0870,
            'low': 1.0850,
            'close': 1.0865,
          },
        ],
      };
      final list = DerivCandleParser.parseCandlesMessage(decoded);
      expect(list.length, 2);
      expect(list.first.time, 1700000000);
      expect(list.first.open, 1.0850);
      expect(list.last.close, 1.0865);
    });

    test('parses ohlc live message', () {
      final decoded = {
        'msg_type': 'ohlc',
        'ohlc': {
          'open_time': 1700000000,
          'open': 208.1,
          'high': 208.5,
          'low': 207.9,
          'close': 208.3,
          'granularity': 1800,
          'symbol': 'frxGBPJPY',
          'id': 'abc-123',
        },
        'subscription': {'id': 'abc-123'},
      };
      final c = DerivCandleParser.parseOhlcMessage(decoded);
      expect(c, isNotNull);
      expect(c!.time, 1700000000);
      expect(c.close, 208.3);
      expect(DerivCandleParser.subscriptionId(decoded), 'abc-123');
    });

    test('rejects invalid candles', () {
      final decoded = {
        'candles': [
          {'epoch': 1, 'open': 1, 'high': 0.5, 'low': 2, 'close': 1},
          {'epoch': 2, 'open': 'bad', 'high': 1, 'low': 1, 'close': 1},
        ],
      };
      final list = DerivCandleParser.parseCandlesMessage(decoded);
      expect(list, isEmpty);
    });

    test('sorts by time', () {
      final decoded = {
        'candles': [
          {'epoch': 200, 'open': 1, 'high': 2, 'low': 0.5, 'close': 1.5},
          {'epoch': 100, 'open': 1, 'high': 2, 'low': 0.5, 'close': 1.5},
        ],
      };
      final list = DerivCandleParser.parseCandlesMessage(decoded);
      expect(list.first.time, 100);
      expect(list.last.time, 200);
    });
  });
}
