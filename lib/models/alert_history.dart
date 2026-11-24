import 'alarm_sound.dart';
import 'alert_category.dart';
import 'currency_pair.dart';
import 'forex_alert.dart';
import 'model_utils.dart';

/// One entry in the alert history: a record of an alert that fired.
/// It is a snapshot, so it stays correct if the alert is later edited or
/// deleted.
class AlertHistory {
  const AlertHistory({
    required this.id,
    required this.alertId,
    required this.pair,
    required this.category,
    required this.sound,
    required this.targetPrice,
    required this.triggerPrice,
    required this.direction,
    required this.triggeredAt,
    this.alarmStoppedAt,
  });

  /// Snapshot of a freshly triggered [alert]. [alert] must have its trigger
  /// fields set (as returned by the evaluation service).
  factory AlertHistory.fromTriggeredAlert(String historyId, ForexAlert alert) {
    final triggerPrice = alert.triggerPrice;
    final triggeredAt = alert.triggeredAt;
    final direction = alert.triggerDirection;
    if (triggerPrice == null || triggeredAt == null || direction == null) {
      throw ArgumentError('Alert ${alert.id} has not been triggered.');
    }
    return AlertHistory(
      id: historyId,
      alertId: alert.id,
      pair: alert.pair,
      category: alert.category,
      sound: alert.sound,
      targetPrice: alert.targetPrice,
      triggerPrice: triggerPrice,
      direction: direction,
      triggeredAt: triggeredAt,
    );
  }

  factory AlertHistory.fromJson(Map<String, dynamic> json) => AlertHistory(
        id: json['id'] as String,
        alertId: json['alertId'] as String,
        pair: CurrencyPair.fromJson(json['pair']),
        category: enumFromName(
            AlertCategory.values,
            json['category'] as String?,
            AlertCategory.generalTargetReached),
        sound: enumFromName(AlarmSound.values, json['sound'] as String?,
            AlarmSound.generalTargetReached),
        targetPrice: (json['targetPrice'] as num).toDouble(),
        triggerPrice: (json['triggerPrice'] as num).toDouble(),
        direction: enumFromName(CrossingDirection.values,
            json['direction'] as String?, CrossingDirection.upward),
        triggeredAt: dateFromJson(json['triggeredAt']),
        alarmStoppedAt: dateFromJsonOrNull(json['alarmStoppedAt']),
      );

  final String id;
  final String alertId;
  final CurrencyPair pair;
  final AlertCategory category;
  final AlarmSound sound;
  final double targetPrice;
  final double triggerPrice;
  final CrossingDirection direction;
  final DateTime triggeredAt;

  /// When the user stopped the alarm. Null while it is still ringing or if
  /// it was never acknowledged. The history screen's "DONE" pill can use
  /// `alarmStoppedAt != null`.
  final DateTime? alarmStoppedAt;

  bool get isDone => alarmStoppedAt != null;

  AlertHistory copyWith({DateTime? alarmStoppedAt}) => AlertHistory(
        id: id,
        alertId: alertId,
        pair: pair,
        category: category,
        sound: sound,
        targetPrice: targetPrice,
        triggerPrice: triggerPrice,
        direction: direction,
        triggeredAt: triggeredAt,
        alarmStoppedAt: alarmStoppedAt ?? this.alarmStoppedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'alertId': alertId,
        'pair': pair.toJson(),
        'category': category.name,
        'sound': sound.name,
        'targetPrice': targetPrice,
        'triggerPrice': triggerPrice,
        'direction': direction.name,
        'triggeredAt': dateToJson(triggeredAt),
        'alarmStoppedAt':
            alarmStoppedAt == null ? null : dateToJson(alarmStoppedAt!),
      };
}
