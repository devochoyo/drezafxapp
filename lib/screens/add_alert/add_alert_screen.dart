import 'package:flutter/material.dart';
import '../common/dz_widgets.dart';
import '../contracts/screen_contracts.dart';
import '../shared/alert_form_sheet.dart';

/// Opens Add Alert as a modal bottom sheet (designs 03, 04, 13).
/// Resolves to the new alert's id, or null if cancelled.
Future<String?> showAddAlertSheet(BuildContext context) =>
    showDzModalSheet<String>(context, builder: (_) => const AddAlertScreen());

/// Add Alert. Saving calls AlertsGateway.createAlert(draft).
class AddAlertScreen extends StatelessWidget {
  const AddAlertScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final alerts = ScreenServices.of(context).alerts;
    return AlertFormSheet(
      title: 'Add Price Alert',
      submitLabel: 'Save Price Alert',
      onSubmit: alerts.createAlert,
    );
  }
}
