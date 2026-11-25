import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/currency_pair.dart';
import '../../screens/common/dz_theme.dart';
import '../../screens/common/dz_widgets.dart';
import '../chart_features.dart';
import '../contracts/chart_contracts.dart';
import '../data/deriv_chart_data_service.dart';
import '../engine/chart_controller_impl.dart';
import '../engine/chart_view.dart';
import 'chart_header.dart';
import 'chart_prefs.dart';
import 'chart_state_banners.dart';
import 'chart_toolbar.dart';
import 'orientation_controller.dart';
import 'symbol_sheet.dart';
import 'timeframe_sheet.dart';

/// Full Chart tab: header, native chart, toolbar, sheets, landscape.
class ChartScreen extends StatefulWidget {
  const ChartScreen({
    super.key,
    this.onOpenHome,
    this.onOpenHistory,
    this.onOpenSettings,
    this.initialSymbol,
  });

  final VoidCallback? onOpenHome;
  final VoidCallback? onOpenHistory;
  final VoidCallback? onOpenSettings;
  final String? initialSymbol;

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  late final DerivChartDataService _dataService;
  late final ChartControllerImpl _controller;
  late final ChartPrefs _prefs;
  late final OrientationController _orientation;
  late final List<ChartFeature> _features;

  final Listenable _featureListenable = _MergedListenable([]);

  bool _ready = false;
  bool _hideBottomNav = false;

