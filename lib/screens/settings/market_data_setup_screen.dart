import 'package:flutter/material.dart';
import '../common/dz_theme.dart';
import '../common/dz_widgets.dart';
import '../contracts/screen_contracts.dart';
import '../contracts/stage2_contracts.dart';

/// Market-data setup (OANDA). The owner enters the OANDA account ID and API
/// token here. They are saved on this phone only and used by the background
/// monitoring service to open the live price stream.
class MarketDataSetupScreen extends StatefulWidget {
  const MarketDataSetupScreen({super.key});

  @override
  State<MarketDataSetupScreen> createState() => _MarketDataSetupScreenState();
}

class _MarketDataSetupScreenState extends State<MarketDataSetupScreen> {
  final _accountController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _live = false;
  bool _hasSaved = false;
  bool _loaded = false;
  bool _busy = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    Stage2Services.of(context).settings.watchMarketDataSetup().first.then((s) {
      if (!mounted) return;
      setState(() {
        _hasSaved = s.hasCredentials;
        _accountController.text = s.accountId;
        _live = s.live;
      });
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _accountController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Stage2Services.of(context).settings.saveMarketDataSetup(
            accountId: _accountController.text,
            token: _tokenController.text,
            live: _live,
          );
      if (!mounted) return;
      _tokenController.clear();
      setState(() => _hasSaved = true);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
        content: Text('Saved. Connecting to OANDA...'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Invalid argument(s): ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      await Stage2Services.of(context).settings.clearMarketDataSetup();
      if (!mounted) return;
      _accountController.clear();
      _tokenController.clear();
      setState(() {
        _hasSaved = false;
        _live = false;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not remove the credentials.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _decoration(String label, String hint) => InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: DzText.label(),
        hintStyle: DzText.label(color: DzColors.text2),
        filled: true,
        fillColor: DzColors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: DzColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: DzColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: DzColors.accent),
        ),
      );

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
                          'Status: connected to OANDA',
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
              'DrezaFx gets live prices from OANDA. You need an OANDA account '
              '(a free fxTrade Practice account works) and an API token: in '
              'your OANDA account go to "Manage API Access" and generate a '
              'personal access token. The account ID looks like '
              '101-001-1234567-001. They are stored only on this phone.',
              style: DzText.body(color: DzColors.text2).copyWith(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _accountController,
              style: DzText.body(),
              autocorrect: false,
              enableSuggestions: false,
              decoration: _decoration('Account ID', '101-001-1234567-001'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tokenController,
              style: DzText.body(),
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: _decoration('API token',
                  _hasSaved ? 'Saved. Leave empty to keep it' : 'Paste your token'),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _live,
              activeColor: DzColors.accent,
              title: Text('Live account', style: DzText.body()),
              subtitle: Text(
                  _live ? 'fxTrade live prices' : 'fxTrade Practice (demo) prices',
                  style: DzText.label()),
              onChanged: _busy ? null : (v) => setState(() => _live = v),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!, style: DzText.body(color: DzColors.danger)),
            ],
            const SizedBox(height: 12),
            DzPrimaryButton(
              label: 'SAVE AND CONNECT',
              loading: _busy,
              onPressed: _busy ? null : _save,
            ),
            if (_hasSaved) ...[
              const SizedBox(height: 10),
              DzSecondaryButton(
                label: 'REMOVE CREDENTIALS',
                onPressed: _busy ? null : _remove,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
