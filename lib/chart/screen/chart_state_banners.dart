import 'package:flutter/material.dart';

import '../../screens/common/dz_theme.dart';
import '../contracts/chart_contracts.dart';

/// Thin top progress bar while loading with cached candles still visible.
class ChartLoadingBar extends StatelessWidget {
  const ChartLoadingBar({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return const LinearProgressIndicator(
      minHeight: 2,
      backgroundColor: Colors.transparent,
      color: DzColors.accent,
    );
  }
}

/// Centred spinner for the first empty load.
class ChartEmptySpinner extends StatelessWidget {
  const ChartEmptySpinner({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: DzColors.accent,
        ),
      ),
    );
  }
}

/// Error card with Retry.
class ChartErrorBanner extends StatelessWidget {
  const ChartErrorBanner({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: DzText.body(color: DzColors.text2),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: DzColors.accent),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small status pills: Reconnecting / Offline / Market closed.
class ChartLinkPill extends StatelessWidget {
  const ChartLinkPill({
    super.key,
    required this.linkState,
    this.marketClosed = false,
  });

  final ChartLinkState linkState;
  final bool marketClosed;

  @override
  Widget build(BuildContext context) {
    String? label;
    Color color = DzColors.warning;

    if (marketClosed) {
      label = 'Market closed';
      color = DzColors.text2;
    } else if (linkState == ChartLinkState.reconnecting) {
      label = 'Reconnecting…';
    } else if (linkState == ChartLinkState.offline ||
        linkState == ChartLinkState.connecting) {
      label = linkState == ChartLinkState.connecting ? 'Connecting…' : 'Offline';
    }

    if (label == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: DzColors.elevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DzColors.border),
      ),
      child: Text(
        label,
        style: DzText.caption(color: color).copyWith(fontSize: 11),
      ),
    );
  }
}

/// Approximate forex weekend: Friday 22:00 UTC → Sunday 22:00 UTC.
bool isApproxMarketClosed(DateTime utcNow) {
  final weekday = utcNow.weekday; // Mon=1 … Sun=7
  final minutes = utcNow.hour * 60 + utcNow.minute;
  const closeFri = 22 * 60;
  if (weekday == DateTime.friday && minutes >= closeFri) return true;
  if (weekday == DateTime.saturday) return true;
  if (weekday == DateTime.sunday && minutes < closeFri) return true;
  return false;
}
