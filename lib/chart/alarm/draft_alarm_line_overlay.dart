import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../screens/common/dz_theme.dart';
import '../contracts/chart_contracts.dart';
import 'alarm_chart_math.dart';

/// Draggable draft alarm line (zOrder 200).
///
/// Spawns at [price]; stays locked to that price across pan/zoom.
class DraftAlarmLineOverlay extends ChartOverlay {
  DraftAlarmLineOverlay({
    required double price,
    required this.symbol,
    required this.onPriceChanged,
    this.lastPrice,
  }) : _price = price;

  final String symbol;
  final ValueChanged<double> onPriceChanged;
  double? lastPrice;

  double _price;
  double get price => _price;

  set price(double v) {
    if (v == _price) return;
    _price = v;
    notifyListeners();
  }

  @override
  int get zOrder => 200;

  static final _linePaint = Paint()
    ..color = ChartColors.alarm
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke;

  static final _tagBg = Paint()
    ..color = ChartColors.alarm
    ..style = PaintingStyle.fill;

  static const _tagStyle = TextStyle(
    color: ChartColors.lastPriceText,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const _subStyle = TextStyle(
    color: DzColors.text2,
    fontSize: 9,
    fontWeight: FontWeight.w500,
  );

  @override
  void paint(Canvas canvas, ChartCoordinateMapper map) {
    final plot = map.plotRect;
    if (plot.width <= 0) return;
    final y = map.priceToY(_price);
    if (y < plot.top - 30 || y > plot.bottom + 30) return;

    canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), _linePaint);

    final prec = map.pricePrecision;
    final text = _price.toStringAsFixed(prec);
    final tp = TextPainter(
      text: TextSpan(
        children: [
          const TextSpan(
            text: '🔔 ',
            style: TextStyle(fontSize: 10, color: ChartColors.lastPriceText),
          ),
          TextSpan(text: text, style: _tagStyle),
        ],
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const padH = 8.0;
    const padV = 4.0;
    final tagW = tp.width + padH * 2;
    final tagH = tp.height + padV * 2;
    final tagLeft = plot.right - tagW - 2;
    final tagTop = y - tagH / 2;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(tagLeft, tagTop, tagW, tagH),
      const Radius.circular(6),
    );
    canvas.drawRRect(rrect, _tagBg);
    tp.paint(canvas, Offset(tagLeft + padH, tagTop + padV));

    // Optional distance subtitle.
    final lp = lastPrice;
    if (lp != null && lp > 0) {
      final dist = AlarmChartMath.distanceLabel(_price, lp, prec);
      final sp = TextPainter(
        text: TextSpan(text: dist, style: _subStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      sp.paint(canvas, Offset(tagLeft, tagTop + tagH + 2));
    }
  }

  @override
  bool hitTest(Offset position, ChartCoordinateMapper map) {
    final plot = map.plotRect;
    // Whole tag on the right + horizontal band.
    final y = map.priceToY(_price);
    if (AlarmChartMath.hitsHorizontalLine(position.dy, y, hitSlop: 22)) {
      if (position.dx >= plot.left - 4 && position.dx <= plot.right + 80) {
        return true;
      }
    }
    // Tag area specifically.
    final tagRect = Rect.fromLTWH(plot.right - 90, y - 22, 90, 44);
    return tagRect.contains(position);
  }

  @override
  void onDragStart(Offset position, ChartCoordinateMapper map) {
    HapticFeedback.selectionClick();
  }

  @override
  void onDragUpdate(
    Offset position,
    Offset delta,
    ChartCoordinateMapper map,
  ) {
    final plot = map.plotRect;
    var y = position.dy;
    // Expand range when near edges.
    if (y < plot.top + 28 || y > plot.bottom - 28) {
      // Caller (feature) will call expandPriceRangeToInclude via onPriceChanged
      // side-channel — we just update price; the feature listens.
    }
    final raw = map.yToPrice(y);
    final rounded = AlarmChartMath.roundForSymbol(raw, symbol);
    final clamped = AlarmChartMath.clampPrice(
      rounded,
      map.visibleMinPrice,
      map.visibleMaxPrice,
    );
    if (clamped != _price) {
      _price = clamped;
      onPriceChanged(_price);
      notifyListeners();
    }
  }

  @override
  void onDragEnd(ChartCoordinateMapper map) {}
}
