import '../screens/contracts/stage2_contracts.dart' as ui;
import 'alert_service.dart';
import 'screen_mappers.dart';

/// Connects the screens' HistoryGateway to AlertService.getHistory().
/// Only real stored records are returned. History is re-read whenever
/// AlertService reports a change (the monitoring service triggers that when it
/// adds a record or marks an alarm as stopped).
class HistoryAdapter implements ui.HistoryGateway {
  HistoryAdapter(this._alerts);

  final AlertService _alerts;

  @override
  Stream<List<ui.HistoryEntry>> watchHistory() =>
      _alerts.watchAlerts().asyncMap((_) async {
        final records = await _alerts.getHistory();
        final entries = records.map(historyToScreen).toList();
        entries.sort((a, b) => b.triggeredAt.compareTo(a.triggeredAt));
        return entries;
      });
}
