import 'dart:ui';

import 'package:flutter/material.dart';

import '../../contracts/chart_contracts.dart';
import '../mapper_impl.dart';

/// Live layer: dashed amber last-price line + rounded tag on the price axis.
class LastPricePainter extends CustomPainter {
  LastPricePainter({
    required this.mapper,
    required this.controller,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final MapperImpl mapper;
  final ChartController controller;
  double? get lastPrice => controller.lastPrice;

  static final _linePaint = Paint()
    ..color = ChartColors.lastPrice
    ..strokeWidth = 1
    ..style = PaintingStyle.stroke;

  static final _tagBg = Paint()
    ..color = ChartColors.lastPrice
    ..style = PaintingStyle.fill;

  static const _tagStyle = TextStyle(
    color: ChartColors.lastPriceText,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  @override
  void paint(Canvas canvas, Size size) {
    final price = lastPrice;
    if (price == null) return;
    final plot = mapper.plotRect;
    if (plot.width <= 0) return;

    final y = mapper.priceToY(price);
    if (y < plot.top - 20 || y > plot.bottom + 20) return;

    // Dashed line across the plot.
    _drawDashedLine(
      canvas,
      Offset(plot.left, y),
      Offset(plot.right, y),
      _linePaint,
      dashWidth: 4,
      gap: 3,
    );

    // Tag on the price axis.
    final text = price.toStringAsFixed(mapper.pricePrecision);
    final tp = TextPainter(
      text: TextSpan(text: text, style: _tagStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    const padH = 6.0;
    const padV = 3.0;
    final tagW = tp.width + padH * 2;
    final tagH = tp.height + padV * 2;
    final tagLeft = plot.right + 2;
    final tagTop = y - tagH / 2;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(tagLeft, tagTop, tagW, tagH),
      const Radius.circular(4),
    );
    canvas.drawRRect(rrect, _tagBg);
    tp.paint(canvas, Offset(tagLeft + padH, tagTop + padV));
  }

  static void _drawDashedLine(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint paint, {
    double dashWidth = 4,
    double gap = 3,
  }) {
    final total = (b.dx - a.dx).abs();
    var x = a.dx;
    final y = a.dy;
    while (x < b.dx) {
      final x2 = (x + dashWidth).clamp(x, b.dx);
      canvas.drawLine(Offset(x, y), Offset(x2, y), paint);
      x += dashWidth + gap;
      if (x >= a.dx + total) break;
    }
  }

  @override
  bool shouldRepaint(covariant LastPricePainter old) =>
      true;
}
