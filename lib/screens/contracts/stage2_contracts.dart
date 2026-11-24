import 'dart:async';
import 'package:flutter/widgets.dart';
import 'screen_contracts.dart';

// ---------------------------------------------------------------------------
// STAGE-2 SCREEN-SIDE CONTRACTS (AI 3).
//
// Same philosophy as screen_contracts.dart (AI 2): these are NOT AI 1's models
// or services. They describe exactly what the Active Alarm, Alert History and
// Settings screens need. AI 4 writes thin adapters from AI 1's real classes.
// AI 2's contracts are untouched; AlertCategory is reused.
// No direction (above/below/buy/sell) exists anywhere in these types.
// ---------------------------------------------------------------------------

/// One triggered alarm as presented by the Active Alarm screen.
/// All values come from the foundation's crossing detection; the screen never
/// computes or invents any of them.
@immutable
class AlarmEvent {
  const AlarmEvent({
    required this.alertId,
    required this.pair,
    required this.targetPrice,
    required this.triggeredPrice,
    required this.category,
    required this.triggeredAt,
    required this.soundFile,
  });

  /// Id of the alert that fired (same id space as ScreenAlert.id).
  final String alertId;

  /// Pair code without slash, e.g. "EURUSD".
  final String pair;
  final double targetPrice;

  /// The CURRENT market price observed when the crossing was detected.
  final double triggeredPrice;
  final AlertCategory category;
  final DateTime triggeredAt;

  /// Sound file name (same naming as SoundOption.file).
  final String soundFile;

  /// Identity used by screens to tell two alarm events apart.
  String get key => '$alertId@${triggeredAt.microsecondsSinceEpoch}';
}

/// One recorded history entry (locally stored by the foundation).
@immutable
class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.pair,
    required this.targetPrice,
    required this.triggeredPrice,
    required this.category,
    required this.triggeredAt,
    this.isDone = true,
  });

  final String id;
  final String pair;
  final double targetPrice;
  final double triggeredPrice;
  final AlertCategory category;
  final DateTime triggeredAt;

  /// True once the alarm for this trigger was stopped (acknowledged).
  /// False while it is still ringing. (Added by AI 4; the foundation knows it.)
  final bool isDone;
}

/// Persisted user settings shown on the Settings screen (design 12).
@immutable
class AppSettings {
  const AppSettings({
    required this.notificationsEnabled,
    required this.vibrationEnabled,
    required this.defaultSoundFile,
  });

  final bool notificationsEnabled;
  final bool vibrationEnabled;

  /// Default alarm sound file name (see kSoundOptions).
  final String defaultSoundFile;

  AppSettings copyWith({
    bool? notificationsEnabled,
    bool? vibrationEnabled,
    String? defaultSoundFile,
  }) =>
      AppSettings(
        notificationsEnabled:
            notificationsEnabled ?? this.notificationsEnabled,
        vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
        defaultSoundFile: defaultSoundFile ?? this.defaultSoundFile,
      );
}

enum NotificationPermission { granted, denied, unknown }

enum BatteryOptimization { unrestricted, optimized, unknown }

/// Runtime status (NOT persisted) for the Background Monitoring section.
@immutable
class SystemStatus {
  const SystemStatus({
    required this.notificationPermission,
    required this.monitoringActive,
    required this.backgroundServiceRunning,
    required this.battery,
    this.internetConnected,
  });

  final NotificationPermission notificationPermission;

  /// True when at least one alert is being monitored.
  final bool monitoringActive;
  final bool backgroundServiceRunning;
  final BatteryOptimization battery;
  /// true = confirmed connected, null = unknown (no connectivity check exists).
  final bool? internetConnected;
}

/// What the Settings screen may know about the market-data credentials.
/// The API token itself is never sent to the UI.
@immutable
class MarketDataSetup {
  const MarketDataSetup({
    required this.hasCredentials,
    this.accountId = '',
    this.live = false,
  });

  final bool hasCredentials;
  final String accountId;

  /// false = OANDA practice (demo) account, true = live account.
  final bool live;
}

/// Active-alarm boundary (backed by AI 1's single audio/alarm service).
abstract class AlarmGateway {
  /// Emits the alarm currently ringing, or null when none is ringing.
  /// Must emit the current value on subscribe. Emits null again when the alarm
  /// is stopped from anywhere (screen, notification action, etc.).
  Stream<AlarmEvent?> watchActiveAlarm();

  /// Stops the repeating alarm sequence in the central audio service.
  /// Must stop real audio playback and clear the active alarm. Idempotent.
  /// Throws if the audio could not be stopped (screen then stays "ringing").
  Future<void> stopAlarm();
}

/// History boundary (backed by AI 1's local storage).
abstract class HistoryGateway {
  /// Emits the stored history, newest first. Must emit the current value on
  /// subscribe and again whenever history changes. A stream error is shown as
  /// the error state; the screen re-subscribes via [watchHistory] on retry.
  Stream<List<HistoryEntry>> watchHistory();
}

/// Settings boundary (backed by AI 1's storage + platform services).
abstract class SettingsGateway {
  Stream<AppSettings> watchSettings();
  Future<void> setNotificationsEnabled(bool enabled);
  Future<void> setVibrationEnabled(bool enabled);
  Future<void> setDefaultSoundFile(String soundFile);

  Stream<SystemStatus> watchSystemStatus();

  /// Asks Android for notification permission (no-op if already granted).
  Future<void> requestNotificationPermission();

  /// Opens the system screen where battery optimisation can be changed.
  Future<void> openBatterySettings();

  /// Version name, e.g. "1.0.0".
  Future<String> appVersion();

  /// OANDA credentials (market-data provider). Current value on subscribe.
  Stream<MarketDataSetup> watchMarketDataSetup();

  /// Saves the credentials and reconnects the market feed. An empty/null
  /// [token] keeps the previously saved token. Throws if input is invalid.
  Future<void> saveMarketDataSetup({
    required String accountId,
    String? token,
    required bool live,
  });

  /// Removes the saved credentials (prices stop).
  Future<void> clearMarketDataSetup();
}

/// Carries the stage-2 gateways. Kept separate from AI 2's [ScreenServices]
/// so that interface is unchanged. Place it next to / above [ScreenServices].
class Stage2Services extends InheritedWidget {
  const Stage2Services({
    super.key,
    required this.alarms,
    required this.history,
    required this.settings,
    required super.child,
  });

  final AlarmGateway alarms;
  final HistoryGateway history;
  final SettingsGateway settings;

  static Stage2Services of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<Stage2Services>();
    assert(s != null, 'Stage2Services missing above this widget.');
    return s!;
  }

  @override
  bool updateShouldNotify(Stage2Services old) =>
      alarms != old.alarms ||
      history != old.history ||
      settings != old.settings;
}
