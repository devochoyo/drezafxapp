import 'alarm_sound.dart';
import 'alert_category.dart';
import 'currency_pair.dart';
import 'model_utils.dart';

/// Lifecycle of an alert.
enum AlertStatus {
  /// Being monitored. Can trigger.
  active,

  /// Already fired once. Ignored by monitoring until re-armed.
  triggered,
}

/// Direction in which the market crossed the target. Detected automatically;
/// the user never chooses it.
enum CrossingDirection { upward, downward }

/// A price alert: "tell me when [pair] crosses [targetPrice]".
///
/// Instances are immutable. Use [copyWith] to change them.
class ForexAlert {
  const ForexAlert({
    required this.id,
    required this.pair,
    required this.targetPrice,
    required this.category,
    required this.sound,
    required this.createdAt,
    required this.updatedAt,
    this.status = AlertStatus.active,
    this.previousPrice,
    this.triggeredAt,
    this.triggerPrice,
    this.triggerDirection,
  });

  factory ForexAlert.fromJson(Map<String, dynamic> json) => ForexAlert(
        id: json['id'] as String,
        pair: CurrencyPair.fromJson(json['pair']),
        targetPrice: (json['targetPrice'] as num).toDouble(),
        category: enumFromName(
            AlertCategory.values,
            json['category'] as String?,
            AlertCategory.generalTargetReached),
        sound: enumFromName(AlarmSound.values, json['sound'] as String?,
            AlarmSound.generalTargetReached),
        createdAt: dateFromJson(json['createdAt']),
        updatedAt: dateFromJson(json['updatedAt']),
        status: enumFromName(
            AlertStatus.values, json['status'] as String?, AlertStatus.active),
        previousPrice: (json['previousPrice'] as num?)?.toDouble(),
        triggeredAt: dateFromJsonOrNull(json['triggeredAt']),
        triggerPrice: (json['triggerPrice'] as num?)?.toDouble(),
        triggerDirection: json['triggerDirection'] == null
            ? null
            : enumFromName(CrossingDirection.values,
                json['triggerDirection'] as String?, CrossingDirection.upward),
      );

  final String id;
  final CurrencyPair pair;

  /// Price copied from MetaTrader 5.
  final double targetPrice;

  final AlertCategory category;
  final AlarmSound sound;
  final DateTime createdAt;

  /// Changes only when the user edits the alert, or when it triggers or is
  /// re-armed. It does NOT change when [previousPrice] moves. The monitoring
  /// engine uses it to detect that an alert was edited while it was working.
  final DateTime updatedAt;

  final AlertStatus status;

  /// Last price observed while evaluating this alert (the crossing
  /// reference). Null means "no reference yet": the next quote only becomes
  /// the reference and can never trigger. Kept up to date in memory by the
  /// monitoring engine; only written to storage when the alert triggers.
  final double? previousPrice;

  final DateTime? triggeredAt;

  /// The actual market price that crossed the target (may be beyond the
  /// target if the market jumped).
  final double? triggerPrice;

  final CrossingDirection? triggerDirection;

  bool get isActive => status == AlertStatus.active;
  bool get isTriggered => status == AlertStatus.triggered;

  ForexAlert copyWith({
    CurrencyPair? pair,
    double? targetPrice,
    AlertCategory? category,
    AlarmSound? sound,
    DateTime? updatedAt,
    AlertStatus? status,
    double? previousPrice,
    bool clearPreviousPrice = false,
    DateTime? triggeredAt,
    double? triggerPrice,
    CrossingDirection? triggerDirection,
    bool clearTrigger = false,
  }) =>
      ForexAlert(
        id: id,
        pair: pair ?? this.pair,
        targetPrice: targetPrice ?? this.targetPrice,
        category: category ?? this.category,
        sound: sound ?? this.sound,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        status: status ?? this.status,
        previousPrice:
            clearPreviousPrice ? null : (previousPrice ?? this.previousPrice),
        triggeredAt: clearTrigger ? null : (triggeredAt ?? this.triggeredAt),
        triggerPrice: clearTrigger ? null : (triggerPrice ?? this.triggerPrice),
        triggerDirection:
            clearTrigger ? null : (triggerDirection ?? this.triggerDirection),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'pair': pair.toJson(),
        'targetPrice': targetPrice,
        'category': category.name,
        'sound': sound.name,
        'createdAt': dateToJson(createdAt),
        'updatedAt': dateToJson(updatedAt),
        'status': status.name,
        'previousPrice': previousPrice,
        'triggeredAt': triggeredAt == null ? null : dateToJson(triggeredAt!),
        'triggerPrice': triggerPrice,
        'triggerDirection': triggerDirection?.name,
      };

  @override
  String toString() =>
      'ForexAlert($id ${pair.displayName} ${pair.format(targetPrice)} ${status.name})';
}
