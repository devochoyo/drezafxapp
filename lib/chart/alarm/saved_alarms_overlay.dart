import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../screens/common/dz_theme.dart';
import '../../screens/contracts/screen_contracts.dart';
import '../../screens/dashboard/widgets/dashboard_widgets.dart';
import '../../screens/edit_alert/edit_alert_screen.dart';
import '../contracts/chart_contracts.dart';
import 'alarm_chart_math.dart';

/// Renders active/near alarms for the current pair (zOrder 150).
class SavedAlarmsOverlay extends ChartOverlay {
  SavedAlarmsOverlay({
    required this.alerts,
    required this.getSymbol,
    required this.onRequestMoveConfirm,
  });

  final AlertsGateway alerts;
  final String Function() getSymbol;
  final void Function(ScreenAlert alert, double newPrice) onRequestMoveConfirm;

  StreamSubscription<List<ScreenAlert>>? _sub;
  List<ScreenAlert> _alarms = const [];
  String? _draggingId;
  double? _dragPrice;

  void start(String symbol) {
    _sub?.cancel();
    _sub = alerts.watchAlerts().listen(_onAlerts);
  }

  void _onAlerts(List<ScreenAlert> all) {
    final sym = getSymbol();
    _alarms = [
      for (final a in all)
        if (a.pair == sym &&
            (a.status == AlertStatus.active || a.status == AlertStatus.near))
          a,
    ];
    notifyListeners();
  }

  void refreshForSymbol() {
    // Force re-filter on next emission; also clear drag.
    _draggingId = null;
    _dragPrice = null;
    // Re-request by re-subscribing is heavy; just clear and wait.
    _alarms = [
      for (final a in _alarms)
        if (a.pair == getSymbol()) a,
    ];
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  int get zOrder => 150;

  static final _linePaint = Paint()
    ..color = ChartColors.alarm.withAlpha(180)
    ..strokeWidth = 1
    ..style = PaintingStyle.stroke;

  static final _nearPaint = Paint()
    ..color = ChartColors.alarm.withAlpha(220)
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke;

  static final _tagBg = Paint()
    ..color = DzColors.elevated
    ..style = PaintingStyle.fill;

  static final _tagBorder = Paint()
    ..color = ChartColors.alarm.withAlpha(160)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;

  static const _tagStyle = TextStyle(
    color: DzColors.text,
    fontSize: 10,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  @override
  void paint(Canvas canvas, ChartCoordinateMapper map) {
    final plot = map.plotRect;
    if (plot.width <= 0 || _alarms.isEmpty) return;

    // Stack overlapping tags vertically.
    final usedYs = <double>[];

    for (final a in _alarms) {
      final price = (_draggingId == a.id && _dragPrice != null)
          ? _dragPrice!
          : a.targetPrice;
      final y = map.priceToY(price);
      if (y < plot.top - 20 || y > plot.bottom + 20) continue;

      final paint = a.status == AlertStatus.near ? _nearPaint : _linePaint;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), paint);

      final label =
          '🔔 ${a.category.chipLabel}  ${price.toStringAsFixed(map.pricePrecision)}';
      final tp = TextPainter(
        text: TextSpan(text: label, style: _tagStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: plot.width * 0.55);

      const padH = 6.0;
      const padV = 3.0;
      final tagW = tp.width + padH * 2;
      final tagH = tp.height + padV * 2;

      // Avoid overlap: push tag down if needed.
      var tagY = y - tagH / 2;
      for (final uy in usedYs) {
        if ((tagY - uy).abs() < tagH + 2) {
          tagY = uy + tagH + 2;
        }
      }
      usedYs.add(tagY);

      final tagRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(plot.left + 6, tagY, tagW, tagH),
        const Radius.circular(4),
      );
      canvas.drawRRect(tagRect, _tagBg);
      canvas.drawRRect(tagRect, _tagBorder);
      tp.paint(canvas, Offset(plot.left + 6 + padH, tagY + padV));
    }
  }

  @override
  bool hitTest(Offset position, ChartCoordinateMapper map) {
    for (final a in _alarms) {
      final price = (_draggingId == a.id && _dragPrice != null)
          ? _dragPrice!
          : a.targetPrice;
      final y = map.priceToY(price);
      if (AlarmChartMath.hitsHorizontalLine(position.dy, y, hitSlop: 20)) {
        return true;
      }
    }
    return false;
  }

  ScreenAlert? _hitAlert(Offset position, ChartCoordinateMapper map) {
    for (final a in _alarms) {
      final price = (_draggingId == a.id && _dragPrice != null)
          ? _dragPrice!
          : a.targetPrice;
      final y = map.priceToY(price);
      if (AlarmChartMath.hitsHorizontalLine(position.dy, y, hitSlop: 20)) {
        return a;
      }
    }
    return null;
  }

  @override
  void onTap(Offset position, ChartCoordinateMapper map) {
    final a = _hitAlert(position, map);
    if (a == null) return;
    // Action sheet is opened by the feature via a callback pattern.
    // Store pending and notify — feature listens and shows the sheet.
    _pendingTap = a;
    notifyListeners();
  }

  ScreenAlert? _pendingTap;
  ScreenAlert? takePendingTap() {
    final a = _pendingTap;
    _pendingTap = null;
    return a;
  }

  @override
  void onDragStart(Offset position, ChartCoordinateMapper map) {
    final a = _hitAlert(position, map);
    if (a == null) return;
    _draggingId = a.id;
    _dragPrice = a.targetPrice;
    HapticFeedback.selectionClick();
  }

  @override
  void onDragUpdate(
    Offset position,
    Offset delta,
    ChartCoordinateMapper map,
  ) {
    if (_draggingId == null) return;
    final raw = map.yToPrice(position.dy);
    final rounded = AlarmChartMath.roundToPrecision(raw, map.pricePrecision);
    _dragPrice = AlarmChartMath.clampPrice(
      rounded,
      map.visibleMinPrice,
      map.visibleMaxPrice,
    );
    notifyListeners();
  }

  @override
  void onDragEnd(ChartCoordinateMapper map) {
    if (_draggingId == null || _dragPrice == null) return;
    final id = _draggingId!;
    final newPrice = _dragPrice!;
    final original = _alarms.cast<ScreenAlert?>().firstWhere(
          (a) => a!.id == id,
          orElse: () => null,
        );
    _draggingId = null;
    _dragPrice = null;
    notifyListeners();
    if (original != null && (original.targetPrice - newPrice).abs() > 1e-12) {
      onRequestMoveConfirm(original, newPrice);
    }
  }
}

/// Compact actions after tapping a saved alarm tag.
Future<void> showSavedAlarmActions(
  BuildContext context, {
  required ScreenAlert alert,
  required AlertsGateway alerts,
}) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: DzColors.bg2,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: DzColors.text),
              title: Text('Edit', style: DzText.body()),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: DzColors.danger),
              title: Text('Delete', style: DzText.body(color: DzColors.danger)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );

  if (!context.mounted) return;
  if (action == 'edit') {
    await showEditAlertSheet(context, alert);
  } else if (action == 'delete') {
    final ok = await showDeleteAlertDialog(context);
    if (ok == true) {
      await alerts.deleteAlert(alert.id);
    }
  }
}
