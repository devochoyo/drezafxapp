import 'dart:async';

import '../models/app_settings.dart';
import '../screens/contracts/stage2_contracts.dart' as ui;
import 'background_monitoring_service.dart';
import 'notification_service.dart';
import 'screen_mappers.dart';
import 'storage_service.dart';
import 'system_actions.dart';

/// Connects the screens' SettingsGateway to StorageService (persistent
/// settings), NotificationService (permission), the monitoring service
/// (status) and SystemActions (battery settings, version).
///
/// Unknown system states are reported as unknown, never as success.
class SettingsAdapter implements ui.SettingsGateway {
  SettingsAdapter({
    required StorageService storage,
    required NotificationService notifications,
    required BackgroundMonitoringService monitoring,
    SystemActions? system,
    this.statusPollInterval = const Duration(seconds: 2),
  })  : _storage = storage,
        _notifications = notifications,
        _monitoring = monitoring,
        _system = system ?? SystemActions();

  final StorageService _storage;
  final NotificationService _notifications;
  final BackgroundMonitoringService _monitoring;
  final SystemActions _system;
  final Duration statusPollInterval;
  final _changes = StreamController<AppSettings>.broadcast();

  ui.AppSettings _toScreen(AppSettings s) => ui.AppSettings(
        notificationsEnabled: s.notificationsEnabled,
        vibrationEnabled: s.vibrationEnabled,
        defaultSoundFile: s.defaultSound.fileName,
      );

  @override
  Stream<ui.AppSettings> watchSettings() async* {
    yield _toScreen(await _storage.getSettings());
    yield* _changes.stream.map(_toScreen);
  }

  Future<void> _save(AppSettings Function(AppSettings) change) async {
    final next = change(await _storage.getSettings());
    await _storage.saveSettings(next);
    if (!_changes.isClosed) _changes.add(next);
  }

  @override
  Future<void> setNotificationsEnabled(bool enabled) async {
    if (enabled) await _notifications.requestPermission();
    await _save((s) => s.copyWith(notificationsEnabled: enabled));
  }

  @override
  Future<void> setVibrationEnabled(bool enabled) =>
      _save((s) => s.copyWith(vibrationEnabled: enabled));

  @override
  Future<void> setDefaultSoundFile(String soundFile) {
    final sound = soundFromFile(soundFile);
    return _save((s) => s.copyWith(defaultSound: sound));
  }

  Future<ui.SystemStatus> _readStatus() async {
    ui.NotificationPermission permission;
    try {
      permission = await _notifications.areNotificationsEnabled()
          ? ui.NotificationPermission.granted
          : ui.NotificationPermission.denied;
    } catch (_) {
      permission = ui.NotificationPermission.unknown;
    }

    final ignoring = await _system.isIgnoringBatteryOptimizations();
    final battery = ignoring == null
        ? ui.BatteryOptimization.unknown
        : (ignoring
            ? ui.BatteryOptimization.unrestricted
            : ui.BatteryOptimization.optimized);

    final status = _monitoring.currentStatus;
    return ui.SystemStatus(
      notificationPermission: permission,
      monitoringActive: status.isServiceRunning && status.activeAlertCount > 0,
      backgroundServiceRunning: status.isServiceRunning,
      battery: battery,
      // There is no connectivity check in the foundation. "Connected" is only
      // reported when the market-data connection itself is connected; any
      // other case is unknown (null), not "not connected".
      internetConnected: status.connection.isConnected ? true : null,
    );
  }

  @override
  Stream<ui.SystemStatus> watchSystemStatus() async* {
    yield await _readStatus();
    yield* Stream<void>.periodic(statusPollInterval).asyncMap((_) => _readStatus());
  }

  @override
  Future<void> requestNotificationPermission() async {
    await _notifications.requestPermission();
  }

  @override
  Future<void> openBatterySettings() => _system.openBatterySettings();

  @override
  Future<String> appVersion() => _system.appVersion();

  Future<void> dispose() async {
    await _changes.close();
  }
}
