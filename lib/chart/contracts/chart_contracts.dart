import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../screens/common/dz_theme.dart';

// ===========================================================================
// DATA
// ===========================================================================

/// One OHLC candle. [time] is the candle OPEN time in epoch SECONDS (UTC).
@immutable
class Candle {
  const Candle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
  });

  final int time;
  final double open;
  final double high;
  final double low;
  final double close;

  bool get isBullish => close >= open;

  /// Applies a new price to this (still forming) candle.
  Candle withPrice(double price) => Candle(
        time: time,
        open: open,
        high: price > high ? price : high,
        low: price < low ? price : low,
        close: price,
      );

  @override
  bool operator ==(Object other) =>
      other is Candle &&
      other.time == time &&
      other.open == open &&
      other.high == high &&
      other.low == low &&
      other.close == close;

  @override
  int get hashCode => Object.hash(time, open, high, low, close);

  @override
  String toString() => 'Candle($time O$open H$high L$low C$close)';
}

enum ChartTimeframe {
  m1('M1', 60),
  m5('M5', 300),
  m15('M15', 900),
  h1('H1', 3600),
  h2('H2', 7200),
  h4('H4', 14400),
  d1('D1', 86400),
  w1('W1', 604800);

  const ChartTimeframe(this.label, this.seconds);

  final String label;
  final int seconds;

  /// The app default.
  static const ChartTimeframe defaultTimeframe = ChartTimeframe.h1;

  /// Deriv offers no weekly candles: W1 is built from D1 candles.
  bool get isDerived => this == ChartTimeframe.w1;

  /// Granularity (seconds) to request from Deriv.
  int get sourceGranularity => isDerived ? 86400 : seconds;

  /// Start (epoch seconds, UTC) of the candle bucket containing [epoch].
  /// Weekly buckets start on Monday 00:00 UTC (the Unix epoch is a Thursday).
  int bucketStart(int epoch) {
    if (this == ChartTimeframe.w1) {
      const mondayOffset = 4 * 86400;
      return ((epoch - mondayOffset) ~/ seconds) * seconds + mondayOffset;
    }
    return (epoch ~/ seconds) * seconds;
  }
}

enum ChartLoadState { idle, loading, ready, empty, error }

enum ChartLinkState { connecting, live, reconnecting, offline }

class ChartDataException implements Exception {
  const ChartDataException(this.message);
  final String message;
  @override
  String toString() => 'ChartDataException: $message';
}

/// Candle source. Symbols are plain 6-letter strings such as "GBPJPY".
/// Implementations never fabricate data.
abstract class ChartDataService {
  /// Most recent [count] candles, oldest first (may include the forming one).
  Future<List<Candle>> loadInitial(
    String symbol,
    ChartTimeframe timeframe, {
    int count = 500,
  });

  /// Up to [count] candles that closed strictly BEFORE [beforeTime]
  /// (epoch seconds), oldest first. Empty list = no more history.
  Future<List<Candle>> loadOlder(
    String symbol,
    ChartTimeframe timeframe, {
    required int beforeTime,
    int count = 500,
  });

  /// Live updates of the forming candle in the REQUESTED timeframe.
  /// Emits a candle with the same `time` as the previous one (update) or a
  /// newer `time` (a new candle started). For W1 the service aggregates.
  Stream<Candle> watchLive(String symbol, ChartTimeframe timeframe);

  /// Connection state of the live feed.
  Stream<ChartLinkState> get linkState;

  /// Close of the previous trading day (for the daily change in the header),
  /// or null if unknown.
  Future<double?> previousDailyClose(String symbol);

  Future<void> dispose();
}

// ===========================================================================
// COORDINATES  (all coordinates are in the local space of ChartView)
// ===========================================================================

abstract class ChartCoordinateMapper {
  /// The candle area, excluding the price axis (right) and time axis (bottom).
  Rect get plotRect;

  /// Decimals of the current symbol (3 JPY pairs, 2 XAU, else 5).
  int get pricePrecision;

  double get visibleMinPrice;
  double get visibleMaxPrice;

  double priceToY(double price);
  double yToPrice(double y);

  /// Works for ANY epoch time, including times in the future beyond the last
  /// candle (extrapolated by timeframe length) and times in market-closed
  /// gaps (interpolated between neighbouring candles). Weekend gaps are
  /// compressed (candle-index space), like TradingView.
  double timeToX(int epochSeconds);
  int xToTime(double x);

  /// Loaded candles, oldest first (read-only, do not mutate).
  List<Candle> get candles;

  /// Candle whose slot contains [x], or null.
  Candle? candleAtX(double x);
}

// ===========================================================================
// OVERLAYS  (lines/shapes painted on top of the candles)
// ===========================================================================

