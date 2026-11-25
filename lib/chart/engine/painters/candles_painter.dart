import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Viewport;

import '../../contracts/chart_contracts.dart';
import '../mapper_impl.dart';
import '../viewport.dart';

/// High-performance candle layer.
///
/// Hot-path rules:
///  * Pre-allocated [Paint] objects (never create per frame).
///  * Visible range clamped by index.
///  * Wicks drawn with [Canvas.drawRawPoints] (one call per colour).
///  * Bodies drawn with a single [Path] per colour.
///  * Pixel-snapped X for crisp 1-px wicks.
class CandlesPainter extends CustomPainter {
  CandlesPainter({
    required this.mapper,
    required this.viewport,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final MapperImpl mapper;
  final Viewport viewport;

  static final _bullWick = Paint()
    ..color = ChartColors.bull
    ..strokeWidth = 1
    ..style = PaintingStyle.stroke
    ..isAntiAlias = false;

  static final _bearWick = Paint()
    ..color = ChartColors.bear
    ..strokeWidth = 1
    ..style = PaintingStyle.stroke
    ..isAntiAlias = false;

  static final _bullBody = Paint()
    ..color = ChartColors.bull
    ..style = PaintingStyle.fill
    ..isAntiAlias = false;

  static final _bearBody = Paint()
    ..color = ChartColors.bear
    ..style = PaintingStyle.fill
    ..isAntiAlias = false;

  // Grow-only buffers.
  static Float32List _bullWickPts = Float32List(0);
  static Float32List _bearWickPts = Float32List(0);
  static final Path _bullPath = Path();
  static final Path _bearPath = Path();

  @override
  void paint(Canvas canvas, Size size) {
    final candles = mapper.candles;
    if (candles.isEmpty) return;
    final plot = mapper.plotRect;
    if (plot.width <= 0 || plot.height <= 0) return;

    final first = viewport.startIndex.floor().clamp(0, candles.length - 1);
    final last = viewport.endIndex.ceil().clamp(0, candles.length - 1);
    if (first > last) return;

    final slotW = plot.width / viewport.visibleCount;
    final bodyW = (slotW * 0.70).clamp(1.0, slotW);
    final halfBody = bodyW / 2;
    const minBodyH = 1.0;

    final need = (last - first + 1) * 4;
    if (_bullWickPts.length < need) {
      _bullWickPts = Float32List(need * 2);
      _bearWickPts = Float32List(need * 2);
    }

    _bullPath.reset();
    _bearPath.reset();
    var bullWickN = 0;
    var bearWickN = 0;

    for (var i = first; i <= last; i++) {
      final c = candles[i];
      final cx = mapper.timeToX(c.time).roundToDouble();
      final yHigh = mapper.priceToY(c.high);
      final yLow = mapper.priceToY(c.low);
      var yOpen = mapper.priceToY(c.open);
      var yClose = mapper.priceToY(c.close);

      if ((yOpen - yClose).abs() < minBodyH) {
        final mid = (yOpen + yClose) / 2;
        yOpen = mid - minBodyH / 2;
        yClose = mid + minBodyH / 2;
      }

      final top = yOpen < yClose ? yOpen : yClose;
      final bot = yOpen < yClose ? yClose : yOpen;

      if (c.isBullish) {
        _bullWickPts[bullWickN++] = cx;
        _bullWickPts[bullWickN++] = yHigh;
        _bullWickPts[bullWickN++] = cx;
        _bullWickPts[bullWickN++] = yLow;
        _bullPath.addRect(
          Rect.fromLTRB(cx - halfBody, top, cx + halfBody, bot),
        );
      } else {
        _bearWickPts[bearWickN++] = cx;
        _bearWickPts[bearWickN++] = yHigh;
        _bearWickPts[bearWickN++] = cx;
        _bearWickPts[bearWickN++] = yLow;
        _bearPath.addRect(
          Rect.fromLTRB(cx - halfBody, top, cx + halfBody, bot),
        );
      }
    }

    if (bullWickN > 0) {
      canvas.drawRawPoints(
        ui.PointMode.lines,
        Float32List.sublistView(_bullWickPts, 0, bullWickN),
        _bullWick,
      );
    }
    if (bearWickN > 0) {
      canvas.drawRawPoints(
        ui.PointMode.lines,
        Float32List.sublistView(_bearWickPts, 0, bearWickN),
        _bearWick,
      );
    }

    canvas.drawPath(_bullPath, _bullBody);
    canvas.drawPath(_bearPath, _bearBody);
  }

  @override
  bool shouldRepaint(covariant CandlesPainter old) => true;
}
