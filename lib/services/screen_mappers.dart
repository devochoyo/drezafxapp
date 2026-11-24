// Translates between the screen-side types (lib/screens/contracts) and the
// foundation models (lib/models). No business logic, only conversion.
//
// The screens and the foundation use the same names for some types
// (AlertCategory, AlertStatus, ...). Screen types are imported with the
// prefix "ui" to keep them apart.
import '../models/alarm_sound.dart';
import '../models/alarm_state.dart';
import '../models/alert_category.dart';
import '../models/alert_history.dart';
import '../models/forex_alert.dart';
import '../screens/contracts/screen_contracts.dart' as ui;
import '../screens/contracts/stage2_contracts.dart' as ui;

/// Foundation category -> screen category (all six, one to one).
ui.AlertCategory categoryToScreen(AlertCategory c) {
  switch (c) {
    case AlertCategory.entryLevelReached:
      return ui.AlertCategory.entryLevelReached;
    case AlertCategory.fvgApproaching:
      return ui.AlertCategory.fairValueGapApproaching;
    case AlertCategory.fvgReached:
      return ui.AlertCategory.fairValueGapReached;
    case AlertCategory.orderBlockApproaching:
      return ui.AlertCategory.orderBlockApproaching;
    case AlertCategory.orderBlockReached:
      return ui.AlertCategory.orderBlockReached;
    case AlertCategory.generalTargetReached:
      return ui.AlertCategory.generalPriceTargetReached;
  }
}

/// Screen category -> foundation category (all six, one to one).
AlertCategory categoryFromScreen(ui.AlertCategory c) {
  switch (c) {
    case ui.AlertCategory.entryLevelReached:
      return AlertCategory.entryLevelReached;
    case ui.AlertCategory.fairValueGapApproaching:
      return AlertCategory.fvgApproaching;
    case ui.AlertCategory.fairValueGapReached:
      return AlertCategory.fvgReached;
    case ui.AlertCategory.orderBlockApproaching:
      return AlertCategory.orderBlockApproaching;
    case ui.AlertCategory.orderBlockReached:
      return AlertCategory.orderBlockReached;
    case ui.AlertCategory.generalPriceTargetReached:
      return AlertCategory.generalTargetReached;
  }
}

/// "entry_level_reached.wav" -> AlarmSound.entryLevelReached.
/// Throws for a file that is not one of the six selectable sounds.
AlarmSound soundFromFile(String fileName) {
  for (final sound in AlarmSound.values) {
    if (sound.fileName == fileName) return sound;
  }
  throw ArgumentError('Unknown alarm sound file: $fileName');
}

ui.AlertStatus statusToScreen(AlertStatus s) =>
    s == AlertStatus.triggered ? ui.AlertStatus.triggered : ui.AlertStatus.active;

ui.ScreenAlert alertToScreen(ForexAlert a) => ui.ScreenAlert(
      id: a.id,
      pair: a.pair.symbol,
      targetPrice: a.targetPrice,
      category: categoryToScreen(a.category),
      soundFile: a.sound.fileName,
      status: statusToScreen(a.status),
      createdAt: a.createdAt,
      updatedAt: a.updatedAt,
    );

/// A ringing AlarmState -> AlarmEvent. Anything else (idle, previewing,
/// stopped, or a state with missing data) -> null.
ui.AlarmEvent? alarmEventFromState(AlarmState s) {
  if (!s.isRinging) return null;
  final alertId = s.alertId;
  final pair = s.pair;
  final category = s.category;
  final target = s.targetPrice;
  final trigger = s.triggerPrice;
  final startedAt = s.startedAt;
  final sound = s.sound;
  if (alertId == null ||
      pair == null ||
      category == null ||
      target == null ||
      trigger == null ||
      startedAt == null ||
      sound == null) {
    return null;
  }
  return ui.AlarmEvent(
    alertId: alertId,
    pair: pair.symbol,
    targetPrice: target,
    triggeredPrice: trigger,
    category: categoryToScreen(category),
    triggeredAt: startedAt,
    soundFile: sound.fileName,
  );
}

ui.HistoryEntry historyToScreen(AlertHistory h) => ui.HistoryEntry(
      id: h.id,
      pair: h.pair.symbol,
      targetPrice: h.targetPrice,
      triggeredPrice: h.triggerPrice,
      category: categoryToScreen(h.category),
      triggeredAt: h.triggeredAt,
      isDone: h.isDone,
    );
