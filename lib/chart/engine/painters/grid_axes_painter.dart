import 'package:flutter/material.dart' hide Viewport;

import '../../contracts/chart_contracts.dart';
import '../mapper_impl.dart';
import '../price_scale.dart';
import '../time_scale.dart';
import '../viewport.dart';

/// Static layer: background, grid lines, price axis labels, time axis labels.
class GridAxesPainter extends CustomPainter {
  GridAxesPainter({
    required this.mapper,
    required this.viewport,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final MapperImpl mapper;
  final Viewport viewport;
  ChartTimeframe get timeframe => mapper.timeframe;

  static final _gridPaint = Paint()
    ..color = ChartColors.grid
    ..strokeWidth = 1
    ..style = PaintingStyle.stroke;

  static final _axisTextStyle = TextStyle(
    color: ChartColors.axisText,
    fontSize: 10,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  @override
  void paint(Canvas canvas, Size size) {
    final plot = mapper.plotRect;
    if (plot.width <= 0 || plot.height <= 0) return;

    // Background already painted by parent; draw grid only.
    _drawPriceGrid(canvas, plot);
    _drawTimeGrid(canvas, plot);
    _drawPriceLabels(canvas, plot, size);
    _drawTimeLabels(canvas, plot, size);
  }

  void _drawPriceGrid(Canvas canvas, Rect plot) {
    final steps = PriceScale.niceSteps(
      viewport.minPrice,
      viewport.maxPrice,
      targetCount: 7,
    );
    for (final p in steps) {
      final y = mapper.priceToY(p);
      if (y < plot.top || y > plot.bottom) continue;
      canvas.drawLine(
        Offset(plot.left, y),
        Offset(plot.right, y),
        _gridPaint,
      );
    }
  }

  void _drawTimeGrid(Canvas canvas, Rect plot) {
    final candles = mapper.candles;
    if (candles.isEmpty) return;
    final first = viewport.startIndex.floor().clamp(0, candles.length - 1);
    final last = viewport.endIndex.ceil().clamp(0, candles.length - 1);
    if (first > last) return;

    final slotW = plot.width / viewport.visibleCount;
    final times = TimeScale.selectLabelTimes(
      candles: candles,
      firstIndex: first,
      lastIndex: last,
      candlePixelWidth: slotW,
      timeframe: timeframe,
    );
    for (final t in times) {
      final x = mapper.timeToX(t);
      if (x < plot.left || x > plot.right) continue;
      canvas.drawLine(
        Offset(x, plot.top),
        Offset(x, plot.bottom),
        _gridPaint,
      );
    }
  }

  void _drawPriceLabels(Canvas canvas, Rect plot, Size size) {
    final steps = PriceScale.niceSteps(
      viewport.minPrice,
      viewport.maxPrice,
      targetCount: 7,
    );
    final prec = mapper.pricePrecision;
    for (final p in steps) {
      final y = mapper.priceToY(p);
      if (y < plot.top - 4 || y > plot.bottom + 4) continue;
      final tp = TextPainter(
        text: TextSpan(
          text: p.toStringAsFixed(prec),
          style: _axisTextStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = plot.right + 6;
      tp.paint(canvas, Offset(x, y - tp.height / 2));
    }
  }

  void _drawTimeLabels(Canvas canvas, Rect plot, Size size) {
    final candles = mapper.candles;
    if (candles.isEmpty) return;
    final first = viewport.startIndex.floor().clamp(0, candles.length - 1);
    final last = viewport.endIndex.ceil().clamp(0, candles.length - 1);
    if (first > last) return;

    final slotW = plot.width / viewport.visibleCount;
    final times = TimeScale.selectLabelTimes(
      candles: candles,
      firstIndex: first,
      lastIndex: last,
      candlePixelWidth: slotW,
      timeframe: timeframe,
    );
    for (final t in times) {
      final x = mapper.timeToX(t);
      if (x < plot.left - 20 || x > plot.right + 20) continue;
      final label = TimeScale.formatLabel(t, timeframe);
      final tp = TextPainter(
        text: TextSpan(text: label, style: _axisTextStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(x - tp.width / 2, plot.bottom + 4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant GridAxesPainter old) => true;
}
