import 'package:flutter/material.dart';
import '../common/dz_theme.dart';
import '../common/dz_widgets.dart';
import '../common/pair_utils.dart';

/// Searchable list of pairs. Resolves to a pair code ("EURUSD") or null.
Future<String?> showCurrencyPairPicker(
  BuildContext context, {
  required String selected,
}) {
  return showDzModalSheet<String>(
    context,
    builder: (_) => _CurrencyPairPicker(selected: selected),
  );
}

class _CurrencyPairPicker extends StatefulWidget {
  const _CurrencyPairPicker({required this.selected});
  final String selected;

  @override
  State<_CurrencyPairPicker> createState() => _CurrencyPairPickerState();
}

class _CurrencyPairPickerState extends State<_CurrencyPairPicker> {
  String _query = '';

  List<String> get _filtered {
    final q = _query.replaceAll('/', '').trim().toUpperCase();
    if (q.isEmpty) return kSupportedPairs;
    return kSupportedPairs.where((p) => p.contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final pairs = _filtered;
    return DzSheet(
      title: 'Select Currency Pair',
      initialSize: 0.8,
      onClose: () => Navigator.of(context).pop(),
      footer: DzSecondaryButton(
        label: 'Cancel',
        onPressed: () => Navigator.of(context).pop(),
      ),
      bodyBuilder: (sc) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: DzColors.elevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: DzColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 20, color: DzColors.text2),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      autofocus: false,
                      textCapitalization: TextCapitalization.characters,
                      style: DzText.body(w: FontWeight.w600),
                      cursorColor: DzColors.accent,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        hintText: 'Search pair',
                        hintStyle: DzText.body(color: DzColors.text2),
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: pairs.isEmpty
                ? Center(
                    child: Text('No matching pairs',
                        style: DzText.body(color: DzColors.text2)),
                  )
                : ListView.builder(
                    controller: sc,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: pairs.length,
                    itemBuilder: (context, i) {
                      final p = pairs[i];
                      final sel = p == widget.selected;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: sel
                              ? DzColors.tint(
                                  DzColors.card, DzColors.accent, 0.15)
                              : DzColors.card,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => Navigator.of(context).pop(p),
                            child: Container(
                              height: 52,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color:
                                      sel ? DzColors.accent : DzColors.border,
                                  width: sel ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(pairDisplay(p),
                                        style: DzText.body(w: FontWeight.w700)
                                            .copyWith(fontSize: 16)),
                                  ),
                                  if (sel)
                                    const Icon(Icons.check,
                                        size: 20, color: DzColors.accent),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
