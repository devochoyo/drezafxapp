import 'package:flutter/material.dart';

import '../../screens/common/dz_theme.dart';
import '../contracts/chart_contracts.dart';
import '../engine/chart_controller_impl.dart';

/// Top-left: green dot + SYMBOL, TF + price / change (or OHLC when crosshair).
/// Top-right: feature items with [ChartToolbarPlacement.topBar] (undo/redo).
class ChartHeader extends StatelessWidget {
  const ChartHeader({
    super.key,
    required this.controller,
    required this.topBarItems,
    this.onPairTap,
    this.trailing,
  });

  final ChartControllerImpl controller;
  final List<ChartToolbarItem> topBarItems;
  final VoidCallback? onPairTap;
  /// Extra widgets on the far right (e.g. landscape phone icon).
  final List<Widget>? trailing;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final cross = c.crosshairCandle;
        final change = c.dailyChange;
        final pct = c.dailyChangePercent;
        final price = c.lastPrice;
        final prec = c.mapper.pricePrecision;

        final changeColor = (change == null || change >= 0)
            ? DzColors.accent
            : DzColors.danger;

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: pair + price
              Expanded(
                child: InkWell(
                  onTap: onPairTap,
                  borderRadius: BorderRadius.circular(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: DzColors.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '${c.symbol}, ${c.timeframe.label}',
                              style: DzText.pair(),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      if (cross != null)
                        Text(
                          'O ${cross.open.toStringAsFixed(prec)}  '
                          'H ${cross.high.toStringAsFixed(prec)}  '
                          'L ${cross.low.toStringAsFixed(prec)}  '
                          'C ${cross.close.toStringAsFixed(prec)}',
                          style: DzText.caption(color: DzColors.text)
                              .copyWith(fontSize: 12),
                        )
                      else if (price != null)
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: price.toStringAsFixed(prec),
                                style: DzText.body(
                                  color: changeColor,
                                  w: FontWeight.w600,
                                ).copyWith(
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                              if (change != null && pct != null) ...[
                                const TextSpan(text: '  '),
                                TextSpan(
                                  text:
                                      '${change >= 0 ? '' : ''}${change.toStringAsFixed(prec)} '
                                      '(${pct >= 0 ? '' : ''}${pct.toStringAsFixed(2)}%)',
                                  style: DzText.caption(color: changeColor)
                                      .copyWith(fontSize: 12),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // Right: top-bar feature items + optional trailing
              for (final item in topBarItems)
                _TopIcon(item: item),
              if (trailing != null) ...trailing!,
            ],
          ),
        );
      },
    );
  }
}

class _TopIcon extends StatelessWidget {
  const _TopIcon({required this.item});
  final ChartToolbarItem item;

  @override
  Widget build(BuildContext context) {
    final enabledListenable = item.enabled;
    final activeListenable = item.active;

    Widget icon = IconButton(
      icon: Icon(item.icon, size: 20),
      tooltip: item.tooltip,
      color: DzColors.text2,
      onPressed: item.onTap,
      visualDensity: VisualDensity.compact,
    );

    if (enabledListenable != null) {
      icon = ValueListenableBuilder<bool>(
        valueListenable: enabledListenable,
        builder: (_, enabled, child) => Opacity(
          opacity: enabled ? 1 : 0.35,
          child: IgnorePointer(ignoring: !enabled, child: child),
        ),
        child: icon,
      );
    }
    if (activeListenable != null) {
      icon = ValueListenableBuilder<bool>(
        valueListenable: activeListenable,
        builder: (_, active, child) => IconTheme(
          data: IconThemeData(
            color: active ? DzColors.accent : DzColors.text2,
          ),
          child: child!,
        ),
        child: icon,
      );
    }
    return icon;
  }
}
