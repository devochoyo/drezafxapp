import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/forex_alert.dart';
import '../models/monitoring_status.dart';

/// Notification payload helpers. A tap on an alert notification delivers
/// `alert:<alertId>` so the UI can open the active-alarm screen.
class NotificationPayload {
  static const String _alertPrefix = 'alert:';
  static const String monitoring = 'monitoring';

  static String forAlert(String alertId) => '$_alertPrefix$alertId';

  /// The alert id in [payload], or null when it is not an alert payload.
  static String? alertIdFrom(String? payload) =>
      (payload != null && payload.startsWith(_alertPrefix))
          ? payload.substring(_alertPrefix.length)
          : null;
}

/// Notifications for DrezaFx.
///
/// Notifications are IN ADDITION to the repeating alarm audio
/// ([AlarmAudioService]); the alert channel is silent on purpose.
abstract class NotificationService {
  /// Creates channels and registers tap handling. Call once per isolate.
  Future<void> initialize();

  /// Asks for the Android 13+ notification permission. Returns true if granted.
  Future<bool> requestPermission();

  Future<bool> areNotificationsEnabled();

  /// Shows (or updates) the persistent monitoring notification.
  Future<void> showMonitoringStatus(MonitoringStatus status);

  /// Shows the high-priority "alert triggered" notification.
  Future<void> showAlertTriggered(ForexAlert alert, {bool vibrate = true});

  Future<void> cancelAlertNotification(String alertId);

  /// Payloads of notifications the user tapped while the app was running.
  Stream<String> get tapStream;

  /// Payload of the notification that launched the app from a closed state.
  Future<String?> getLaunchPayload();
}

/// [NotificationService] backed by flutter_local_notifications.
class LocalNotificationService implements NotificationService {
  /// Silent, low-importance channel of the persistent monitoring notification.
  /// MUST exist before the foreground service starts (see
  /// BackgroundMonitoringService).
  static const String monitoringChannelId = 'drezafx_monitoring';

  /// Channel for triggered alerts (high importance, no sound: audio comes from
  /// the alarm service).
  static const String alertChannelId = 'drezafx_alerts';

  /// Same alert channel without vibration. Android fixes a channel's vibration
  /// after creation, so "vibration off" uses this second channel.
  static const String alertQuietChannelId = 'drezafx_alerts_no_vibration';

  /// Vibration pattern for the alarm notification (ms: wait, buzz, wait, buzz).
  /// With the insistent flag Android repeats it until the notification is
  /// cancelled, which happens when the alarm is stopped.
  static final Int64List _vibrationPattern =
      Int64List.fromList(<int>[0, 800, 600, 800, 600]);

  /// Same ID as the foreground-service notification so status updates replace
  /// it in place.
  static const int monitoringNotificationId = 888;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final _taps = StreamController<String>.broadcast();
  String? _lastStatusText;
  bool _initialized = false;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    // Launcher icon as small icon for now. Replace with a monochrome
    // drawable (e.g. @drawable/ic_stat_drezafx) once the final icon exists.
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null) _taps.add(payload);
      },
    );
    final android = _android;
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      monitoringChannelId,
      'Monitoring status',
      description: 'Shows that DrezaFx is watching prices in the background.',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
      showBadge: false,
    ));
    await android?.createNotificationChannel(AndroidNotificationChannel(
      alertChannelId,
      'Price alerts',
      description: 'Shown when a price target is crossed. The alarm sound '
          'is played by the app itself.',
      importance: Importance.max,
      playSound: false,
      enableVibration: true,
      vibrationPattern: _vibrationPattern,
    ));
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      alertQuietChannelId,
      'Price alerts (no vibration)',
      description: 'Same as Price alerts, used when vibration is turned off.',
      importance: Importance.max,
      playSound: false,
      enableVibration: false,
    ));
    _initialized = true;
  }

  @override
  Future<bool> requestPermission() async =>
      await _android?.requestNotificationsPermission() ?? false;

  @override
  Future<bool> areNotificationsEnabled() async =>
      await _android?.areNotificationsEnabled() ?? false;

  @override
  Future<void> showMonitoringStatus(MonitoringStatus status) async {
    final String title;
    final String body;
    if (!status.isServiceRunning) {
      title = 'DrezaFx monitoring stopped';
      body = 'Price alerts are not being watched.';
    } else if (status.connection.isConnected) {
      title = 'DrezaFx is monitoring prices';
      body = '${status.activeAlertCount} active alert(s) - '
          '${status.watchedPairs.length} pair(s) watched';
    } else {
      title = 'DrezaFx: no live prices';
      body = status.connection.message ??
          'Waiting for the market-data connection (${status.connection.state.name}).';
    }
    final text = '$title|$body';
    if (text == _lastStatusText) return; // avoid redundant updates
    _lastStatusText = text;

    await _plugin.show(
      monitoringNotificationId,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          monitoringChannelId,
          'Monitoring status',
          channelDescription:
              'Shows that DrezaFx is watching prices in the background.',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          playSound: false,
          showWhen: false,
          onlyAlertOnce: true,
        ),
      ),
      payload: NotificationPayload.monitoring,
    );
  }

  @override
  Future<void> showAlertTriggered(ForexAlert alert,
      {bool vibrate = true}) async {
    final price = alert.triggerPrice ?? alert.targetPrice;
    final direction = alert.triggerDirection == CrossingDirection.downward
        ? 'crossed down'
        : 'crossed up';
    await _plugin.show(
      _alertNotificationId(alert.id),
      '${alert.pair.displayName} - ${alert.category.announcement}',
      'Target ${alert.pair.format(alert.targetPrice)} $direction '
          '(price ${alert.pair.format(price)})',
      NotificationDetails(
        android: AndroidNotificationDetails(
          vibrate ? alertChannelId : alertQuietChannelId,
          vibrate ? 'Price alerts' : 'Price alerts (no vibration)',
          channelDescription: 'Shown when a price target is crossed.',
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.alarm,
          fullScreenIntent: true,
          autoCancel: false,
          playSound: false,
          enableVibration: vibrate,
          vibrationPattern: vibrate ? _vibrationPattern : null,
          // 4 = FLAG_INSISTENT: repeat the vibration until the notification
          // is cancelled (cancelled by "STOP ALARM").
          additionalFlags: vibrate ? Int32List.fromList(<int>[4]) : null,
          visibility: NotificationVisibility.public,
        ),
      ),
      payload: NotificationPayload.forAlert(alert.id),
    );
  }

  @override
  Future<void> cancelAlertNotification(String alertId) =>
      _plugin.cancel(_alertNotificationId(alertId));

  @override
  Stream<String> get tapStream => _taps.stream;

  @override
  Future<String?> getLaunchPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp ?? false) {
      return details!.notificationResponse?.payload;
    }
    return null;
  }

  /// Stable positive id per alert, never equal to [monitoringNotificationId].
  static int _alertNotificationId(String alertId) =>
      1000 + (alertId.hashCode & 0x7fffffff) % 1000000;
}
