import 'package:flutter/material.dart';
import '../contracts/screen_contracts.dart';
import 'dz_theme.dart';

/// Green primary button (52 h, radius 16, dark text). Disabled = 40 % opacity.
class DzPrimaryButton extends StatelessWidget {
  const DzPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.leading,
    this.loading = false,
    this.height = 52,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? leading;
  final bool loading;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: Material(
        color: DzColors.accent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onPressed : null,
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: DzColors.onAccent),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (leading != null) ...[
                          leading!,
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Text(label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DzText.button()),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Transparent button with a 1.5 px border and white text.
class DzSecondaryButton extends StatelessWidget {
  const DzSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.height = 52,
    this.background,
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background ?? Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: DzColors.border, width: 1.5),
          ),
          alignment: Alignment.center,
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DzText.button(color: DzColors.text)),
        ),
      ),
    );
  }
}

/// Round icon button (e.g. sheet close, settings gear). 48 dp hit area.
class DzCircleIconButton extends StatelessWidget {
  const DzCircleIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 40,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkResponse(
        onTap: onPressed,
        radius: 26,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: DzColors.elevated,
                shape: BoxShape.circle,
                border: Border.all(color: DzColors.border),
              ),
              child: Icon(icon, size: 20, color: DzColors.text2),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom navigation: Home | History | Settings (no other destinations).
/// History/Settings targets belong to AI 3; the Dashboard forwards callbacks.
class DzBottomNav extends StatelessWidget {
  const DzBottomNav({
    super.key,
    this.currentIndex = 0,
    this.onHistory,
    this.onSettings,
    this.onHome,
  });

  final int currentIndex;
  final VoidCallback? onHome;
  final VoidCallback? onHistory;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    final items = <_NavItem>[
      _NavItem('Home', Icons.home_outlined, onHome),
      _NavItem('History', Icons.history, onHistory),
      _NavItem('Settings', Icons.settings, onSettings),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: DzColors.bg2,
        border: Border(top: BorderSide(color: DzColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: items[i].onTap,
                    child: Stack(
                      alignment: Alignment.topCenter,
                      children: [
                        if (i == currentIndex)
                          Container(
                            width: 28,
                            height: 3,
                            decoration: BoxDecoration(
                              color: DzColors.accent,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(items[i].icon,
                                  size: 22,
                                  color: i == currentIndex
                                      ? DzColors.accent
                                      : DzColors.text2),
                              const SizedBox(height: 3),
                              Text(
                                items[i].label,
                                style: DzText.caption(
                                  color: i == currentIndex
                                      ? DzColors.accent
                                      : DzColors.text2,
                                  letterSpacing: 0,
                                ).copyWith(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon, this.onTap);
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
}

/// Opens a modal bottom sheet that re-provides [ScreenServices] inside it,
/// so sheets work regardless of where ScreenServices sits above the Navigator.
Future<T?> showDzModalSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  final services = ScreenServices.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withAlpha(171), // ~67 % scrim
    builder: (ctx) => ScreenServices(
      alerts: services.alerts,
      market: services.market,
      sounds: services.sounds,
      child: Builder(builder: builder),
    ),
  );
}

/// Bottom-sheet chrome: handle, title row, scrolling body, pinned footer.
/// Keyboard-aware (bottom inset). [bodyBuilder] MUST attach the given
/// ScrollController to its scrollable.
class DzSheet extends StatelessWidget {
  const DzSheet({
    super.key,
    required this.title,
    required this.bodyBuilder,
    required this.footer,
    this.subtitle,
    this.onClose,
    this.initialSize = 0.62,
    this.controller,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onClose; // null = no close button
  final Widget footer;
  final double initialSize;
  final DraggableScrollableController? controller;
  final Widget Function(ScrollController) bodyBuilder;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: DraggableScrollableSheet(
        controller: controller,
        expand: false,
        initialChildSize: initialSize,
        minChildSize: 0.4 < initialSize ? 0.4 : initialSize,
        maxChildSize: 0.94,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: DzColors.bg2,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: DzColors.border),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: DzColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 12, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DzText.sheetTitle()
                                      .copyWith(fontSize: 22)),
                              if (subtitle != null) ...[
                                const SizedBox(height: 4),
                                Text(subtitle!,
                                    style: DzText.body(color: DzColors.text2)),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (onClose != null)
                        DzCircleIconButton(
                          icon: Icons.close,
                          onPressed: onClose,
                          tooltip: 'Close',
                        ),
                    ],
                  ),
                ),
                Expanded(child: bodyBuilder(scrollController)),
                Container(
                  decoration: const BoxDecoration(
                    color: DzColors.bg2,
                    border: Border(top: BorderSide(color: DzColors.border)),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: SafeArea(top: false, child: footer),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
