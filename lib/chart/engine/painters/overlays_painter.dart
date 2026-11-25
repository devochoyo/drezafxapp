import 'package:flutter/material.dart';

import '../../contracts/chart_contracts.dart';
import '../mapper_impl.dart';

/// Paints all registered [ChartOverlay]s in ascending zOrder.
class OverlaysPainter extends CustomPainter {
  OverlaysPainter({
    required this.mapper,
    required this.overlays,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final MapperImpl mapper;
  final List<ChartOverlay> overlays;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = mapper.plotRect;
    if (plot.width <= 0) return;
    canvas.save();
    canvas.clipRect(plot.inflate(1));
    // Already sorted by the controller; paint low → high.
    for (final o in overlays) {
      o.paint(canvas, mapper);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant OverlaysPainter old) => true;
}
