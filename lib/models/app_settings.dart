import 'alarm_sound.dart';
import 'model_utils.dart';

/// Basic user settings (see the Settings design).
class AppSettings {
  const AppSettings({
    this.notificationsEnabled = true,
    this.defaultSound = AlarmSound.entryLevelReached,
    this.vibrationEnabled = true,
    this.monitoringEnabled = true,
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
        defaultSound: enumFromName(AlarmSound.values,
            json['defaultSound'] as String?, AlarmSound.entryLevelReached),
        vibrationEnabled: json['vibrationEnabled'] as bool? ?? true,
        monitoringEnabled: json['monitoringEnabled'] as bool? ?? true,
      );

  /// Whether DrezaFx may show notifications (in addition to the OS
  /// permission).
  final bool notificationsEnabled;

  /// Sound pre-selected on the add-alert form.
  final AlarmSound defaultSound;

  /// Stored for the Settings screen. NOTE: not yet applied by the audio
  /// service (see README "Known gaps").
  final bool vibrationEnabled;

  /// User's wish to have background monitoring running while alerts exist.
  final bool monitoringEnabled;

  AppSettings copyWith({
    bool? notificationsEnabled,
    AlarmSound? defaultSound,
    bool? vibrationEnabled,
    bool? monitoringEnabled,
  }) =>
      AppSettings(
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        defaultSound: defaultSound ?? this.defaultSound,
        vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
        monitoringEnabled: monitoringEnabled ?? this.monitoringEnabled,
      );

  Map<String, dynamic> toJson() => {
        'notificationsEnabled': notificationsEnabled,
        'defaultSound': defaultSound.name,
        'vibrationEnabled': vibrationEnabled,
        'monitoringEnabled': monitoringEnabled,
      };
}
