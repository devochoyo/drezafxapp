import 'alarm_sound.dart';
import 'alert_category.dart';
import 'currency_pair.dart';
import 'forex_alert.dart';
import 'model_utils.dart';

enum AlarmStatus {
  /// Nothing playing.
  idle,

  /// A sound preview is playing (one cycle, then returns to idle).
  previewing,

  /// A real alarm is repeating until the user stops it.
  ringing,

  /// The user stopped the alarm. Kept so the "Alarm Stopped" screen can show
  /// a summary. The next alarm or [AlarmState.idle] replaces it.
  stopped,
}

/// Snapshot of the alarm audio. Also persisted so a UI opened from the
/// alarm notification can show which alert is ringing.
class AlarmState {
  const AlarmState({
    this.status = AlarmStatus.idle,
    this.sound,
    this.alertId,
    this.historyId,
    this.pair,
    this.category,
    this.targetPrice,
    this.triggerPrice,
    this.direction,
    this.startedAt,
    this.stoppedAt,
  });

  static const AlarmState idle = AlarmState();

  /// State for a sound preview of [sound].
  factory AlarmState.previewing(AlarmSound sound) =>
      AlarmState(status: AlarmStatus.previewing, sound: sound);

  /// State for a real alarm raised by a triggered [alert].
  factory AlarmState.ringingFor(
    ForexAlert alert, {
    String? historyId,
    DateTime? startedAt,
  }) =>
      AlarmState(
        status: AlarmStatus.ringing,
        sound: alert.sound,
        alertId: alert.id,
        historyId: historyId,
        pair: alert.pair,
        category: alert.category,
        targetPrice: alert.targetPrice,
        triggerPrice: alert.triggerPrice,
        direction: alert.triggerDirection,
        startedAt: startedAt ?? DateTime.now(),
      );

  factory AlarmState.fromJson(Map<String, dynamic> json) => AlarmState(
        status: enumFromName(
            AlarmStatus.values, json['status'] as String?, AlarmStatus.idle),
        sound: json['sound'] == null
            ? null
            : enumFromName(AlarmSound.values, json['sound'] as String?,
                AlarmSound.generalTargetReached),
        alertId: json['alertId'] as String?,
        historyId: json['historyId'] as String?,
        pair: json['pair'] == null ? null : CurrencyPair.fromJson(json['pair']),
        category: json['category'] == null
            ? null
            : enumFromName(AlertCategory.values, json['category'] as String?,
                AlertCategory.generalTargetReached),
        targetPrice: (json['targetPrice'] as num?)?.toDouble(),
        triggerPrice: (json['triggerPrice'] as num?)?.toDouble(),
        direction: json['direction'] == null
            ? null
            : enumFromName(CrossingDirection.values,
                json['direction'] as String?, CrossingDirection.upward),
        startedAt: dateFromJsonOrNull(json['startedAt']),
        stoppedAt: dateFromJsonOrNull(json['stoppedAt']),
      );

  final AlarmStatus status;
  final AlarmSound? sound;
  final String? alertId;
  final String? historyId;
  final CurrencyPair? pair;
  final AlertCategory? category;
  final double? targetPrice;
  final double? triggerPrice;
  final CrossingDirection? direction;
  final DateTime? startedAt;
  final DateTime? stoppedAt;

  bool get isRinging => status == AlarmStatus.ringing;
  bool get isPreviewing => status == AlarmStatus.previewing;
  bool get isIdle => status == AlarmStatus.idle;

  /// Same alarm, marked as stopped by the user.
  AlarmState asStopped(DateTime at) => AlarmState(
        status: AlarmStatus.stopped,
        sound: sound,
        alertId: alertId,
        historyId: historyId,
        pair: pair,
        category: category,
        targetPrice: targetPrice,
        triggerPrice: triggerPrice,
        direction: direction,
        startedAt: startedAt,
        stoppedAt: at,
      );

  Map<String, dynamic> toJson() => {
        'status': status.name,
        'sound': sound?.name,
        'alertId': alertId,
        'historyId': historyId,
        'pair': pair?.toJson(),
        'category': category?.name,
        'targetPrice': targetPrice,
        'triggerPrice': triggerPrice,
        'direction': direction?.name,
        'startedAt': startedAt == null ? null : dateToJson(startedAt!),
        'stoppedAt': stoppedAt == null ? null : dateToJson(stoppedAt!),
      };

  @override
  String toString() => 'AlarmState(${status.name}, alert: $alertId)';
}
