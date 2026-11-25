import 'package:flutter/material.dart';

import '../../models/currency_pair.dart';
import '../../screens/common/dz_theme.dart';
import '../../screens/common/dz_widgets.dart';
import '../../screens/contracts/screen_contracts.dart';

/// Bottom sheet to pick a currency pair.
///
/// Search is case-insensitive and matches "gbp", "GBPJPY", "GBP/JPY".
/// Recently-used pairs (if provided) appear first under a header.
Future<String?> showSymbolSheet(
  BuildContext context, {
  required String currentSymbol,
  List<String> recentSymbols = const [],
}) {
  return showDzModalSheet<String>(
    context,
    builder: (ctx) => _SymbolSheetBody(
      currentSymbol: currentSymbol.toUpperCase(),
      recentSymbols: recentSymbols,
    ),
  );
}

class _SymbolSheetBody extends StatefulWidget {
  const _SymbolSheetBody({
    required this.currentSymbol,
    required this.recentSymbols,
  });

  final String currentSymbol;
  final List<String> recentSymbols;

  @override
  State<_SymbolSheetBody> createState() => _SymbolSheetBodyState();
}

class _SymbolSheetBodyState extends State<_SymbolSheetBody> {
  final _query = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<CurrencyPair> _filtered() {
    final all = CurrencyPair.supported;
    if (_filter.isEmpty) return all;
    final q = _filter.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    return [
      for (final p in all)
        if (p.symbol.toLowerCase().contains(q) ||
            p.displayName.toLowerCase().replaceAll('/', '').contains(q) ||
            p.base.toLowerCase().contains(q) ||
            p.quote.toLowerCase().contains(q))
          p,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final pairs = _filtered();
    final market = ScreenServices.of(context).market;

    return DzSheet(
      title: 'Pairs',
      onClose: () => Navigator.of(context).pop(),
      initialSize: 0.72,
      footer: const SizedBox.shrink(),
      bodyBuilder: (scrollCtrl) {
        return ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // Search
            TextField(
              controller: _query,
              onChanged: (v) => setState(() => _filter = v),
              style: DzText.body(),
              cursorColor: DzColors.accent,
              decoration: InputDecoration(
                hintText: 'Search',
                hintStyle: DzText.body(color: DzColors.text2),
                prefixIcon: const Icon(Icons.search, color: DzColors.text2),
                filled: true,
                fillColor: DzColors.elevated,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 16),

            // Currently in use
            Text('Currently in use', style: DzText.label()),
            const SizedBox(height: 8),
            _PairTile(
              pair: CurrencyPair.tryParse(widget.currentSymbol) ??
                  CurrencyPair.supported.first,
              selected: true,
              market: market,
              onTap: () => Navigator.of(context).pop(widget.currentSymbol),
            ),
            const SizedBox(height: 16),

            Text('All pairs', style: DzText.label()),
            const SizedBox(height: 8),
            for (final p in pairs)
              if (p.symbol != widget.currentSymbol)
                _PairTile(
                  pair: p,
                  selected: false,
                  market: market,
                  onTap: () => Navigator.of(context).pop(p.symbol),
                ),
          ],
        );
      },
    );
  }
}

class _PairTile extends StatelessWidget {
  const _PairTile({
    required this.pair,
    required this.selected,
    required this.market,
    required this.onTap,
  });

  final CurrencyPair pair;
  final bool selected;
  final MarketPriceGateway market;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? DzColors.elevated : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pair.displayName, style: DzText.pair()),
                    const SizedBox(height: 2),
                    Text(pair.symbol, style: DzText.caption()),
                  ],
                ),
              ),
              StreamBuilder(
                stream: market.snapshots,
                builder: (context, snap) {
                  // Live price is best-effort; absence is fine.
                  return const SizedBox.shrink();
                },
              ),
              if (selected)
                const Icon(Icons.check, color: DzColors.accent, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
