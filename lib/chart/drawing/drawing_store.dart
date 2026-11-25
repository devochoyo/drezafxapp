import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'drawing_models.dart';

/// Per-symbol drawing persistence.
///
/// Key: `chart.drawings.v1.<SYMBOL>` → JSON list of shapes.
class DrawingStore {
  DrawingStore({SharedPreferencesAsync? prefs})
      : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;
  Timer? _debounce;

  static String _key(String symbol) =>
      'chart.drawings.v1.${symbol.toUpperCase()}';

  Future<List<DrawingShape>> load(String symbol) async {
    try {
      final raw = await _prefs.getString(_key(symbol));
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <DrawingShape>[];
      for (final item in decoded) {
        final s = DrawingShape.tryFromJson(item);
        if (s != null) out.add(s);
      }
      return out;
    } catch (_) {
      // Corrupt data → start empty, never crash.
      return const [];
    }
  }

  /// Debounced save (~300 ms) after each completed edit.
  void saveDebounced(String symbol, List<DrawingShape> shapes) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      saveNow(symbol, shapes);
    });
  }

  Future<void> saveNow(String symbol, List<DrawingShape> shapes) async {
    try {
      final list = [for (final s in shapes) s.toJson()];
      await _prefs.setString(_key(symbol), jsonEncode(list));
    } catch (_) {
      // Persistence failure must not crash the chart.
    }
  }

  Future<void> flush(String symbol, List<DrawingShape> shapes) async {
    _debounce?.cancel();
    await saveNow(symbol, shapes);
  }

  void dispose() {
    _debounce?.cancel();
  }
}
