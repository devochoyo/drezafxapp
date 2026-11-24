import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../common/dz_theme.dart';
import '../common/dz_widgets.dart';
import '../common/pair_utils.dart';
import '../contracts/screen_contracts.dart';
import '../sound_selection/sound_selection_screen.dart';
import 'currency_pair_picker.dart';

/// Form shared by Add Alert and Edit Alert (identical layout per designs
/// 04/05/13). There is deliberately NO Above/Below or direction selector:
/// the foundation detects crossings automatically in both directions.
///
/// Pops with the alert id returned by [onSubmit], or null on cancel.
class AlertFormSheet extends StatefulWidget {
  const AlertFormSheet({
    super.key,
    required this.title,
    required this.submitLabel,
    required this.onSubmit,
    this.initial,
  });

  final String title;
  final String submitLabel;
  final AlertDraft? initial;
  final Future<String> Function(AlertDraft draft) onSubmit;

  @override
  State<AlertFormSheet> createState() => _AlertFormSheetState();
}

class _AlertFormSheetState extends State<AlertFormSheet> {
  final _sheetController = DraggableScrollableController();
  final _priceController = TextEditingController();
  final _priceFocus = FocusNode();

  late String _pair;
  late AlertCategory _category;
  late String _soundFile;
  late bool _soundChosen; // once true, category changes no longer swap sound

  String? _priceError;
  String? _submitError;
  bool _saving = false;

  String? _previewing;
  StreamSubscription<String?>? _sub;
  SoundGateway? _sounds;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _pair = i?.pair ?? kSupportedPairs.first;
    _category = i?.category ?? AlertCategory.entryLevelReached;
    _soundFile = i?.soundFile ?? _category.defaultSoundFile;
    _soundChosen = i != null; // editing keeps the stored sound
    if (i != null) {
      _priceController.text = editablePrice(i.targetPrice, i.pair);
    }
    _priceFocus.addListener(() {
      if (!mounted) return;
      setState(() {});
      if (_priceFocus.hasFocus && _sheetController.isAttached) {
        _sheetController.animateTo(0.94,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sounds == null) {
      _sounds = ScreenServices.of(context).sounds;
      _sub = _sounds!.previewingFile.listen((f) {
        if (mounted) setState(() => _previewing = f);
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sounds?.stopPreview();
    _priceController.dispose();
    _priceFocus.dispose();
    _sheetController.dispose();
    super.dispose();
  }

  Future<void> _pickPair() async {
    FocusScope.of(context).unfocus();
    final p = await showCurrencyPairPicker(context, selected: _pair);
    if (p != null && mounted) {
      setState(() {
        _pair = p;
        _priceError = null;
      });
    }
  }

  Future<void> _chooseSound() async {
    FocusScope.of(context).unfocus();
    await _sounds?.stopPreview();
    if (!mounted) return;
    final f = await showSoundSelectionSheet(context, selectedFile: _soundFile);
    if (f != null && mounted) {
      setState(() {
        _soundFile = f;
        _soundChosen = true;
      });
    }
  }

  Future<void> _togglePreview() async {
    final sounds = _sounds;
    if (sounds == null) return;
    try {
      if (_previewing == _soundFile) {
        await sounds.stopPreview();
      } else {
        await sounds.preview(_soundFile);
      }
    } catch (_) {
      if (mounted) setState(() => _submitError = 'Could not play this sound');
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final err = validateTargetPrice(_priceController.text, _pair);
    if (err != null) {
      setState(() {
        _priceError = err;
        _submitError = null;
      });
      return;
    }
    FocusScope.of(context).unfocus();
    await _sounds?.stopPreview();
    setState(() {
      _priceError = null;
      _submitError = null;
      _saving = true;
    });
    try {
      final id = await widget.onSubmit(AlertDraft(
        pair: _pair,
        targetPrice: parseTargetPrice(_priceController.text)!,
        category: _category,
        soundFile: _soundFile,
      ));
      if (mounted) Navigator.of(context).pop(id);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _submitError = 'Could not save the alert. Please try again.';
        });
      }
    }
  }

  void _cancel() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    return DzSheet(
      title: widget.title,
      controller: _sheetController,
      initialSize: 0.62,
      onClose: _cancel,
      bodyBuilder: (sc) => SingleChildScrollView(
        controller: sc,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('Currency Pair'),
            _PairField(pair: _pair, onTap: _pickPair),
            const SizedBox(height: 20),
            _label('Target Price'),
            _PriceField(
              controller: _priceController,
              focusNode: _priceFocus,
              quote: quoteCurrency(_pair),
              error: _priceError,
              onChanged: (_) {
                if (_priceError != null) setState(() => _priceError = null);
              },
              onSubmitted: (_) => _save(),
            ),
            if (_priceError != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.error, size: 16, color: DzColors.danger),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_priceError!,
                        style: DzText.body(color: DzColors.danger)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            _label('Alert Type'),
            _CategoryGrid(
              selected: _category,
              onChanged: (c) => setState(() {
                _category = c;
                if (!_soundChosen) _soundFile = c.defaultSoundFile;
              }),
            ),
            const SizedBox(height: 20),
            _label('Notification Sound'),
            _SoundRowCard(
              name: soundDisplayName(_soundFile),
              playing: _previewing == _soundFile,
              onPlay: _togglePreview,
              onChoose: _chooseSound,
            ),
            if (_submitError != null) ...[
              const SizedBox(height: 12),
              Text(_submitError!, style: DzText.body(color: DzColors.danger)),
            ],
          ],
        ),
      ),
      footer: Row(
        children: [
          SizedBox(
            width: 112,
            child: DzSecondaryButton(label: 'Cancel', onPressed: _cancel),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DzPrimaryButton(
              label: widget.submitLabel,
              loading: _saving,
              onPressed: _save,
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(t, style: DzText.label()),
      );
}

class _PairField extends StatelessWidget {
  const _PairField({required this.pair, required this.onTap});
  final String pair;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DzColors.elevated,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DzColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(pairDisplay(pair),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DzText.body(w: FontWeight.w700)
                        .copyWith(fontSize: 17)),
              ),
              const Icon(Icons.search, size: 22, color: DzColors.text2),
            ],
          ),
        ),
      ),
    );
  }
}

