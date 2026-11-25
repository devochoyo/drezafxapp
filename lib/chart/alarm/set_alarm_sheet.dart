import 'package:flutter/material.dart';

import '../../screens/common/dz_theme.dart';
import '../../screens/common/dz_widgets.dart';
import '../../screens/contracts/screen_contracts.dart';
import '../../screens/sound_selection/sound_selection_screen.dart';
import 'alarm_chart_math.dart';

/// Bottom sheet: pair + price, category chips, sound, Set Alarm.
Future<bool> showSetAlarmSheet(
  BuildContext context, {
  required String symbol,
  required double price,
  required int pricePrecision,
  required AlertsGateway alerts,
}) async {
  final result = await showDzModalSheet<bool>(
    context,
    builder: (ctx) => _SetAlarmBody(
      symbol: symbol,
      initialPrice: price,
      pricePrecision: pricePrecision,
      alerts: alerts,
    ),
  );
  return result == true;
}

class _SetAlarmBody extends StatefulWidget {
  const _SetAlarmBody({
    required this.symbol,
    required this.initialPrice,
    required this.pricePrecision,
    required this.alerts,
  });

  final String symbol;
  final double initialPrice;
  final int pricePrecision;
  final AlertsGateway alerts;

  @override
  State<_SetAlarmBody> createState() => _SetAlarmBodyState();
}

class _SetAlarmBodyState extends State<_SetAlarmBody> {
  late AlertCategory _category = AlertCategory.generalPriceTargetReached;
  late String _soundFile = _category.defaultSoundFile;
  bool _userPickedSound = false;
  bool _saving = false;
  String? _error;
  late final TextEditingController _priceCtrl;

  @override
  void initState() {
    super.initState();
    _priceCtrl = TextEditingController(
      text: widget.initialPrice.toStringAsFixed(widget.pricePrecision),
    );
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickSound() async {
    final chosen = await showSoundSelectionSheet(
      context,
      selectedFile: _soundFile,
    );
    if (chosen != null && mounted) {
      setState(() {
        _soundFile = chosen;
        _userPickedSound = true;
      });
    }
  }

  Future<void> _submit() async {
    final raw = double.tryParse(_priceCtrl.text.trim());
    if (raw == null || raw <= 0) {
      setState(() => _error = 'Enter a valid price');
      return;
    }
    final price = AlarmChartMath.roundToPrecision(raw, widget.pricePrecision);

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.alerts.createAlert(AlertDraft(
        pair: widget.symbol,
        targetPrice: price,
        category: _category,
        soundFile: _soundFile,
      ));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DzSheet(
      title: 'Set Alarm',
      onClose: () => Navigator.of(context).pop(false),
      initialSize: 0.62,
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: DzPrimaryButton(
          label: 'Set Alarm',
          loading: _saving,
          onPressed: _saving ? null : _submit,
        ),
      ),
      bodyBuilder: (scrollCtrl) {
        return ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          children: [
            // Pair + price
            Text(widget.symbol, style: DzText.label()),
            const SizedBox(height: 6),
            TextField(
              controller: _priceCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: DzText.displayPrice(),
              cursorColor: DzColors.accent,
              decoration: InputDecoration(
                filled: true,
                fillColor: DzColors.elevated,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: DzText.caption(color: DzColors.danger)),
            ],
            const SizedBox(height: 20),

            // Categories
            Text('Alarm type', style: DzText.label()),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final cat in AlertCategory.values)
                  ChoiceChip(
                    label: Text(
                      cat.chipLabel,
                      style: DzText.caption(
                        color: _category == cat
                            ? DzColors.onAccent
                            : DzColors.text,
                      ).copyWith(fontSize: 11),
                    ),
                    selected: _category == cat,
                    selectedColor: DzColors.accent,
                    backgroundColor: DzColors.elevated,
                    onSelected: (_) {
                      setState(() {
                        _category = cat;
                        if (!_userPickedSound) {
                          _soundFile = cat.defaultSoundFile;
                        }
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 20),

            // Sound
            Text('Sound', style: DzText.label()),
            const SizedBox(height: 8),
            Material(
              color: DzColors.elevated,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _pickSound,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Row(
                    children: [
                      const Icon(Icons.volume_up_outlined,
                          color: DzColors.text2, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          soundDisplayName(_soundFile),
                          style: DzText.body(),
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: DzColors.text2),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