/// A layer painted inside the chart plot. Overlays are painted in ascending
/// [zOrder]. Call `notifyListeners()` to request a repaint of the overlay
/// layer only (never rebuild the widget tree for drags).
///
/// GESTURE ARBITRATION (implemented by ChartView):
///  * On pointer-down the view asks overlays, highest [zOrder] first,
///    `hitTest(...)`. The first that returns true owns the gesture: it gets
///    onDragStart/Update/End and the chart does NOT pan.
///  * If an overlay has [capturesAllPointers] == true (e.g. a drawing tool is
///    armed), it owns every gesture inside the plot, before any hit-test.
///  * A tap with no drag is delivered to [onTap] of the hit overlay.
///  * If no overlay claims the pointer the chart pans/zooms.
abstract class ChartOverlay extends ChangeNotifier {
  int get zOrder;

  bool get capturesAllPointers => false;

  void paint(Canvas canvas, ChartCoordinateMapper map);

  bool hitTest(Offset position, ChartCoordinateMapper map);

  void onTap(Offset position, ChartCoordinateMapper map) {}
  void onDragStart(Offset position, ChartCoordinateMapper map) {}
  void onDragUpdate(Offset position, Offset delta, ChartCoordinateMapper map) {}
  void onDragEnd(ChartCoordinateMapper map) {}
}

// ===========================================================================
// CONTROLLER  (implemented by Batch 1; used by Batches 2, 3, 4)
// ===========================================================================

abstract class ChartController extends ChangeNotifier {
  String get symbol;
  ChartTimeframe get timeframe;

  ChartLoadState get loadState;
  String? get errorMessage;
  ChartLinkState get linkState;

  /// Oldest first. Includes the forming candle as the last element.
  List<Candle> get candles;
  Candle? get lastCandle;
  double? get lastPrice;

  /// Last price minus previous daily close (null if unknown) and percent.
  double? get dailyChange;
  double? get dailyChangePercent;

  /// Non-null while the crosshair is visible: the candle under it.
  Candle? get crosshairCandle;

  ChartCoordinateMapper get mapper;

  /// Price at the vertical centre of the plot (where a new alarm spawns).
  double? get centerPrice;

  /// True when the newest candle is in view (auto-follow is on).
  bool get isAtLiveEdge;

  /// True when the user manually scaled the price axis (auto-fit is off).
  bool get isPriceScaleManual;

  /// Fires on every pan/zoom/scale/size change. Overlay painters and tag
  /// widgets listen to this instead of the heavier ChangeNotifier above.
  Listenable get viewportChanges;

  Future<void> setSymbol(String symbol);
  Future<void> setTimeframe(ChartTimeframe timeframe);
  Future<void> reload();

  void scrollToLatest({bool animate = true});

  /// Re-enables automatic price-range fitting.
  void resetPriceScale();

  void addOverlay(ChartOverlay overlay);
  void removeOverlay(ChartOverlay overlay);

  /// Temporarily widens the visible price range so [price] is visible
  /// (used while dragging a line to the top/bottom edge).
  void expandPriceRangeToInclude(double price);
}

// ===========================================================================
// FEATURE PLUG-INS  (implemented by Batches 3 and 4, hosted by Batch 2)
// ===========================================================================

enum ChartToolbarPlacement { bottomBar, topBar }

@immutable
class ChartToolbarItem {
  const ChartToolbarItem({
    required this.id,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.placement = ChartToolbarPlacement.bottomBar,
    this.active,
    this.enabled,
    this.order = 100,
  });

  final String id;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final ChartToolbarPlacement placement;

  /// Highlights the button while true (e.g. a tool is armed).
  final ValueListenable<bool>? active;

  /// Greys the button out while false (e.g. nothing to undo). Null = enabled.
  final ValueListenable<bool>? enabled;

  /// Lower = further left.
  final int order;
}

/// A self-contained chart feature. The ChartScreen listens to it (it is a
/// ChangeNotifier) and re-reads [toolbarItems] / [buildFloating] on change.
abstract class ChartFeature extends ChangeNotifier {
  String get id;

  /// Called once when the ChartScreen starts. [context] belongs to the
  /// ChartScreen: use it ONLY to look up `ScreenServices.of(context)` and
  /// keep the gateways. Never store the context itself.
  void attach(ChartController controller, BuildContext context);

  /// Remove overlays, cancel subscriptions. Always safe to call twice.
  void detach();

  List<ChartToolbarItem> toolbarItems(BuildContext context);

  /// Floating widgets stacked over the chart area. The screen puts them in a
  /// `Stack` that fills the chart; each widget positions itself with
  /// `Align` / `Positioned`. Return an empty list when nothing is visible.
  List<Widget> buildFloating(BuildContext context);
}

// ===========================================================================
// COLOURS
// ===========================================================================

class ChartColors {
  ChartColors._();

  static const Color background = DzColors.bg;
  static const Color grid = Color(0x14FFFFFF); // white ~8 %
  static const Color axisText = DzColors.text2;
  static const Color bull = DzColors.accent;
  static const Color bear = DzColors.danger;
  static const Color lastPrice = DzColors.warning;
  static const Color lastPriceText = Color(0xFF1A1300);
  static const Color crosshair = Color(0x99FFFFFF);
  static const Color crosshairTag = DzColors.elevated;
  static const Color alarm = DzColors.warning;
}