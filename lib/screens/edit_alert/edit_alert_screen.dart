import 'package:flutter/material.dart';
import '../common/dz_widgets.dart';
import '../contracts/screen_contracts.dart';
import '../shared/alert_form_sheet.dart';

/// Opens Edit Alert as a modal bottom sheet (design 05).
/// Resolves to the (unchanged) alert id on save, or null if cancelled.
Future<String?> showEditAlertSheet(BuildContext context, ScreenAlert alert) =>
    showDzModalSheet<String>(
        context, builder: (_) => EditAlertScreen(alert: alert));

/// Edit Alert. Prefilled from [alert]; saving calls
/// AlertsGateway.updateAlert(alert, draft). The screen never creates an id or
/// timestamps and contains no crossing logic - the gateway implementation must
/// keep id/createdAt, set updatedAt and reset the crossing reference when pair
/// or target changed.
class EditAlertScreen extends StatelessWidget {
  const EditAlertScreen({super.key, required this.alert});

  final ScreenAlert alert;

  @override
  Widget build(BuildContext context) {
    final alerts = ScreenServices.of(context).alerts;
    return AlertFormSheet(
      title: 'Edit Price Alert',
      submitLabel: 'Save Changes',
      initial: AlertDraft.fromAlert(alert),
      onSubmit: (draft) => alerts.updateAlert(alert, draft),
    );
  }
}
