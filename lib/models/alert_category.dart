import 'alarm_sound.dart';

/// What the user is waiting for. The category only labels the alert and picks
/// its default sound; it never changes how crossings are detected.
enum AlertCategory {
  entryLevelReached(
    label: 'Entry Level Reached',
    announcement: 'Entry level reached',
    defaultSound: AlarmSound.entryLevelReached,
  ),
  fvgApproaching(
    label: 'Fair Value Gap Approaching',
    announcement: 'Fair value gap approaching',
    defaultSound: AlarmSound.fvgApproaching,
  ),
  fvgReached(
    label: 'Fair Value Gap Reached',
    announcement: 'Fair value gap reached',
    defaultSound: AlarmSound.fvgReached,
  ),
  orderBlockApproaching(
    label: 'Order Block Approaching',
    announcement: 'Order block approaching',
    defaultSound: AlarmSound.orderBlockApproaching,
  ),
  orderBlockReached(
    label: 'Order Block Reached',
    announcement: 'Order block reached',
    defaultSound: AlarmSound.orderBlockReached,
  ),
  generalTargetReached(
    label: 'General Price Target Reached',
    announcement: 'Price target reached',
    defaultSound: AlarmSound.generalTargetReached,
  );

  const AlertCategory({
    required this.label,
    required this.announcement,
    required this.defaultSound,
  });

  /// Name shown in the UI.
  final String label;

  /// Short text used in notifications.
  final String announcement;

  /// Sound pre-selected for this category.
  final AlarmSound defaultSound;
}
