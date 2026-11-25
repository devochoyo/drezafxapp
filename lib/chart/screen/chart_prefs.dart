import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../contracts/chart_contracts.dart';

/// Persists last-used symbol and timeframe.
///
/// Key: `chart.prefs.v1` → `{"symbol":"GBPJPY","tf":"h1"}`
class ChartPrefs {
  ChartPrefs({SharedPreferencesAsync? prefs})
      : _prefs = prefs ?? SharedPreferencesAsync();

  static const _key = 'chart.prefs.v1';

  final SharedPreferencesAsync _prefs;

  Future<({String symbol, ChartTimeframe timeframe})> load({
    required String defaultSymbol,
    ChartTimeframe defaultTimeframe = ChartTimeframe.defaultTimeframe,
  }) async {
    try {
      final raw = await _prefs.getString(_key);
      if (raw == null || raw.isEmpty) {
        return (symbol: defaultSymbol, timeframe: defaultTimeframe);
      }
      final map = jsonDecode(raw);
      if (map is! Map) {
        return (symbol: defaultSymbol, timeframe: defaultTimeframe);
      }
      final sym = map['symbol'];
      final tfName = map['tf'];
      final symbol = (sym is String && sym.length == 6)
          ? sym.toUpperCase()
          : defaultSymbol;
      final timeframe = _tfFromName(tfName) ?? defaultTimeframe;
      return (symbol: symbol, timeframe: timeframe);
    } catch (_) {
      return (symbol: defaultSymbol, timeframe: defaultTimeframe);
    }
  }

  Future<void> save(String symbol, ChartTimeframe timeframe) async {
    try {
      await _prefs.setString(
        _key,
        jsonEncode({
          'symbol': symbol.toUpperCase(),
          'tf': timeframe.name,
        }),
      );
    } catch (_) {
      // Persistence failure must never crash the chart.
    }
  }

  static ChartTimeframe? _tfFromName(Object? name) {
    if (name is! String) return null;
    for (final tf in ChartTimeframe.values) {
      if (tf.name == name) return tf;
    }
    return null;
  }
}