  @override
  void initState() {
    super.initState();
    _dataService = DerivChartDataService();
    _prefs = ChartPrefs();
    _orientation = OrientationController();
    _features = createChartFeatures();

    // Temporary controller; real symbol/tf restored async.
    final defaultSymbol = CurrencyPair.supported.isNotEmpty
        ? CurrencyPair.supported.first.symbol
        : 'EURUSD';
    _controller = ChartControllerImpl(
      data: _dataService,
      symbol: widget.initialSymbol ?? defaultSymbol,
      timeframe: ChartTimeframe.defaultTimeframe,
    );

    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final defaultSymbol = CurrencyPair.supported.isNotEmpty
        ? CurrencyPair.supported.first.symbol
        : 'EURUSD';
    final loaded = await _prefs.load(defaultSymbol: defaultSymbol);

    if (!mounted) return;

    await _controller.setSymbol(widget.initialSymbol ?? loaded.symbol);
    if (!mounted) return;
    await _controller.setTimeframe(loaded.timeframe);
    if (!mounted) return;

    // Attach features after the first frame so ScreenServices is available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final f in _features) {
        f.attach(_controller, context);
      }
      (_featureListenable as _MergedListenable).replace(_features);
      setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    for (final f in _features) {
      f.detach();
    }
    _orientation.restore();
    _controller.dispose();
    super.dispose();
  }

  // ---- actions ----------------------------------------------------------

  Future<void> _pickSymbol() async {
    final chosen = await showSymbolSheet(
      context,
      currentSymbol: _controller.symbol,
    );
    if (chosen == null || !mounted) return;
    if (chosen == _controller.symbol) return;
    await _controller.setSymbol(chosen);
    await _prefs.save(_controller.symbol, _controller.timeframe);
  }

  Future<void> _pickTimeframe() async {
    final chosen = await showTimeframeSheet(
      context,
      current: _controller.timeframe,
    );
    if (chosen == null || !mounted) return;
    if (chosen == _controller.timeframe) return;
    await _controller.setTimeframe(chosen);
    await _prefs.save(_controller.symbol, _controller.timeframe);
  }

  Future<void> _toggleOrientation() async {
    await _orientation.toggle();
    setState(() => _hideBottomNav = _orientation.isLandscape);
  }

  // ---- build ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_orientation.isLandscape,
      onPopInvoked: (didPop) async {
        if (!didPop && _orientation.isLandscape) {
          await _orientation.enterPortrait();
          if (mounted) setState(() => _hideBottomNav = false);
        }
      },
      child: Scaffold(
        backgroundColor: DzColors.bg,
        body: SafeArea(
          bottom: !_hideBottomNav,
          child: !_ready
              ? const ChartEmptySpinner()
              : OrientationBuilder(
                  builder: (context, orientation) {
                    final landscape =
                        orientation == Orientation.landscape ||
                            _orientation.isLandscape;
                    return Column(
                      children: [
                        // Header
                        ListenableBuilder(
                          listenable: _featureListenable,
                          builder: (_, __) => ChartHeader(
                          controller: _controller,
                          topBarItems: _topBarItems(),
                          onPairTap: _pickSymbol,
                          trailing: landscape
                              ? [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.stay_current_portrait_outlined,
                                      size: 20,
                                    ),
                                    color: DzColors.text2,
                                    tooltip: 'Portrait',
                                    onPressed: _toggleOrientation,
                                  ),
                                ]
                              : null,
                        ),
                        ),
                        // Link / market-closed pill
                        _StatusRow(controller: _controller),
                        // Loading bar
                        ListenableBuilder(
                          listenable: _controller,
                          builder: (_, __) => ChartLoadingBar(
                            visible: _controller.loadState ==
                                    ChartLoadState.loading &&
                                _controller.candles.isNotEmpty,
                          ),
                        ),
                        // Chart plot
                        Expanded(
                          child: Stack(
                            children: [
                              ChartView(controller: _controller),
                              // Empty / error overlays
                              ListenableBuilder(
                                listenable: _controller,
                                builder: (_, __) {
                                  final s = _controller.loadState;
                                  if (s == ChartLoadState.loading &&
                                      _controller.candles.isEmpty) {
                                    return const ChartEmptySpinner();
                                  }
                                  if (s == ChartLoadState.error) {
                                    return ChartErrorBanner(
                                      message: _controller.errorMessage ??
                                          'Failed to load chart',
                                      onRetry: () => _controller.reload(),
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),
                              // In-plot buttons (bottom-right)
                              _InPlotButtons(
                                controller: _controller,
                                landscape: landscape,
                                onToggleOrientation: _toggleOrientation,
                              ),
                              // Feature floating widgets
                              ListenableBuilder(
                                listenable: _featureListenable,
                                builder: (_, __) => Stack(
                                  fit: StackFit.expand,
                                  children: _floatingWidgets(),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Toolbar
                        ListenableBuilder(
                          listenable: Listenable.merge([
                            _controller,
                            _featureListenable,
                          ]),
                          builder: (_, __) => ChartToolbar(
                            symbol: _controller.symbol,
                            timeframe: _controller.timeframe,
                            items: _allToolbarItems(),
                            onPairTap: _pickSymbol,
                            onTimeframeTap: _pickTimeframe,
                          ),
                        ),
                        // App bottom nav (hidden in landscape)
                        if (!_hideBottomNav)
                          DzBottomNav(
                            currentIndex: 1,
                            onHome: widget.onOpenHome,
                            onHistory: widget.onOpenHistory,
                            onSettings: widget.onOpenSettings,
                          ),
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }

  List<ChartToolbarItem> _allToolbarItems() {
    final items = <ChartToolbarItem>[];
    for (final f in _features) {
      items.addAll(f.toolbarItems(context));
    }
    return items;
  }

  List<ChartToolbarItem> _topBarItems() {
    final items = _allToolbarItems()
        .where((i) => i.placement == ChartToolbarPlacement.topBar)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return items;
  }

  List<Widget> _floatingWidgets() {
    final out = <Widget>[];
    for (final f in _features) {
      out.addAll(f.buildFloating(context));
    }
    return out;
  }
}

// ---------------------------------------------------------------------------

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.controller});
  final ChartControllerImpl controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (_, __) {
        final last = controller.lastCandle;
        final closed = last != null &&
            isApproxMarketClosed(DateTime.now().toUtc()) &&
            DateTime.now()
                    .toUtc()
                    .difference(
                      DateTime.fromMillisecondsSinceEpoch(
                        last.time * 1000,
                        isUtc: true,
                      ),
                    )
                    .inHours >
                6;
        return Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ChartLinkPill(
              linkState: controller.linkState,
              marketClosed: closed,
            ),
          ),
        );
      },
    );
  }
}

class _InPlotButtons extends StatelessWidget {
  const _InPlotButtons({
    required this.controller,
    required this.landscape,
    required this.onToggleOrientation,
  });

  final ChartControllerImpl controller;
  final bool landscape;
  final VoidCallback onToggleOrientation;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller.viewportChanges,
      builder: (_, __) {
        final showLatest = !controller.isAtLiveEdge ||
            controller.isPriceScaleManual;
        return Positioned(
          right: controller.mapper.plotRect.width > 0
              ? (MediaQuery.sizeOf(context).width -
                      controller.mapper.plotRect.right) +
                  8
              : 76,
          bottom: 28,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showLatest)
                _RoundBtn(
                  icon: Icons.keyboard_double_arrow_right,
                  color: DzColors.accent,
                  onTap: () {
                    controller.scrollToLatest();
                    controller.resetPriceScale();
                  },
                ),
              if (!landscape) ...[
                const SizedBox(height: 8),
                _RoundBtn(
                  icon: Icons.crop_landscape_outlined,
                  color: DzColors.text2,
                  outlined: true,
                  onTap: onToggleOrientation,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    this.outlined = false,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DzColors.elevated,
      shape: CircleBorder(
        side: outlined
            ? BorderSide(color: color.withAlpha(180))
            : BorderSide.none,
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}

/// Merges multiple [Listenable]s (the features) into one.
class _MergedListenable extends ChangeNotifier {
  _MergedListenable(List<Listenable> items) {
    replace(items);
  }

  final List<Listenable> _items = [];

  void replace(List<Listenable> items) {
    for (final i in _items) {
      i.removeListener(notifyListeners);
    }
    _items
      ..clear()
      ..addAll(items);
    for (final i in _items) {
      i.addListener(notifyListeners);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    for (final i in _items) {
      i.removeListener(notifyListeners);
    }
    super.dispose();
  }
}
