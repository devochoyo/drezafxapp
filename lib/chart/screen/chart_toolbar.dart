import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../screens/common/dz_theme.dart';
import '../contracts/chart_contracts.dart';

/// Bottom toolbar: pair chip | timeframe chip | feature icons.
class ChartToolbar extends StatelessWidget {
  const ChartToolbar({
    super.key,
    required this.symbol,
    required this.timeframe,
    required this.items,
    required this.onPairTap,
    required this.onTimeframeTap,
  });

  final String symbol;
  final ChartTimeframe timeframe;
  final List<ChartToolbarItem> items;
  final VoidCallback onPairTap;
  final VoidCallback onTimeframeTap;

  @override
  Widget build(BuildContext context) {
    final bottomItems = items
        .where((i) => i.placement == ChartToolbarPlacement.bottomBar)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    return Container(
      decoration: const BoxDecoration(
        color: DzColors.bg2,
        border: Border(top: BorderSide(color: DzColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              const SizedBox(width: 10),
              _Chip(label: symbol, onTap: onPairTap),
              const SizedBox(width: 8),
              _Chip(label: timeframe.label, onTap: onTimeframeTap),
              const Spacer(),
              for (final item in bottomItems) _FeatureIcon(item: item),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DzColors.elevated,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Text(
                label,
                style: DzText.body(w: FontWeight.w600).copyWith(fontSize: 13),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureIcon extends StatelessWidget {
  const _FeatureIcon({required this.item});
  final ChartToolbarItem item;

  @override
  Widget build(BuildContext context) {
    Widget btn = IconButton(
      icon: Icon(item.icon, size: 22),
      tooltip: item.tooltip,
      color: DzColors.text2,
      onPressed: () {
        HapticFeedback.selectionClick();
        item.onTap();
      },
    );

    if (item.active != null) {
      btn = ValueListenableBuilder<bool>(
        valueListenable: item.active!,
        builder: (_, active, child) => IconTheme(
          data: IconThemeData(
            color: active ? DzColors.accent : DzColors.text2,
          ),
          child: child!,
        ),
        child: btn,
      );
    }
    if (item.enabled != null) {
      btn = ValueListenableBuilder<bool>(
        valueListenable: item.enabled!,
        builder: (_, enabled, child) => Opacity(
          opacity: enabled ? 1 : 0.35,
          child: IgnorePointer(ignoring: !enabled, child: child),
        ),
        child: btn,
      );
    }
    return btn;
  }
}
