import 'dart:async';
import 'package:flutter/widgets.dart';

// ---------------------------------------------------------------------------
// SCREEN-SIDE CONTRACTS.
//
// These are NOT AI 1's models or services. They describe exactly what the
// AI 2 screens need. AI 4 should write thin adapters from AI 1's real classes
// to these types (see HANDOVER.md). No business logic lives here.
// ---------------------------------------------------------------------------

/// The six established alert categories. Names/meanings are fixed.
enum AlertCategory {
  entryLevelReached(
    id: 'entry_level_reached',
    label: 'Entry Level Reached',
    chipLabel: 'Entry Level Reached',
    cardCaption: 'ENTRY LEVEL',
    defaultSoundFile: 'entry_level_reached.wav',
  ),
  fairValueGapApproaching(
    id: 'fair_value_gap_approaching',
    label: 'Fair Value Gap Approaching',
    chipLabel: 'Fair Value Gap Approaching',
    cardCaption: 'FAIR VALUE GAP APPROACHING',
    defaultSoundFile: 'fvg_approaching.wav',
  ),
  fairValueGapReached(
    id: 'fair_value_gap_reached',
    label: 'Fair Value Gap Reached',
    chipLabel: 'Fair Value Gap Reached',
    cardCaption: 'FAIR VALUE GAP REACHED',
    defaultSoundFile: 'fvg_reached.wav',
  ),
  orderBlockApproaching(
    id: 'order_block_approaching',
    label: 'Order Block Approaching',
    chipLabel: 'Order Block Approaching',
    cardCaption: 'ORDER BLOCK APPROACHING',
    defaultSoundFile: 'order_block_approaching.wav',
  ),
  orderBlockReached(
    id: 'order_block_reached',
    label: 'Order Block Reached',
    chipLabel: 'Order Block Reached',
    cardCaption: 'ORDER BLOCK REACHED',
    defaultSoundFile: 'order_block_reached.wav',
  ),
  generalPriceTargetReached(
    id: 'general_price_target_reached',
    label: 'General Price Target Reached',
    chipLabel: 'General Price Target',
    cardCaption: 'GENERAL PRICE TARGET',
    defaultSoundFile: 'general_target_reached.wav',
  );

  const AlertCategory({
    required this.id,
    required this.label,
    required this.chipLabel,
    required this.cardCaption,
    required this.defaultSoundFile,
  });

  /// Stable string id (AI 4 maps to/from AI 1's category type).
  final String id;
  final String label;
  final String chipLabel;
  final String cardCaption;

  /// Sound file name suggested for this category (verify against real assets).
  final String defaultSoundFile;

  bool get isApproaching =>
      this == fairValueGapApproaching || this == orderBlockApproaching;

  static AlertCategory fromId(String id) => AlertCategory.values
      .firstWhere((c) => c.id == id, orElse: () => generalPriceTargetReached);
}

/// Status shown on the dashboard card. Computed by the foundation (AI 1),
/// never by the UI.
enum AlertStatus {
  /// Enabled and waiting.
  active,

  /// Enabled and the foundation reports price is near the target
  /// (approach rule is owned by the foundation; UI does not compute it).
  near,

  /// Already triggered.
  triggered,

  /// Disabled / inactive.
  inactive,
}

/// What the screens need from one alert. Plain immutable data.
@immutable
class ScreenAlert {
  const ScreenAlert({
    required this.id,
    required this.pair,
    required this.targetPrice,
    required this.category,
    required this.soundFile,
    required this.status,
    this.createdAt,
    this.updatedAt,
  });

  /// Stable id. Never regenerated on edit.
  final String id;

  /// Pair code WITHOUT slash, upper case, e.g. "EURUSD", "USDJPY", "XAUUSD".
  final String pair;

  /// Target price manually entered by the user (from MT5).
  final double targetPrice;
  final AlertCategory category;

  /// Sound file name, e.g. "entry_level_reached.wav".
  final String soundFile;
  final AlertStatus status;

  /// Preserved by the foundation on edit; screens only carry them through.
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

/// Data collected by Add/Edit forms. No id, no timestamps, no direction.
@immutable
class AlertDraft {
  const AlertDraft({
    required this.pair,
    required this.targetPrice,
    required this.category,
    required this.soundFile,
  });

