import 'dart:async';
import 'package:flutter/material.dart';
import '../common/dz_theme.dart';
import '../common/dz_widgets.dart';
import '../contracts/screen_contracts.dart';

/// Opens the Sound Selection sheet. Resolves to the confirmed sound file name,
/// or null if dismissed without pressing "Use This Sound".
Future<String?> showSoundSelectionSheet(
  BuildContext context, {
  required String selectedFile,
}) {
  return showDzModalSheet<String>(
    context,
    builder: (_) => SoundSelectionScreen(selectedFile: selectedFile),
  );
}

/// Design: 06_sound_selection.png
class SoundSelectionScreen extends StatefulWidget {
  const SoundSelectionScreen({super.key, required this.selectedFile});

  final String selectedFile;

  @override
  State<SoundSelectionScreen> createState() => _SoundSelectionScreenState();
}

class _SoundSelectionScreenState extends State<SoundSelectionScreen> {
  late String _selected = widget.selectedFile;
  String? _previewing;
  StreamSubscription<String?>? _sub;
  SoundGateway? _sounds;

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
    _sounds?.stopPreview(); // never leave audio playing after the sheet closes
    super.dispose();
  }

  Future<void> _togglePreview(String file) async {
    final sounds = _sounds;
    if (sounds == null) return;
    try {
      if (_previewing == file) {
        await sounds.stopPreview();
      } else {
        await sounds.preview(file); // service must stop any other preview
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Could not play this sound')),
      );
    }
  }

  Future<void> _confirm() async {
    await _sounds?.stopPreview();
    if (mounted) Navigator.of(context).pop(_selected);
  }

  @override
  Widget build(BuildContext context) {
    return DzSheet(
      title: 'Choose Alert Sound',
      subtitle: 'Tap play to preview before selecting',
      initialSize: 0.88,
      bodyBuilder: (sc) => ListView.builder(
        controller: sc,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        itemCount: kSoundOptions.length,
        itemBuilder: (context, i) {
          final o = kSoundOptions[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SoundRow(
              option: o,
              selected: _selected == o.file,
              playing: _previewing == o.file,
              onSelect: () => setState(() => _selected = o.file),
              onPlay: () => _togglePreview(o.file),
            ),
          );
        },
      ),
      footer: DzPrimaryButton(
        label: 'Use This Sound',
        onPressed: _confirm,
      ),
    );
  }
}

class _SoundRow extends StatelessWidget {
  const _SoundRow({
    required this.option,
    required this.selected,
    required this.playing,
    required this.onSelect,
    required this.onPlay,
  });

  final SoundOption option;
  final bool selected;
  final bool playing;
  final VoidCallback onSelect;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? DzColors.tint(DzColors.card, DzColors.accent, 0.15)
          : DzColors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onSelect,
        child: Container(
          constraints: const BoxConstraints(minHeight: 74),
          padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? DzColors.accent : DzColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              DzPreviewButton(
                playing: playing,
                highlighted: selected,
                onPressed: onPlay,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(option.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DzText.body(w: FontWeight.w700)
                            .copyWith(fontSize: 15)),
                    const SizedBox(height: 3),
                    Text(option.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DzText.label().copyWith(
                            fontWeight: FontWeight.w400, fontSize: 12.5)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _RadioMark(selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadioMark extends StatelessWidget {
  const _RadioMark({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? DzColors.accent : Colors.transparent,
        border: selected
            ? null
            : Border.all(color: DzColors.border, width: 2),
      ),
      child: selected
          ? const Icon(Icons.check, size: 14, color: DzColors.onAccent)
          : null,
    );
  }
}

/// Play/pause circle used on Sound Selection and on the Add/Edit sound row.
/// 48 dp hit area around a 44 (row) or 36 (form) visual circle.
class DzPreviewButton extends StatelessWidget {
  const DzPreviewButton({
    super.key,
    required this.playing,
    required this.onPressed,
    this.highlighted = true,
    this.size = 44,
  });

  final bool playing;
  final bool highlighted;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final active = highlighted || playing;
    return InkResponse(
      onTap: onPressed,
      radius: size / 2 + 6,
      child: SizedBox(
        width: size < 48 ? 48 : size,
        height: size < 48 ? 48 : size,
        child: Center(
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? DzColors.accent : DzColors.elevated,
              border: playing
                  ? Border.all(
                      color: DzColors.tint(DzColors.card, DzColors.accent, 0.5),
                      width: 3)
                  : null,
            ),
            child: Icon(
              playing ? Icons.pause : Icons.play_arrow,
              size: size * 0.55,
              color: active ? DzColors.onAccent : DzColors.text,
            ),
          ),
        ),
      ),
    );
  }
}
