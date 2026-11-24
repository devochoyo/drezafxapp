import 'package:flutter/material.dart';
import '../common/dz_theme.dart';
import '../common/dz_widgets.dart';
import '../contracts/screen_contracts.dart';

/// Market data status. Prices come from Deriv's public WebSocket feed, which
/// needs no account, token or setup, so this screen only shows the connection
/// status and lets the owner reconnect.
class MarketDataSetupScreen extends StatelessWidget {
  const MarketDataSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final market = ScreenServices.of(context).market;
    return Scaffold(
      backgroundColor: DzColors.bg,
      appBar: AppBar(
        backgroundColor: DzColors.bg,
        elevation: 0,
        title: Text('Market data', style: DzText.sheetTitle()),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            StreamBuilder<MarketSnapshot>(
              stream: market.snapshots,
              builder: (context, snap) {
                final s = snap.data;
                final text = s == null
                    ? 'Status: —'
                    : switch (s.status) {
                        MarketConnectionStatus.connected =>
                          'Status: connected to Deriv',
                        MarketConnectionStatus.connecting =>
                          'Status: connecting...',
                        MarketConnectionStatus.disconnected =>
                          'Status: disconnected. ${s.errorMessage ?? ''}',
                        MarketConnectionStatus.error =>
                          'Status: error. ${s.errorMessage ?? ''}',
                      };
                final ok = s?.status == MarketConnectionStatus.connected;
                return Text(text,
                    style: DzText.body(
                        color: ok ? DzColors.accent : DzColors.warning));
              },
            ),
            const SizedBox(height: 12),
            Text(
              'DrezaFx gets live Forex prices from Deriv\'s public price feed. '
              'No account, API token or setup is needed. The feed is closed '
              'at weekends, so prices pause until the market reopens.',
              style: DzText.body(color: DzColors.text2)
                  .copyWith(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 16),
            DzPrimaryButton(
              label: 'RECONNECT',
              onPressed: market.retry,
            ),
          ],
        ),
      ),
    );
  }
}
