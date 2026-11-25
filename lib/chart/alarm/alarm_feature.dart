import 'dart:async';

import 'package:flutter/material.dart';

import '../../screens/common/dz_theme.dart';
import '../../screens/contracts/screen_contracts.dart';
import '../../services/app_services.dart';
import '../contracts/chart_contracts.dart';
import 'draft_alarm_line_overlay.dart';
import 'saved_alarms_overlay.dart';
import 'set_alarm_sheet.dart';

/// Chart feature: bell button, draft line, set-alarm flow, saved alarms.
class AlarmChartFeature extends ChartFeature {
  AlertsGateway? _alerts;
  ChartController? _controller;
  DraftAlarmLineOverlay? _draft;
  SavedAlarmsOverlay? _saved;
  final ValueNotifier<bool> _draftActive = ValueNotifier(false);
  bool _showMonitoringBanner = false;
  StreamSubscription? _monitorSub;
  StreamSubscription? _alertsBannerSub;
  String? _lastSymbol;

  // Move-confirm state for saved alarms.
  ScreenAlert? _moveAlert;
  double? _movePrice;

  @override
  String get id => 'alarm';

  @override
  void attach(ChartController controller, BuildContext context) {
    _controller = controller;
    final services = ScreenServices.of(context);
    _alerts = services.alerts;

    _saved = SavedAlarmsOverlay(
      alerts: services.alerts,
      getSymbol: () => controller.symbol,
      onRequestMoveConfirm: (alert, price) {
        _moveAlert = alert;
        _movePrice = price;
        notifyListeners();
      },
    );
    _saved!.start(controller.symbol);
    controller.addOverlay(_saved!);
    _lastSymbol = controller.symbol;

    // Listen for pending tag taps.
    _saved!.addListener(_onSavedChanged);

    // Track whether any alarm is active (for monitoring-off banner).
    _alertsBannerSub = services.alerts.watchAlerts().listen(_onAlertsForBanner);

    // Monitoring status (read-only).
    final mon = AppServices.instance.monitoring;
    _updateMonitoringBanner(mon.currentStatus);
    _monitorSub = mon.statusStream.listen(_updateMonitoringBanner);

    controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    final c = _controller;
    if (c == null) return;
    if (c.symbol != _lastSymbol) {
      _lastSymbol = c.symbol;
      _cancelDraft();
      _saved?.refreshForSymbol();
    }
    // Update draft lastPrice for distance label.
    _draft?.lastPrice = c.lastPrice;
  }

  void _onSavedChanged() {
    final pending = _saved?.takePendingTap();
    if (pending != null && _controller != null) {
      // Need a BuildContext — deferred via notifyListeners so buildFloating
      // / parent can open the sheet. Store and flag.
      _pendingActionAlert = pending;
      notifyListeners();
    }
  }

  ScreenAlert? _pendingActionAlert;

  bool _hasActiveAlarms = false;

  void _updateMonitoringBanner(dynamic status) {
    // status is MonitoringStatus from the background service.
    final running = status.isServiceRunning == true;
    final show = _hasActiveAlarms && !running;
    if (show != _showMonitoringBanner) {
      _showMonitoringBanner = show;
      notifyListeners();
    }
  }

  void _onAlertsForBanner(List<ScreenAlert> all) {
    final active = all.any((a) =>
        a.status == AlertStatus.active || a.status == AlertStatus.near);
    if (active != _hasActiveAlarms) {
      _hasActiveAlarms = active;
      final mon = AppServices.instance.monitoring;
      _updateMonitoringBanner(mon.currentStatus);
    }
  }

  @override
  void detach() {
    _monitorSub?.cancel();
    _monitorSub = null;
    _alertsBannerSub?.cancel();
    _alertsBannerSub = null;
    _cancelDraft();
    final c = _controller;
    final s = _saved;
    if (c != null && s != null) {
      c.removeOverlay(s);
      s.removeListener(_onSavedChanged);
      s.dispose();
    }
    _saved = null;
    _controller?.removeListener(_onControllerChanged);
    _controller = null;
    _alerts = null;
    _draftActive.value = false;
  }

  void _toggleDraft() {
    if (_draft != null) {
      _cancelDraft();
      return;
    }
    final c = _controller;
    if (c == null) return;
    final price = c.centerPrice ?? c.lastPrice;
    if (price == null) return;

    _draft = DraftAlarmLineOverlay(
      price: price,
      symbol: c.symbol,
      lastPrice: c.lastPrice,
      onPriceChanged: (p) {
        // Expand range when user drags near edges.
        c.expandPriceRangeToInclude(p);
        notifyListeners();
      },
    );
    c.addOverlay(_draft!);
    _draftActive.value = true;
    notifyListeners();
  }

