import 'dart:async';

import '../models/alarm_sound.dart';
import 'alarm_audio_service.dart';
import 'alert_evaluation_service.dart';
import 'alert_service.dart';
import 'background_monitoring_service.dart';
import 'notification_service.dart';
import 'storage_service.dart';

/// Single place that creates and wires the UI-isolate services.
///
/// State management approach (for all three batches): plain Dart service
/// objects exposing `Stream`s and `Future`s, reached through
/// `AppServices.instance`, consumed in widgets with StreamBuilder /
/// FutureBuilder. No third-party state-management package. Business logic
/// lives in services, never in widgets.
class AppServices {
  AppServices._();
  static final AppServices instance = AppServices._();

  late final StorageService storage;
  late final AlertEvaluationService evaluator;
  late final AlertService alerts;
  late final NotificationService notifications;
  late final AlarmAudioService alarm;
  late final BackgroundMonitoringService monitoring;

  bool _initialized = false;
  StreamSubscription<void>? _alertsUpdatedSub;

  /// Call once from `main()` before `runApp`.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    storage = StorageService(SharedPreferencesKeyValueStore());
    evaluator = const AlertEvaluationService();
    notifications = LocalNotificationService();
    alarm = AudioplayersAlarmAudioService();
    monitoring = BackgroundMonitoringService(storage);
    alerts = AlertService(storage, onAlertsChanged: monitoring.notifyAlertsChanged);

    // Channels must exist before the foreground service is configured/started.
    await notifications.initialize();
    await monitoring.configure();

    // Refresh alert lists when the service changes alerts (trigger, ack).
    _alertsUpdatedSub =
        monitoring.alertsUpdatedStream.listen((_) => alerts.notifyExternalChange());
  }

  /// Starts background monitoring (call from the foreground; request the
  /// notification permission first on Android 13+).
  Future<void> startMonitoring() => monitoring.start();

  Future<void> stopMonitoring() => monitoring.stop();

  /// Plays a sound preview in the UI isolate.
  Future<void> previewSound(AlarmSound sound) => alarm.previewSound(sound);

  /// Stops the real alarm (running in the service isolate) and any local
  /// preview.
  Future<void> stopAlarm() async {
    await alarm.stopAlarm();
    await monitoring.stopAlarm();
  }

  Future<void> dispose() async {
    await _alertsUpdatedSub?.cancel();
    await alerts.dispose();
    await alarm.dispose();
    await monitoring.dispose();
  }
}
