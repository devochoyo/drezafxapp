import 'dart:async';
import 'package:flutter/material.dart';
import '../common/dz_theme.dart';
import '../common/dz_widgets.dart';
import '../common/format_utils.dart';
import '../common/pair_utils.dart';
import '../contracts/stage2_contracts.dart';

/// Designs 10 (history list) and 11 (empty). Shows ONLY what
/// [HistoryGateway.watchHistory] emits. Also has loading and error states.
class AlertHistoryScreen extends StatefulWidget {
  const AlertHistoryScreen({
    super.key,
    this.onOpenHome,
    this.onOpenChart,
    this.onOpenSettings,
  });

  final VoidCallback? onOpenHome;
  final VoidCallback? onOpenChart;
  final VoidCallback? onOpenSettings;

  @override
  State<AlertHistoryScreen> createState() => _AlertHistoryScreenState();
}

class _AlertHistoryScreenState extends State<AlertHistoryScreen> {
  HistoryGateway? _gateway;
  StreamSubscription<List<HistoryEntry>>? _sub;
  List<HistoryEntry>? _entries;
  Object? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_gateway == null) {
      _gateway = Stage2Services.of(context).history;
      _subscribe();
    }
  }

  void _subscribe() {
    _sub?.cancel();
    setState(() {
      _entries = null;
      _error = null;
    });
    _sub = _gateway!.watchHistory().listen(
      (list) {
        if (mounted) setState(() => _entries = list);
      },
      onError: (Object e) {
        if (mounted) setState(() => _error = e);
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    Widget body;
    if (_error != null) {
      body = _HistoryError(onRetry: _subscribe);
    } else if (entries == null) {
      body = const Center(
          child: CircularProgressIndicator(color: DzColors.accent));
    } else if (entries.isEmpty) {
      body = const _HistoryEmpty();
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        itemCount: entries.length,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: HistoryCard(entry: entries[i]),
        ),
      );
    }

    final count = entries?.length ?? 0;
    return Scaffold(
      backgroundColor: DzColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Alert History', style: DzText.screenTitle()),
                    if (_error == null && entries != null && count > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        count == 1
                            ? '1 triggered alert'
                            : '$count triggered alerts',
                        style: DzText.body(color: DzColors.text2)
                            .copyWith(fontSize: 15),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Expanded(child: body),
            DzBottomNav(
              currentIndex: 2,
              onHome: widget.onOpenHome,
              onChart: widget.onOpenChart,
              onSettings: widget.onOpenSettings,
            ),
          ],
        ),
      ),
    );
  }
}

/// One history row (design 10).
class HistoryCard extends StatelessWidget {
  const HistoryCard({super.key, required this.entry});
  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: DzColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: DzColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: DzColors.tint(DzColors.card, DzColors.accent, 0.2),
            ),
            child: Icon(e.isDone ? Icons.check : Icons.notifications_active,
                size: 22, color: e.isDone ? DzColors.accent : DzColors.warning),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(pairDisplay(e.pair),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DzText.pair().copyWith(fontSize: 20)),
                    ),
                    const SizedBox(width: 8),
                    _StatusPill(done: e.isDone),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  children: [
                    Text('Target ${formatPrice(e.targetPrice, e.pair)}',
                        style: DzText.body().copyWith(fontSize: 15)),
                    Container(
                        width: 4,
                        height: 4,
                        decoration: const BoxDecoration(
                            color: DzColors.text, shape: BoxShape.circle)),
                    Text('Triggered ${formatPrice(e.triggeredPrice, e.pair)}',
                        style: DzText.body().copyWith(fontSize: 15)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(e.category.label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DzText.caption(color: DzColors.accent)
                        .copyWith(fontSize: 12, letterSpacing: 0.3)),
                const SizedBox(height: 6),
                Text(
                  '${formatDateTimeShort(e.triggeredAt)}  •  ${e.category.label}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DzText.body(color: DzColors.text2)
                      .copyWith(fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.done});
  final bool done;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: DzColors.tint(
              DzColors.card, done ? DzColors.accent : DzColors.warning, 0.2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(done ? 'DONE' : 'RINGING',
            style: DzText.pill(done ? DzColors.accent : DzColors.warning)
                .copyWith(fontSize: 12)),
      );
}

/// Design 11.
class _HistoryEmpty extends StatelessWidget {
  const _HistoryEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 110,
              height: 110,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: DzColors.card,
                      shape: BoxShape.circle,
                      border: Border.all(color: DzColors.border),
                    ),
                    child: const Icon(Icons.schedule,
                        size: 44, color: DzColors.text2),
                  ),
                  Positioned(
                    right: 2,
                    top: 2,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: DzColors.bg,
                        shape: BoxShape.circle,
                        border: Border.all(color: DzColors.border),
                      ),
                      child: const Icon(Icons.check,
                          size: 14, color: DzColors.accent),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('No triggered alerts yet',
                textAlign: TextAlign.center,
                style: DzText.sheetTitle().copyWith(fontSize: 22)),
            const SizedBox(height: 8),
            Text('Alerts will appear here once\nyour price levels are reached.',
                textAlign: TextAlign.center,
                style: DzText.body(color: DzColors.text2)
                    .copyWith(fontSize: 15, height: 1.4)),
          ],
        ),
      ),
    );
  }
}

/// Error state (not in the designs; built from the same tokens).
class _HistoryError extends StatelessWidget {
  const _HistoryError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 44, color: DzColors.danger),
            const SizedBox(height: 16),
            Text('Could not load history',
                style: DzText.sheetTitle().copyWith(fontSize: 20)),
            const SizedBox(height: 8),
            Text('Something went wrong while reading your alert history.',
                textAlign: TextAlign.center,
                style: DzText.body(color: DzColors.text2)),
            const SizedBox(height: 20),
            SizedBox(
              width: 160,
              child: DzPrimaryButton(label: 'Try Again', onPressed: onRetry),
            ),
          ],
        ),
      ),
    );
  }
}
