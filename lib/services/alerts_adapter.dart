import '../models/currency_pair.dart';
import '../screens/contracts/screen_contracts.dart' as ui;
import 'alert_service.dart';
import 'screen_mappers.dart';

/// Connects the screens' AlertsGateway to the foundation's AlertService.
/// Validation and re-arm behaviour stay inside AlertService.
class AlertsAdapter implements ui.AlertsGateway {
  AlertsAdapter(this._alerts);

  final AlertService _alerts;

  @override
  Stream<List<ui.ScreenAlert>> watchAlerts() => _alerts
      .watchAlerts()
      .map((list) => list.map(alertToScreen).toList());

  @override
  Future<String> createAlert(ui.AlertDraft draft) async {
    final alert = await _alerts.createAlert(
      pair: CurrencyPair.fromSymbol(draft.pair),
      targetPrice: draft.targetPrice,
      category: categoryFromScreen(draft.category),
      sound: soundFromFile(draft.soundFile),
    );
    return alert.id;
  }

  /// AlertService.updateAlert keeps id + createdAt, sets updatedAt, makes the
  /// alert active again and clears the crossing reference / trigger.
  @override
  Future<String> updateAlert(ui.ScreenAlert original, ui.AlertDraft draft) async {
    final alert = await _alerts.updateAlert(
      original.id,
      pair: CurrencyPair.fromSymbol(draft.pair),
      targetPrice: draft.targetPrice,
      category: categoryFromScreen(draft.category),
      sound: soundFromFile(draft.soundFile),
    );
    return alert.id;
  }

  @override
  Future<void> deleteAlert(String id) => _alerts.deleteAlert(id);
}
