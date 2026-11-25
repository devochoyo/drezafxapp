import 'package:flutter/material.dart';

import '../../screens/common/dz_theme.dart';
import '../../screens/common/dz_widgets.dart';
import '../contracts/chart_contracts.dart';

/// Compact grid of timeframe chips.
Future<ChartTimeframe?> showTimeframeSheet(
  BuildContext context, {
  required ChartTimeframe current,
}) {
  return showDzModalSheet<ChartTimeframe>(
    context,
    builder: (ctx) => _TimeframeSheetBody(current: current),
  );
}

class _TimeframeSheetBody extends StatelessWidget {
  const _TimeframeSheetBody({required this.current});

  final ChartTimeframe current;

  static const _order = [
    ChartTimeframe.m1,
    ChartTimeframe.m5,
    ChartTimeframe.m15,
    ChartTimeframe.h1,
    ChartTimeframe.h2,
    ChartTimeframe.h4,
    ChartTimeframe.d1,
    ChartTimeframe.w1,
  ];

  @override
  Widget build(BuildContext context) {
    return DzSheet(
      title: 'Timeframe',
      onClose: () => Navigator.of(context).pop(),
      initialSize: 0.42,
      footer: const SizedBox.shrink(),
      bodyBuilder: (scrollCtrl) {
        return GridView.count(
          controller: scrollCtrl,
          crossAxisCount: 4,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          childAspectRatio: 1.8,
          children: [
            for (final tf in _order)
              _Chip(
                label: tf.label,
                selected: tf == current,
                onTap: () => Navigator.of(context).pop(tf),
              ),
          ],
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? DzColors.accent : DzColors.elevated,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: DzText.body(
              color: selected ? DzColors.onAccent : DzColors.text,
              w: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
