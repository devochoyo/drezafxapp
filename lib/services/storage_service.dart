import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/alarm_state.dart';
import '../models/alert_history.dart';
import '../models/app_settings.dart';
import '../models/forex_alert.dart';

/// Minimal async string key-value store. Lets the storage logic be tested
/// without Flutter plugins.
abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
  Future<Set<String>> keys();
}

/// Production store backed by [SharedPreferencesAsync]. Unlike the legacy
/// SharedPreferences API it has no in-memory cache, so the UI isolate and
/// the background-service isolate always see each other's writes.
class SharedPreferencesKeyValueStore implements KeyValueStore {
  SharedPreferencesKeyValueStore() : _prefs = SharedPreferencesAsync();
  final SharedPreferencesAsync _prefs;

  @override
  Future<String?> read(String key) => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) => _prefs.setString(key, value);

  @override
  Future<void> remove(String key) => _prefs.remove(key);

  @override
  Future<Set<String>> keys() => _prefs.getKeys();
}

/// In-memory store for tests.
class InMemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> remove(String key) async => _data.remove(key);

  @override
  Future<Set<String>> keys() async => _data.keys.toSet();
}

/// Persistent storage for alerts, history, settings and the alarm state.
///
/// Each alert is stored under its own key so the UI (editing one alert) and
/// the background isolate (marking another as triggered) do not overwrite
/// each other. Unreadable records are skipped instead of crashing the app.
class StorageService {
  StorageService(this._store);

  final KeyValueStore _store;

  static const _alertPrefix = 'drezafx.alert.';
  static const _historyKey = 'drezafx.history';
  static const _settingsKey = 'drezafx.settings';
  static const _alarmStateKey = 'drezafx.alarm_state';

  /// Oldest history entries beyond this count are dropped.
  static const int maxHistoryEntries = 500;

  Future<void> _historyLock = Future.value();

  // ---------------------------------------------------------------- alerts

  /// All alerts, newest first.
  Future<List<ForexAlert>> getAlerts({AlertStatus? status}) async {
    final keys = (await _store.keys()).where((k) => k.startsWith(_alertPrefix));
    final alerts = <ForexAlert>[];
    for (final key in keys) {
      final alert = await _decodeAlert(await _store.read(key));
      if (alert != null && (status == null || alert.status == status)) {
        alerts.add(alert);
      }
    }
    alerts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return alerts;
  }

  Future<ForexAlert?> getAlert(String id) async =>
      _decodeAlert(await _store.read('$_alertPrefix$id'));

  /// Creates or overwrites [alert].
  Future<void> saveAlert(ForexAlert alert) =>
      _store.write('$_alertPrefix${alert.id}', jsonEncode(alert.toJson()));

  Future<void> deleteAlert(String id) => _store.remove('$_alertPrefix$id');

  ForexAlert? _tryDecodeAlert(String? raw) {
    if (raw == null) return null;
    try {
      return ForexAlert.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<ForexAlert?> _decodeAlert(String? raw) async => _tryDecodeAlert(raw);

  // --------------------------------------------------------------- history

  /// History, newest first.
  Future<List<AlertHistory>> getHistory() async {
    final raw = await _store.read(_historyKey);
    if (raw == null) return [];
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => AlertHistory.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      list.sort((a, b) => b.triggeredAt.compareTo(a.triggeredAt));
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> addHistory(AlertHistory entry) => _withHistoryLock(() async {
        final list = await getHistory();
        list.insert(0, entry);
        await _writeHistory(list.take(maxHistoryEntries).toList());
      });

  /// Marks the history entry [historyId] as acknowledged (alarm stopped).
  Future<void> markHistoryAlarmStopped(String historyId, DateTime at) =>
      _withHistoryLock(() async {
        final list = await getHistory();
        final index = list.indexWhere((h) => h.id == historyId);
        if (index == -1) return;
        list[index] = list[index].copyWith(alarmStoppedAt: at);
        await _writeHistory(list);
      });

  Future<void> clearHistory() => _withHistoryLock(() => _store.remove(_historyKey));

  Future<void> _writeHistory(List<AlertHistory> list) =>
      _store.write(_historyKey, jsonEncode(list.map((h) => h.toJson()).toList()));

  Future<void> _withHistoryLock(Future<void> Function() action) {
    final next = _historyLock.then((_) => action());
    _historyLock = next.catchError((_) {});
    return next;
  }

  // -------------------------------------------------------------- settings

  Future<AppSettings> getSettings() async {
    final raw = await _store.read(_settingsKey);
    if (raw == null) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> saveSettings(AppSettings settings) =>
      _store.write(_settingsKey, jsonEncode(settings.toJson()));

  // ------------------------------------------------------------ alarm state

  /// Last persisted alarm state (lets a freshly opened UI see a ringing
  /// alarm that started in the background).
  Future<AlarmState> getAlarmState() async {
    final raw = await _store.read(_alarmStateKey);
    if (raw == null) return AlarmState.idle;
    try {
      return AlarmState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return AlarmState.idle;
    }
  }

  Future<void> saveAlarmState(AlarmState state) =>
      _store.write(_alarmStateKey, jsonEncode(state.toJson()));
}
