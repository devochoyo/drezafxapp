import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../common/category_style.dart';
import '../../common/dz_theme.dart';
import '../../common/dz_widgets.dart';
import '../../common/pair_utils.dart';
import '../../contracts/screen_contracts.dart';

/// Design: ActiveAlertCard (components.md #1), 01_dashboard.png.
class AlertCard extends StatelessWidget {
  const AlertCard({
    super.key,
    required this.alert,
    required this.currentPrice,
    required this.onEdit,
    required this.onDelete,
    this.highlighted = false,
  });

  final ScreenAlert alert;

  /// Live price from the market-data stream; null = unknown (shows "—").
  final double? currentPrice;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final near = alert.status == AlertStatus.near;
    final catColor = categoryColor(alert.category);
    final tileColor = near ? DzColors.warning : catColor;
    final nowColor = near ? DzColors.warning : DzColors.text2;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 12),
      decoration: BoxDecoration(
        color: DzColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted ? DzColors.accent : DzColors.border,
          width: highlighted ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: DzColors.tint(DzColors.card, tileColor, 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.notifications, size: 20, color: tileColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pairDisplay(alert.pair),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DzText.pair()),
                    const SizedBox(height: 2),
                    Text(alert.category.cardCaption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DzText.caption(color: catColor)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(status: alert.status),
              const SizedBox(width: 4),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                flex: 5,
                child: _PriceColumn(
                  label: 'TARGET',
                  value: formatPrice(alert.targetPrice, alert.pair),
                  style: DzText.cardPrice(),
                ),
              ),
              Expanded(
                flex: 5,
                child: _PriceColumn(
                  label: 'NOW',
                  value: currentPrice == null
                      ? '—'
                      : formatPrice(currentPrice!, alert.pair),
                  style: DzText.cardPrice(color: nowColor)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              _ActionButton(
                icon: Icons.edit_outlined,
                color: DzColors.accent2,
                tooltip: 'Edit alert',
                onTap: onEdit,
              ),
              _ActionButton(
                icon: Icons.delete_outline,
                color: DzColors.danger,
                tooltip: 'Delete alert',
                onTap: onDelete,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Flexible(
                child: Text(alert.category.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DzText.label().copyWith(fontWeight: FontWeight.w400)),
              ),
              Text('  •  ',
                  style: DzText.label().copyWith(fontWeight: FontWeight.w400)),
              const Icon(Icons.volume_up, size: 13, color: DzColors.text2),
              const SizedBox(width: 3),
              Flexible(
                child: Text(soundDisplayName(alert.soundFile),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DzText.label().copyWith(fontWeight: FontWeight.w400)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PriceColumn extends StatelessWidget {
  const _PriceColumn(
      {required this.label, required this.value, required this.style});
  final String label;
  final String value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: DzText.caption()),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, maxLines: 1, style: style),
        ),
      ],
    );
  }
}

/// 32 dp visual tile inside a 44 dp hit area.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: DzColors.tint(DzColors.card, color, 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
          ),
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});
  final AlertStatus status;

  @override
  Widget build(BuildContext context) {
    late final String text;
    late final Color color;
    switch (status) {
      case AlertStatus.active:
        text = 'ACTIVE';
        color = DzColors.accent;
        break;
      case AlertStatus.near:
        text = 'NEAR';
        color = DzColors.warning;
        break;
      case AlertStatus.triggered:
        text = 'TRIGGERED';
        color = DzColors.danger;
        break;
      case AlertStatus.inactive:
        text = 'INACTIVE';
        color = DzColors.text2;
        break;
    }
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: DzColors.tint(DzColors.card, color, 0.2),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(text, style: DzText.pill(color)),
        ],
      ),
    );
  }
}