  void _cancelDraft() {
    final c = _controller;
    final d = _draft;
    if (c != null && d != null) {
      c.removeOverlay(d);
    }
    _draft = null;
    _draftActive.value = false;
    notifyListeners();
  }

  Future<void> _setAlarm(BuildContext context) async {
    final c = _controller;
    final d = _draft;
    final alerts = _alerts;
    if (c == null || d == null || alerts == null) return;

    final ok = await showSetAlarmSheet(
      context,
      symbol: c.symbol,
      price: d.price,
      pricePrecision: c.mapper.pricePrecision,
      alerts: alerts,
    );
    if (ok) {
      _cancelDraft();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(
              'Alarm set at ${d.price.toStringAsFixed(c.mapper.pricePrecision)}',
            ),
            behavior: SnackBarBehavior.floating,
          ));
      }
    }
  }

  Future<void> _confirmMove(BuildContext context) async {
    final alert = _moveAlert;
    final price = _movePrice;
    final alerts = _alerts;
    _moveAlert = null;
    _movePrice = null;
    notifyListeners();
    if (alert == null || price == null || alerts == null) return;

    final draft = AlertDraft(
      pair: alert.pair,
      targetPrice: price,
      category: alert.category,
      soundFile: alert.soundFile,
    );
    try {
      await alerts.updateAlert(alert, draft);
    } catch (_) {
      // Ignore — user can retry from the dashboard.
    }
  }

  void _cancelMove() {
    _moveAlert = null;
    _movePrice = null;
    notifyListeners();
  }

  @override
  List<ChartToolbarItem> toolbarItems(BuildContext context) {
    return [
      ChartToolbarItem(
        id: 'alarm',
        icon: Icons.notifications_outlined,
        tooltip: 'Set alarm',
        onTap: _toggleDraft,
        placement: ChartToolbarPlacement.bottomBar,
        order: 50,
        active: _draftActive,
      ),
    ];
  }

  @override
  List<Widget> buildFloating(BuildContext context) {
    final widgets = <Widget>[];

    // Pending saved-alarm tap → open actions once.
    final pending = _pendingActionAlert;
    if (pending != null && _alerts != null) {
      _pendingActionAlert = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          showSavedAlarmActions(
            context,
            alert: pending,
            alerts: _alerts!,
          );
        }
      });
    }

    // Monitoring-off banner
    if (_showMonitoringBanner) {
      widgets.add(
        Positioned(
          top: 4,
          left: 12,
          right: 12,
          child: Material(
            color: DzColors.elevated,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: DzColors.warning, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Monitoring is off — alarms will not ring.',
                      style: DzText.caption(color: DzColors.text),
                    ),
                  ),
                  TextButton(
                    onPressed: () => AppServices.instance.startMonitoring(),
                    child: Text('Start',
                        style: DzText.caption(color: DzColors.accent)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    color: DzColors.text2,
                    onPressed: () {
                      _showMonitoringBanner = false;
                      notifyListeners();
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Draft floating bar
    if (_draft != null) {
      widgets.add(
        Positioned(
          left: 0,
          right: 0,
          bottom: 8,
          child: Center(
            child: Material(
              color: DzColors.elevated,
              borderRadius: BorderRadius.circular(24),
              elevation: 4,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: _cancelDraft,
                      child: Text('✕ Cancel',
                          style: DzText.body(color: DzColors.text2)),
                    ),
                    const SizedBox(width: 4),
                    Material(
                      color: DzColors.accent,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => _setAlarm(context),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 10),
                          child: Text(
                            'Set Alarm',
                            style: DzText.button(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Move confirm bar
    if (_moveAlert != null && _movePrice != null) {
      final prec = _controller?.mapper.pricePrecision ?? 5;
      widgets.add(
        Positioned(
          left: 0,
          right: 0,
          bottom: 8,
          child: Center(
            child: Material(
              color: DzColors.elevated,
              borderRadius: BorderRadius.circular(24),
              elevation: 4,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Move alarm to ${_movePrice!.toStringAsFixed(prec)}?',
                      style: DzText.body(),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _cancelMove,
                      child: Text('Cancel',
                          style: DzText.body(color: DzColors.text2)),
                    ),
                    TextButton(
                      onPressed: () => _confirmMove(context),
                      child: Text('Save',
                          style: DzText.body(color: DzColors.accent)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return widgets;
  }
}
