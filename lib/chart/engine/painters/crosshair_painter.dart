import 'dart:ui';

import 'package:flutter/material.dart';

import '../../contracts/chart_contracts.dart';
import '../mapper_impl.dart';
import '../time_scale.dart';

/// Crosshair lines + price tag on the right axis + time tag on the bottom.
class CrosshairPainter extends CustomPainter {
  CrosshairPainter({
    required this.mapper,
    required this.controller,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final MapperImpl mapper;
  final ChartController controller;
  Candle? get candle => controller.crosshairCandle;
  ChartTimeframe get timeframe => mapper.timeframe;

  static final _linePaint = Paint()
    ..color = ChartColors.crosshair
    ..strokeWidth = 1
    ..style = PaintingStyle.stroke;

  static final _tagBg = Paint()
    ..color = ChartColors.crosshairTag
    ..style = PaintingStyle.fill;

  static const _tagStyle = TextStyle(
    color: ChartColors.axisText,
    fontSize: 10,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  @override
  void paint(Canvas canvas, Size size) {
    final c = candle;
    if (c == null) return;
    final plot = mapper.plotRect;
    if (plot.width <= 0) return;

    final x = mapper.timeToX(c.time);
    final y = mapper.priceToY(c.close);

    // Vertical + horizontal lines.
    canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), _linePaint);
    canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), _linePaint);

    // Price tag (right).
    final priceText = c.close.toStringAsFixed(mapper.pricePrecision);
    _drawTag(
      canvas,
      text: priceText,
      anchor: Offset(plot.right + 2, y),
      alignLeft: true,
    );

    // Time tag (bottom).
    final timeText = TimeScale.formatLabel(c.time, timeframe);
    _drawTag(
      canvas,
      text: timeText,
      anchor: Offset(x, plot.bottom + 2),
      alignLeft: false,
      centerH: true,
    );
  }

  void _drawTag(
    Canvas canvas, {
    required String text,
    required Offset anchor,
    bool alignLeft = true,
    bool centerH = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: _tagStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    const padH = 5.0;
    const padV = 2.5;
    final w = tp.width + padH * 2;
    final h = tp.height + padV * 2;
    double left;
    if (centerH) {
      left = anchor.dx - w / 2;
    } else if (alignLeft) {
      left = anchor.dx;
    } else {
      left = anchor.dx - w;
    }
    final top = centerH ? anchor.dy : anchor.dy - h / 2;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, w, h),
      const Radius.circular(3),
    );
    canvas.drawRRect(rrect, _tagBg);
    tp.paint(canvas, Offset(left + padH, top + padV));
  }

  @override
  bool shouldRepaint(covariant CrosshairPainter old) =>
      true;
}