/// Design: 09_delete_confirmation.png. Resolves true when "Delete Alert".
Future<bool> showDeleteAlertDialog(BuildContext context) async {
  final r = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withAlpha(171),
    builder: (ctx) => Dialog(
      backgroundColor: DzColors.elevated,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 337),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: DzColors.tint(DzColors.elevated, DzColors.danger, 0.2),
                ),
                child: const Icon(Icons.delete_outline,
                    color: DzColors.danger, size: 26),
              ),
              const SizedBox(height: 16),
              Text('Delete Price Alert?',
                  textAlign: TextAlign.center, style: DzText.sheetTitle()),
              const SizedBox(height: 10),
              Text(
                'Are you sure you want to delete this price alert? '
                'This action cannot be undone.',
                textAlign: TextAlign.center,
                style: DzText.body(color: DzColors.text2)
                    .copyWith(fontSize: 14.5, height: 1.4),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: DzSecondaryButton(
                      label: 'Cancel',
                      height: 46,
                      background: DzColors.tint(
                          DzColors.elevated, DzColors.bg2, 0.5),
                      onPressed: () => Navigator.of(ctx).pop(false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Material(
                      color: DzColors.danger,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => Navigator.of(ctx).pop(true),
                        child: SizedBox(
                          height: 46,
                          child: Center(
                            child: Text('Delete Alert',
                                maxLines: 1,
                                style: DzText.button(color: Colors.white)
                                    .copyWith(fontSize: 15)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return r ?? false;
}

/// Design: EmptyStateWidget (components.md #12), 02_dashboard_empty.png.
class DashboardEmptyState extends StatelessWidget {
  const DashboardEmptyState({super.key, required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 130,
              height: 130,
              child: CustomPaint(
                painter: _DashedRingPainter(),
                child: Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: DzColors.card,
                          shape: BoxShape.circle,
                          border: Border.all(color: DzColors.border),
                        ),
                        child: const Icon(Icons.notifications,
                            size: 34, color: DzColors.accent),
                      ),
                      Positioned(
                        right: -8,
                        top: -8,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: const BoxDecoration(
                              color: DzColors.accent, shape: BoxShape.circle),
                          child: const Icon(Icons.add,
                              size: 16, color: DzColors.onAccent),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('No price alerts yet',
                textAlign: TextAlign.center,
                style: DzText.sheetTitle().copyWith(fontSize: 22)),
            const SizedBox(height: 8),
            Text(
              'Create your first alert and never\nmiss your trading level.',
              textAlign: TextAlign.center,
              style: DzText.body(color: DzColors.text2).copyWith(height: 1.4),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 260,
              child: DzPrimaryButton(
                  label: 'Create Your First Alert', onPressed: onCreate),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedRingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = DzColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rect = Offset.zero & size;
    const dashes = 36;
    const sweep = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect.deflate(1), i * sweep, sweep * 0.55, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Market-data status strip (disconnected / error / connecting).
class MarketStatusBanner extends StatelessWidget {
  const MarketStatusBanner({super.key, required this.snapshot, this.onRetry});
  final MarketSnapshot snapshot;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    late final String text;
    late final Color color;
    late final IconData icon;
    switch (snapshot.status) {
      case MarketConnectionStatus.connected:
        return const SizedBox.shrink();
      case MarketConnectionStatus.connecting:
        text = 'Connecting to market data…';
        color = DzColors.accent2;
        icon = Icons.sync;
        break;
      case MarketConnectionStatus.disconnected:
        text = snapshot.errorMessage ??
            'Market data disconnected. Current prices are unavailable.';
        color = DzColors.warning;
        icon = Icons.cloud_off;
        break;
      case MarketConnectionStatus.error:
        text = snapshot.errorMessage ?? 'Market data error. Prices may be unavailable.';
        color = DzColors.danger;
        icon = Icons.error_outline;
        break;
    }
    final canRetry = onRetry != null &&
        snapshot.status != MarketConnectionStatus.connecting;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: DzColors.tint(DzColors.bg, color, 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DzColors.tint(DzColors.bg, color, 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: DzText.label(color: DzColors.text).copyWith(
                    fontWeight: FontWeight.w500)),
          ),
          if (canRetry)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                  foregroundColor: color, minimumSize: const Size(48, 40)),
              child: Text('Retry', style: DzText.label(color: color)),
            ),
        ],
      ),
    );
  }
}
