import 'package:flutter/material.dart';

import '../../screens/common/dz_theme.dart';
import 'drawing_models.dart';

/// Compact style bar shown when a shape is selected (top-centre).
class DrawingStyleBar extends StatelessWidget {
  const DrawingStyleBar({
    super.key,
    required this.shape,
    required this.onStyleChanged,
    required this.onDelete,
  });

  final DrawingShape shape;
  final ValueChanged<DrawingStyle> onStyleChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final style = shape.style;
    return Material(
      color: DzColors.elevated,
      borderRadius: BorderRadius.circular(20),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Colour swatches
            for (final c in DrawingStyle.presetColors)
              GestureDetector(
                onTap: () => onStyleChanged(style.copyWith(colorValue: c)),
                child: Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: style.colorValue == c
                          ? DzColors.text
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 6),
            // Width
            for (final w in [1.0, 2.0, 3.0])
              _MiniChip(
                label: '${w.toInt()}',
                selected: style.width == w,
                onTap: () => onStyleChanged(style.copyWith(width: w)),
              ),
            // Rectangle fill
            if (shape.type == DrawingType.rectangle) ...[
              const SizedBox(width: 4),
              for (final a in [0x15, 0x33, 0x66])
                _MiniChip(
                  label: a == 0x15 ? 'L' : (a == 0x33 ? 'M' : 'H'),
                  selected: style.fillAlpha.round() == a,
                  onTap: () =>
                      onStyleChanged(style.copyWith(fillAlpha: a.toDouble())),
                ),
            ],
            // Trendline extend
            if (shape.type == DrawingType.trendline) ...[
              const SizedBox(width: 4),
              _MiniChip(
                label: '→',
                selected: style.extendRight,
                onTap: () => onStyleChanged(
                    style.copyWith(extendRight: !style.extendRight)),
              ),
            ],
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              color: DzColors.danger,
              onPressed: onDelete,
              visualDensity: VisualDensity.compact,
              tooltip: 'Delete',
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? DzColors.accent : DzColors.bg2,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? DzColors.onAccent : DzColors.text2,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
