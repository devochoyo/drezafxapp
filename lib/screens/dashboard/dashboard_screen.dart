import 'dart:async';
import 'package:flutter/material.dart';
import '../add_alert/add_alert_screen.dart';
import '../common/dz_theme.dart';
import '../common/dz_widgets.dart';
import '../contracts/screen_contracts.dart';
import '../edit_alert/edit_alert_screen.dart';
import 'widgets/dashboard_widgets.dart';

/// Main screen (designs 01, 02, 09, 14). Reads alerts from
/// [AlertsGateway.watchAlerts] and current prices from
/// [MarketPriceGateway.snapshots]. It never fabricates prices.
///
/// [onOpenHistory] / [onOpenSettings] are hooks for AI 3's screens; when null
/// the matching controls do nothing.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.onOpenHistory, this.onOpenSettings});

  final VoidCallback? onOpenHistory;
  final VoidCallback? onOpenSettings;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  ScreenServices? _services;
  Stream<List<ScreenAlert>>? _alertsStream;
  Stream<MarketSnapshot>? _marketStream;
  String? _highlightId;
  Timer? _highlightTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = ScreenServices.of(context);
    if (_services?.alerts != s.alerts) _alertsStream = s.alerts.watchAlerts();
    if (_services?.market != s.market) _marketStream = s.market.snapshots;
    _services = s;
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    super.dispose();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ));
  }

  void _highlight(String id) {
    _highlightTimer?.cancel();
    setState(() => _highlightId = id);
    _highlightTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _highlightId = null);
    });
  }

  Future<void> _add() async {
    final id = await showAddAlertSheet(context);
    if (id != null && mounted) {
      _highlight(id);
      _snack('Price alert saved');
    }
  }

  Future<void> _edit(ScreenAlert a) async {
    final id = await showEditAlertSheet(context, a);
    if (id != null && mounted) {
      _highlight(id);
      _snack('Price alert updated');
    }
  }

  Future<void> _delete(ScreenAlert a) async {
    final ok = await showDeleteAlertDialog(context);
    if (!ok || !mounted) return;
    try {
      await _services!.alerts.deleteAlert(a.id);
      if (mounted) _snack('Price alert deleted');
    } catch (_) {
      if (mounted) _snack('Could not delete the alert');
    }
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DzColors.bg,
      body: SafeArea(
        bottom: false,
        child: StreamBuilder<List<ScreenAlert>>(
          stream: _alertsStream,
          builder: (context, alertSnap) {
            final loading = !alertSnap.hasData && !alertSnap.hasError;
            final alerts = alertSnap.data ?? const <ScreenAlert>[];
            return StreamBuilder<MarketSnapshot>(
              stream: _marketStream,
              builder: (context, marketSnap) {
                final market = marketSnap.data;
                return Column(
                  children: [
                    _Header(onSettings: widget.onOpenSettings),
                    Expanded(
                      child: _Body(
                        greeting: _greeting(),
                        loading: loading,
                        error: alertSnap.hasError,
                        alerts: alerts,
                        market: market,
                        marketHasError: marketSnap.hasError,
                        highlightId: _highlightId,
                        onAdd: _add,
                        onEdit: _edit,
                        onDelete: _delete,
                        onRetryMarket: _services?.market.retry,
                      ),
                    ),
                    if (!loading && alerts.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        child: DzPrimaryButton(
                          label: 'Set New Price Alert',
                          height: 52,
                          leading: const Icon(Icons.add,
                              size: 20, color: DzColors.onAccent),
                          onPressed: _add,
                        ),
                      ),
                    DzBottomNav(
                      currentIndex: 0,
                      onHistory: widget.onOpenHistory,
                      onSettings: widget.onOpenSettings,
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({this.onSettings});
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: DzColors.tint(DzColors.bg, DzColors.accent, 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.notifications,
                size: 22, color: DzColors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('FOREX ALERT',
                style: DzText.body(w: FontWeight.w700)
                    .copyWith(letterSpacing: 0.3)),
          ),
          DzCircleIconButton(
            icon: Icons.settings,
            onPressed: onSettings,
            tooltip: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.greeting,
    required this.loading,
    required this.error,
    required this.alerts,
    required this.market,
    required this.marketHasError,
    required this.highlightId,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onRetryMarket,
  });

  final String greeting;
  final bool loading;
  final bool error;
  final List<ScreenAlert> alerts;
  final MarketSnapshot? market;
  final bool marketHasError;
  final String? highlightId;
  final VoidCallback onAdd;
  final ValueChanged<ScreenAlert> onEdit;
  final ValueChanged<ScreenAlert> onDelete;
  final VoidCallback? onRetryMarket;

  @override
  Widget build(BuildContext context) {
    final activeCount = alerts
        .where((a) =>
            a.status == AlertStatus.active || a.status == AlertStatus.near)
        .length;
    final nearCount = alerts.where((a) => a.status == AlertStatus.near).length;

    final banner = marketHasError
        ? const MarketSnapshot(
            status: MarketConnectionStatus.error,
            errorMessage: 'Market data error. Prices may be unavailable.')
        : market;

    Widget content;
    if (loading) {
      content = const Center(
        child: CircularProgressIndicator(color: DzColors.accent),
      );
    } else if (error) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text('Could not load your alerts.',
              textAlign: TextAlign.center,
              style: DzText.body(color: DzColors.danger)),
        ),
      );
    } else if (alerts.isEmpty) {
      content = DashboardEmptyState(onCreate: onAdd);
    } else {
      content = Stack(
        children: [
          ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            itemCount: alerts.length,
            itemBuilder: (context, i) {
              final a = alerts[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AlertCard(
                  key: ValueKey(a.id),
                  alert: a,
                  currentPrice: market?.prices[a.pair],
                  highlighted: a.id == highlightId,
                  onEdit: () => onEdit(a),
                  onDelete: () => onDelete(a),
                ),
              );
            },
          ),
          // Fade under the floating button, as in the design.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 28,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [DzColors.bg.withAlpha(0), DzColors.bg],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(greeting, style: DzText.body(color: DzColors.text2)
                  .copyWith(fontSize: 15)),
              const SizedBox(height: 2),
              Text('My Price Alerts', style: DzText.screenTitle()),
              const SizedBox(height: 10),
              if (!loading && !error)
                Wrap(
                  spacing: 18,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _Dot(
                      color: activeCount > 0 ? DzColors.accent : DzColors.text2,
                      text: '$activeCount Active Alert'
                          '${activeCount == 1 ? '' : 's'}',
                      bold: true,
                    ),
                    if (nearCount > 0)
                      _Dot(
                          color: DzColors.warning,
                          text: '$nearCount approaching'),
                  ],
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
        if (banner != null) MarketStatusBanner(snapshot: banner, onRetry: onRetryMarket),
        Expanded(child: content),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.text, this.bold = false});
  final Color color;
  final String text;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(text,
            style: DzText.body(
                color: color, w: bold ? FontWeight.w700 : FontWeight.w500)
                .copyWith(fontSize: 15)),
      ],
    );
  }
}