class _PriceField extends StatelessWidget {
  const _PriceField({
    required this.controller,
    required this.focusNode,
    required this.quote,
    required this.error,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String quote;
  final String? error;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final hasError = error != null;
    final active = focusNode.hasFocus || controller.text.isNotEmpty;
    final borderColor = hasError
        ? DzColors.danger
        : (active ? DzColors.accent : DzColors.border);
    return Container(
      height: 64,
      padding: const EdgeInsets.only(left: 18, right: 12),
      decoration: BoxDecoration(
        color: DzColors.elevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: borderColor, width: (hasError || active) ? 1.5 : 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              cursorColor: DzColors.accent,
              style: DzText.displayPrice(),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: 'Enter target price',
                hintStyle: DzText.displayPrice(color: DzColors.text2)
                    .copyWith(fontSize: 22, fontWeight: FontWeight.w400),
              ),
              onChanged: onChanged,
              onSubmitted: onSubmitted,
            ),
          ),
          if (quote.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: DzColors.bg2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(quote,
                  style: DzText.body(color: DzColors.text2, w: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.selected, required this.onChanged});
  final AlertCategory selected;
  final ValueChanged<AlertCategory> onChanged;

  @override
  Widget build(BuildContext context) {
    const cats = AlertCategory.values; // exactly the six categories
    return Column(
      children: [
        for (var r = 0; r < cats.length; r += 2)
          Padding(
            padding: EdgeInsets.only(bottom: r + 2 < cats.length ? 8 : 0),
            child: Row(
              children: [
                Expanded(child: _chip(cats[r])),
                const SizedBox(width: 8),
                Expanded(child: _chip(cats[r + 1])),
              ],
            ),
          ),
      ],
    );
  }

  Widget _chip(AlertCategory c) {
    final sel = c == selected;
    return Material(
      color: sel
          ? DzColors.tint(DzColors.card, DzColors.accent, 0.2)
          : DzColors.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onChanged(c),
        child: Container(
          height: 40,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: sel ? DzColors.accent : DzColors.border,
                width: sel ? 1.5 : 1),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              c.chipLabel,
              maxLines: 1,
              style: DzText.body(
                  color: sel ? DzColors.accent : DzColors.text,
                  w: sel ? FontWeight.w600 : FontWeight.w400)
                  .copyWith(fontSize: 13),
            ),
          ),
        ),
      ),
    );
  }
}

class _SoundRowCard extends StatelessWidget {
  const _SoundRowCard({
    required this.name,
    required this.playing,
    required this.onPlay,
    required this.onChoose,
  });

  final String name;
  final bool playing;
  final VoidCallback onPlay;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: DzColors.elevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DzColors.border),
      ),
      child: Row(
        children: [
          DzPreviewButton(playing: playing, onPressed: onPlay, size: 40),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: DzText.body(w: FontWeight.w700)
                        .copyWith(fontSize: 15)),
                const SizedBox(height: 2),
                Text('Tap play to preview', style: DzText.label()),
              ],
            ),
          ),
          TextButton(
            onPressed: onChoose,
            style: TextButton.styleFrom(
              foregroundColor: DzColors.accent2,
              minimumSize: const Size(48, 48),
            ),
            child: Text('Choose Sound',
                style: DzText.body(color: DzColors.accent2, w: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
