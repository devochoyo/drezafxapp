import '../contracts/chart_contracts.dart';

/// In-memory LRU cache of candle series keyed by (symbol, timeframe).
///
/// Capacity is intentionally small (~24 entries) — enough for the pairs a
/// user is likely to flip between during a session.
class CandleCache {
  CandleCache({this.maxEntries = 24});

  final int maxEntries;

  final Map<String, List<Candle>> _store = {};
  final List<String> _order = []; // most-recently-used at the end

  static String _key(String symbol, ChartTimeframe tf) =>
      '${symbol.toUpperCase()}|${tf.name}';

  /// Returns a defensive copy of the cached list, or null.
  List<Candle>? get(String symbol, ChartTimeframe timeframe) {
    final k = _key(symbol, timeframe);
    final list = _store[k];
    if (list == null) return null;
    _touch(k);
    return List<Candle>.from(list);
  }

  /// Stores [candles] (must already be sorted oldest→newest, de-duplicated).
  void put(String symbol, ChartTimeframe timeframe, List<Candle> candles) {
    final k = _key(symbol, timeframe);
    _store[k] = List<Candle>.from(candles);
    _touch(k);
    _evict();
  }

  /// Merge [incoming] into any existing entry for the key.
  /// Rules: same time → replace; newer → append; older → ignore if already
  /// present; result stays sorted; invalid candles rejected.
  void merge(String symbol, ChartTimeframe timeframe, List<Candle> incoming) {
    if (incoming.isEmpty) return;
    final k = _key(symbol, timeframe);
    final existing = _store[k];
    if (existing == null || existing.isEmpty) {
      put(symbol, timeframe, _sanitize(incoming));
      return;
    }
    final merged = _mergeLists(existing, incoming);
    _store[k] = merged;
    _touch(k);
  }

  void clear() {
    _store.clear();
    _order.clear();
  }

  // ----------------------------------------------------------------- helpers

  void _touch(String k) {
    _order.remove(k);
    _order.add(k);
  }

  void _evict() {
    while (_order.length > maxEntries) {
      final oldest = _order.removeAt(0);
      _store.remove(oldest);
    }
  }

  static List<Candle> _sanitize(List<Candle> src) {
    final out = <Candle>[];
    for (final c in src) {
      if (_valid(c)) out.add(c);
    }
    out.sort((a, b) => a.time.compareTo(b.time));
    return _dedupe(out);
  }

  static List<Candle> _mergeLists(List<Candle> a, List<Candle> b) {
    final map = <int, Candle>{};
    for (final c in a) {
      if (_valid(c)) map[c.time] = c;
    }
    for (final c in b) {
      if (_valid(c)) map[c.time] = c; // newer wins
    }
    final keys = map.keys.toList()..sort();
    return [for (final k in keys) map[k]!];
  }

  static List<Candle> _dedupe(List<Candle> sorted) {
    if (sorted.length < 2) return sorted;
    final out = <Candle>[sorted.first];
    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i].time != out.last.time) {
        out.add(sorted[i]);
      } else {
        out[out.length - 1] = sorted[i]; // keep last
      }
    }
    return out;
  }

  static bool _valid(Candle c) {
    if (c.open.isNaN || c.high.isNaN || c.low.isNaN || c.close.isNaN) {
      return false;
    }
    if (c.open <= 0 || c.high <= 0 || c.low <= 0 || c.close <= 0) return false;
    if (c.high < c.low) return false;
    return true;
  }
}
