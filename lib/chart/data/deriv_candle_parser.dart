import 'dart:convert';

import '../contracts/chart_contracts.dart';

/// Parses Deriv WebSocket messages for historical candles and live OHLC.
///
/// Expected history response:
/// ```json
/// {"msg_type":"candles","candles":[{"epoch":...,"open":...,"high":...,"low":...,"close":...}, ...]}
/// ```
///
/// Expected live update:
/// ```json
/// {"msg_type":"ohlc","ohlc":{"open_time":...,"open":...,"high":...,"low":...,"close":...,"granularity":...,"symbol":...,"id":...}}
/// ```
class DerivCandleParser {
  DerivCandleParser._();

  /// Parse a `candles` history payload into a sorted list (oldest first).
  /// Invalid / incomplete candles are skipped.
  static List<Candle> parseCandlesMessage(Object? decoded) {
    if (decoded is! Map) return const [];
    final raw = decoded['candles'];
    if (raw is! List) return const [];
    final out = <Candle>[];
    for (final item in raw) {
      final c = _parseCandleMap(item, epochKey: 'epoch');
      if (c != null) out.add(c);
    }
    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }

  /// Parse a live `ohlc` message. Returns null when the payload is unusable.
  static Candle? parseOhlcMessage(Object? decoded) {
    if (decoded is! Map) return null;
    final ohlc = decoded['ohlc'];
    return _parseCandleMap(ohlc, epochKey: 'open_time');
  }

  /// Extract the subscription id from a live candles / ohlc reply.
  static String? subscriptionId(Object? decoded) {
    if (decoded is! Map) return null;
    final sub = decoded['subscription'];
    if (sub is Map && sub['id'] is String) return sub['id'] as String;
    final ohlc = decoded['ohlc'];
    if (ohlc is Map && ohlc['id'] is String) return ohlc['id'] as String;
    return null;
  }

  /// Decode a raw WebSocket string; returns null on parse failure.
  static Object? decode(String data) {
    try {
      return jsonDecode(data);
    } catch (_) {
      return null;
    }
  }

  static Candle? _parseCandleMap(Object? raw, {required String epochKey}) {
    if (raw is! Map) return null;
    final time = _toInt(raw[epochKey]);
    final open = _toDouble(raw['open']);
    final high = _toDouble(raw['high']);
    final low = _toDouble(raw['low']);
    final close = _toDouble(raw['close']);
    if (time == null || open == null || high == null || low == null || close == null) {
      return null;
    }
    if (!_isValid(open, high, low, close)) return null;
    return Candle(time: time, open: open, high: high, low: low, close: close);
  }

  static bool _isValid(double o, double h, double l, double c) {
    if (o.isNaN || h.isNaN || l.isNaN || c.isNaN) return false;
    if (o <= 0 || h <= 0 || l <= 0 || c <= 0) return false;
    if (h < l) return false;
    if (h < o || h < c) return false;
    if (l > o || l > c) return false;
    return true;
  }

  static int? _toInt(Object? v) {
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static double? _toDouble(Object? v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}