  factory AlertDraft.fromAlert(ScreenAlert a) => AlertDraft(
        pair: a.pair,
        targetPrice: a.targetPrice,
        category: a.category,
        soundFile: a.soundFile,
      );

  final String pair;
  final double targetPrice;
  final AlertCategory category;
  final String soundFile;
}

enum MarketConnectionStatus { connecting, connected, disconnected, error }

/// One emission of the market-data stream.
@immutable
class MarketSnapshot {
  const MarketSnapshot({
    required this.status,
    this.prices = const {},
    this.errorMessage,
  });

  final MarketConnectionStatus status;

  /// Latest known CURRENT market price per pair code ("EURUSD" -> 1.08412).
  /// Missing key = no price known. The UI shows "—" and never invents one.
  final Map<String, double> prices;
  final String? errorMessage;
}

/// Alert storage boundary (to be backed by AI 1's storage service).
abstract class AlertsGateway {
  /// Emits the full current list, and again after every create/update/delete.
  Stream<List<ScreenAlert>> watchAlerts();

  /// Persists a new alert; returns its new id.
  Future<String> createAlert(AlertDraft draft);

  /// Updates [original] IN PLACE: keep id + createdAt, set updatedAt, and reset
  /// the crossing reference if pair or target changed. Returns the same id.
  Future<String> updateAlert(ScreenAlert original, AlertDraft draft);

  Future<void> deleteAlert(String id);
}

/// Market-data boundary (to be backed by AI 1's market-data abstraction).
abstract class MarketPriceGateway {
  Stream<MarketSnapshot> get snapshots;

  /// Optional user-initiated reconnect from the Dashboard banner.
  void retry();
}

/// Shared audio boundary (to be backed by AI 1's single audio service).
abstract class SoundGateway {
  /// Starts previewing [soundFile]; any other preview must stop first.
  Future<void> preview(String soundFile);
  Future<void> stopPreview();

  /// Emits the file currently previewing, or null when idle.
  Stream<String?> get previewingFile;
}

/// Carries the three gateways down the tree. Wrap the app (or each route) in
/// this once. Not a state-management framework.
class ScreenServices extends InheritedWidget {
  const ScreenServices({
    super.key,
    required this.alerts,
    required this.market,
    required this.sounds,
    required super.child,
  });

  final AlertsGateway alerts;
  final MarketPriceGateway market;
  final SoundGateway sounds;

  static ScreenServices of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<ScreenServices>();
    assert(s != null, 'ScreenServices missing above this widget.');
    return s!;
  }

  @override
  bool updateShouldNotify(ScreenServices old) =>
      alerts != old.alerts || market != old.market || sounds != old.sounds;
}

/// A selectable sound in the Sound Selection screen.
@immutable
class SoundOption {
  const SoundOption(this.file, this.name, this.description);
  final String file;
  final String name;
  final String description;
}

/// Names/descriptions fixed by the design (06_sound_selection.png).
/// File names are the EXPECTED asset names - verify against the real assets.
/// "forex_alarm_bell.wav" is a seventh expected asset that is not one of the
/// six design rows (see HANDOVER.md); it is intentionally not listed here.
const List<SoundOption> kSoundOptions = [
  SoundOption('entry_level_reached.wav', 'Entry Level Reached',
      'Clear chime when your entry is hit'),
  SoundOption('fvg_approaching.wav', 'Fair Value Gap Approaching',
      'Soft rising tone as price nears the gap'),
  SoundOption('fvg_reached.wav', 'Fair Value Gap Reached',
      'Firm double tone when the gap is touched'),
  SoundOption('order_block_approaching.wav', 'Order Block Approaching',
      'Soft pulse as price nears the block'),
  SoundOption('order_block_reached.wav', 'Order Block Reached',
      'Strong tone when the block is touched'),
  SoundOption('general_target_reached.wav', 'General Price Target Reached',
      'Standard tone for any price target'),
];

/// Human name for a sound file; falls back to a prettified file name.
String soundDisplayName(String file) {
  for (final o in kSoundOptions) {
    if (o.file == file) return o.name;
  }
  final base = file.split('.').first.replaceAll('_', ' ').trim();
  if (base.isEmpty) return file;
  return base
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}
