import 'package:flutter/material.dart';

import '../../screens/common/dz_theme.dart';
import '../../screens/common/dz_widgets.dart';
import 'drawing_models.dart';

/// Drawing tool sheet: Horizontal Line, Trendline, Rectangle + toggles.
Future<DrawingType?> showDrawingSheet(
  BuildContext context, {
  required bool stayInMode,
  required bool magnet,
  required ValueChanged<bool> onStayInMode,
  required ValueChanged<bool> onMagnet,
  required VoidCallback onClearAll,
}) {
  return showDzModalSheet<DrawingType>(
    context,
    builder: (ctx) => _DrawingSheetBody(
      stayInMode: stayInMode,
      magnet: magnet,
      onStayInMode: onStayInMode,
      onMagnet: onMagnet,
      onClearAll: onClearAll,
    ),
  );
}

class _DrawingSheetBody extends StatefulWidget {
  const _DrawingSheetBody({
    required this.stayInMode,
    required this.magnet,
    required this.onStayInMode,
    required this.onMagnet,
    required this.onClearAll,
  });

  final bool stayInMode;
  final bool magnet;
  final ValueChanged<bool> onStayInMode;
  final ValueChanged<bool> onMagnet;
  final VoidCallback onClearAll;

  @override
  State<_DrawingSheetBody> createState() => _DrawingSheetBodyState();
}

class _DrawingSheetBodyState extends State<_DrawingSheetBody> {
  late bool _stay = widget.stayInMode;
  late bool _magnet = widget.magnet;

  @override
  Widget build(BuildContext context) {
    return DzSheet(
      title: 'Drawing',
      onClose: () => Navigator.of(context).pop(),
      initialSize: 0.55,
      footer: const SizedBox.shrink(),
      bodyBuilder: (scrollCtrl) {
        return ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // Toggles
            Row(
              children: [
                Expanded(
                  child: _ToggleCard(
                    icon: Icons.edit_note,
                    label: 'Stay in drawing mode',
                    value: _stay,
                    onChanged: (v) {
                      setState(() => _stay = v);
                      widget.onStayInMode(v);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ToggleCard(
                    icon: Icons.near_me_outlined,
                    label: 'Magnet',
                    value: _magnet,
                    onChanged: (v) {
                      setState(() => _magnet = v);
                      widget.onMagnet(v);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _ToolRow(
              icon: Icons.horizontal_rule,
              label: 'Horizontal Line',
              onTap: () =>
                  Navigator.pop(context, DrawingType.horizontalLine),
            ),
            _ToolRow(
              icon: Icons.show_chart,
              label: 'Trendline',
              onTap: () => Navigator.pop(context, DrawingType.trendline),
            ),
            _ToolRow(
              icon: Icons.crop_square,
              label: 'Rectangle',
              onTap: () => Navigator.pop(context, DrawingType.rectangle),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: DzColors.elevated,
                    title: Text('Clear all drawings?', style: DzText.sheetTitle()),
                    content: Text(
                      'This removes every drawing on the current pair.',
                      style: DzText.body(color: DzColors.text2),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text('Cancel',
                            style: DzText.body(color: DzColors.text2)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text('Clear',
                            style: DzText.body(color: DzColors.danger)),
                      ),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  widget.onClearAll();
                  Navigator.pop(context);
                }
              },
              child: Text(
                'Clear all drawings (this pair)',
                style: DzText.body(color: DzColors.danger),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ToggleCard extends StatelessWidget {
  const _ToggleCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: value ? DzColors.accent.withAlpha(40) : DzColors.elevated,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Icon(icon,
                  color: value ? DzColors.accent : DzColors.text2, size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: DzText.caption(
                  color: value ? DzColors.accent : DzColors.text2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: DzColors.text),
      title: Text(label, style: DzText.body()),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }
}
