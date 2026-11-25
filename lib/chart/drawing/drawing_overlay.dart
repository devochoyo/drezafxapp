import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../../screens/common/dz_theme.dart';
import '../contracts/chart_contracts.dart';
import 'drawing_models.dart';

/// Drawing overlay (zOrder 100). Handles create / select / move / resize.
class DrawingOverlay extends ChartOverlay {
  DrawingOverlay({
    required this.onShapesChanged,
    this.onBeforeMutation,
  });

  final VoidCallback onShapesChanged;
  /// Called once when the user starts moving/resizing an existing shape.
  final VoidCallback? onBeforeMutation;

  List<DrawingShape> shapes = [];
  String? selectedId;

  // Armed tool
  DrawingType? armedTool;
  bool stayInMode = false;
  bool magnet = false;

  // Creation in progress
  DrawingPoint? _p1;
  Offset? _previewEnd;
  bool _creating = false;

  // Drag state
  enum _DragKind { none, move, handle0, handle1 }
  _DragKind _drag = _DragKind.none;
  DrawingShape? _dragShape;
  List<DrawingPoint>? _dragStartPts;
  Offset? _dragStartPos;

  @override
  int get zOrder => 100;

  @override
  bool get capturesAllPointers => armedTool != null;

  // ---- public API used by the feature -----------------------------------

  void setShapes(List<DrawingShape> list) {
    shapes = List<DrawingShape>.from(list);
    notifyListeners();
  }

  void arm(DrawingType? tool) {
    armedTool = tool;
    _p1 = null;
    _previewEnd = null;
    _creating = false;
    if (tool != null) selectedId = null;
    notifyListeners();
  }

  void select(String? id) {
    selectedId = id;
    notifyListeners();
  }

  void updateSelectedStyle(DrawingStyle style) {
    final id = selectedId;
    if (id == null) return;
    final i = shapes.indexWhere((s) => s.id == id);
    if (i < 0) return;
    shapes[i] = shapes[i].copyWith(style: style);
    onShapesChanged();
    notifyListeners();
  }

  void deleteSelected() {
    final id = selectedId;
    if (id == null) return;
    shapes.removeWhere((s) => s.id == id);
    selectedId = null;
    onShapesChanged();
    notifyListeners();
  }

  // ---- paint ------------------------------------------------------------

  @override
  void paint(Canvas canvas, ChartCoordinateMapper map) {
    final plot = map.plotRect;
    if (plot.width <= 0) return;
    canvas.save();
    canvas.clipRect(plot);

    for (final s in shapes) {
      _paintShape(canvas, map, s, selected: s.id == selectedId);
    }

    // Live preview while placing point 2.
    if (_creating && _p1 != null && _previewEnd != null && armedTool != null) {
      final p1 = _p1!;
      final x1 = map.timeToX(p1.time);
      final y1 = map.priceToY(p1.price);
      final x2 = _previewEnd!.dx;
      final y2 = _previewEnd!.dy;
      final paint = Paint()
        ..color = DzColors.accent2.withAlpha(180)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      switch (armedTool!) {
        case DrawingType.trendline:
          canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
          break;
        case DrawingType.rectangle:
          canvas.drawRect(Rect.fromPoints(Offset(x1, y1), Offset(x2, y2)), paint);
          break;
        case DrawingType.horizontalLine:
          break;
      }
    }

    canvas.restore();
  }

  void _paintShape(
    Canvas canvas,
    ChartCoordinateMapper map,
    DrawingShape s, {
    required bool selected,
  }) {
    final style = s.style;
    final paint = Paint()
      ..color = style.color
      ..strokeWidth = style.width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    switch (s.type) {
      case DrawingType.horizontalLine:
        if (s.points.isEmpty) return;
        final y = map.priceToY(s.points.first.price);
        final plot = map.plotRect;
        canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), paint);
        // Small price label left-centre.
        final label = s.points.first.price.toStringAsFixed(map.pricePrecision);
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              color: style.color,
              fontSize: 10,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(plot.left + 6, y - tp.height - 2));
        if (selected) {
          _drawHandle(canvas, Offset(plot.center.dx, y));
        }
        break;

      case DrawingType.trendline:
        if (s.points.length < 2) return;
        final a = s.points[0];
        final b = s.points[1];
        final o1 = Offset(map.timeToX(a.time), map.priceToY(a.price));
        var o2 = Offset(map.timeToX(b.time), map.priceToY(b.price));
        if (style.extendRight) {
          final plot = map.plotRect;
          final dx = o2.dx - o1.dx;
          final dy = o2.dy - o1.dy;
          if (dx.abs() > 1e-6) {
            final t = (plot.right - o1.dx) / dx;
            o2 = Offset(plot.right, o1.dy + dy * t);
          }
        }
        canvas.drawLine(o1, o2, paint);
        if (selected) {
          _drawHandle(canvas, o1);
          _drawHandle(canvas, Offset(map.timeToX(b.time), map.priceToY(b.price)));
        }
        break;

      case DrawingType.rectangle:
        if (s.points.length < 2) return;
        final a = s.points[0];
        final b = s.points[1];
        final r = Rect.fromPoints(
          Offset(map.timeToX(a.time), map.priceToY(a.price)),
          Offset(map.timeToX(b.time), map.priceToY(b.price)),
        );
        // Fill
        final fill = Paint()
          ..color = style.color.withAlpha(style.fillAlpha.round().clamp(0, 255))
          ..style = PaintingStyle.fill;
        canvas.drawRect(r, fill);
        canvas.drawRect(r, paint);
        if (selected) {
          _drawHandle(canvas, r.topLeft);
          _drawHandle(canvas, r.bottomRight);
        }
        break;
    }
  }

  void _drawHandle(Canvas canvas, Offset c) {
    final bg = Paint()..color = DzColors.text;
    final ring = Paint()
      ..color = DzColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(c, 5, bg);
    canvas.drawCircle(c, 5, ring);
  }

  // ---- hit test ---------------------------------------------------------

  @override
  bool hitTest(Offset position, ChartCoordinateMapper map) {
    if (armedTool != null) return true; // capturesAllPointers
    return _hitShape(position, map) != null;
  }

  DrawingShape? _hitShape(Offset position, ChartCoordinateMapper map) {
    // Prefer selected, then top-most.
    for (final s in shapes.reversed) {
      if (_shapeHits(s, position, map)) return s;
    }
    return null;
  }

  bool _shapeHits(DrawingShape s, Offset pos, ChartCoordinateMapper map) {
    const slop = 20.0;
    switch (s.type) {
      case DrawingType.horizontalLine:
        if (s.points.isEmpty) return false;
        final y = map.priceToY(s.points.first.price);
        return (pos.dy - y).abs() <= slop;

      case DrawingType.trendline:
        if (s.points.length < 2) return false;
        final a = Offset(
            map.timeToX(s.points[0].time), map.priceToY(s.points[0].price));
        final b = Offset(
            map.timeToX(s.points[1].time), map.priceToY(s.points[1].price));
        return _distToSegment(pos, a, b) <= slop;

      case DrawingType.rectangle:
        if (s.points.length < 2) return false;
        final r = Rect.fromPoints(
          Offset(map.timeToX(s.points[0].time),
              map.priceToY(s.points[0].price)),
          Offset(map.timeToX(s.points[1].time),
              map.priceToY(s.points[1].price)),
        ).inflate(slop);
        // Hit if near edge or inside.
        final inner = r.deflate(slop * 2);
        if (r.contains(pos) && !inner.contains(pos)) return true;
        return r.contains(pos);
    }
  }

  static double _distToSegment(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    if (dx == 0 && dy == 0) return (p - a).distance;
    final t = ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / (dx * dx + dy * dy);
    final tc = t.clamp(0.0, 1.0);
    final proj = Offset(a.dx + tc * dx, a.dy + tc * dy);
    return (p - proj).distance;
  }

  int? _hitHandle(DrawingShape s, Offset pos, ChartCoordinateMapper map) {
    const r = 14.0;
    if (s.type == DrawingType.horizontalLine) return null;
    if (s.points.isEmpty) return null;
    for (var i = 0; i < s.points.length && i < 2; i++) {
      final o = Offset(
          map.timeToX(s.points[i].time), map.priceToY(s.points[i].price));
      if ((pos - o).distance <= r) return i;
    }
    return null;
  }

  // ---- gestures ---------------------------------------------------------

  @override
  void onTap(Offset position, ChartCoordinateMapper map) {
    if (armedTool != null) {
      _placePoint(position, map);
      return;
    }
    final hit = _hitShape(position, map);
    selectedId = hit?.id;
    notifyListeners();
  }

  @override
  void onDragStart(Offset position, ChartCoordinateMapper map) {
    if (armedTool != null) {
      if (armedTool == DrawingType.horizontalLine) {
        _placePoint(position, map);
        return;
      }
      // Start creation: set p1.
      final pt = _pointFromOffset(position, map);
      _p1 = pt;
      _previewEnd = position;
      _creating = true;
      notifyListeners();
      return;
    }

    // Editing existing.
    final hit = _hitShape(position, map);
    if (hit == null) {
      selectedId = null;
      _drag = _DragKind.none;
      notifyListeners();
      return;
    }
    selectedId = hit.id;
    final handle = _hitHandle(hit, position, map);
    if (handle == 0) {
      _drag = _DragKind.handle0;
    } else if (handle == 1) {
      _drag = _DragKind.handle1;
    } else {
      _drag = _DragKind.move;
    }
    _dragShape = hit;
    _dragStartPts = List<DrawingPoint>.from(hit.points);
    _dragStartPos = position;
    onBeforeMutation?.call();
    notifyListeners();
  }

  @override
  void onDragUpdate(Offset position, Offset delta, ChartCoordinateMapper map) {
    if (armedTool != null && _creating) {
      _previewEnd = position;
      notifyListeners();
      return;
    }

    final shape = _dragShape;
    final startPts = _dragStartPts;
    final startPos = _dragStartPos;
    if (shape == null || startPts == null || startPos == null) return;

    if (_drag == _DragKind.move) {
      final dTime = map.xToTime(position.dx) - map.xToTime(startPos.dx);
      final dPrice = map.yToPrice(position.dy) - map.yToPrice(startPos.dy);
      final moved = [
        for (final p in startPts)
          DrawingPoint(time: p.time + dTime, price: p.price + dPrice),
      ];
      _replaceShape(shape.id, shape.copyWith(points: moved));
    } else if (_drag == _DragKind.handle0 || _drag == _DragKind.handle1) {
      final idx = _drag == _DragKind.handle0 ? 0 : 1;
      final pts = List<DrawingPoint>.from(startPts);
      if (idx < pts.length) {
        pts[idx] = _pointFromOffset(position, map);
        _replaceShape(shape.id, shape.copyWith(points: pts));
      }
    }
  }

  @override
  void onDragEnd(ChartCoordinateMapper map) {
    if (armedTool != null && _creating && _p1 != null && _previewEnd != null) {
      final moved = (_previewEnd! -
              Offset(map.timeToX(_p1!.time), map.priceToY(_p1!.price)))
          .distance;
      if (moved > 12) {
        // Complete with point 2.
        final p2 = _pointFromOffset(_previewEnd!, map);
        _finishShape([_p1!, p2]);
      } else {
        // Treat as tap for p1; wait for second tap.
        // Keep _p1, clear creating flag for next tap.
      }
      _creating = false;
      _previewEnd = null;
      notifyListeners();
      return;
    }

    if (_drag != _DragKind.none) {
      onShapesChanged(); // commit one undo entry
    }
    _drag = _DragKind.none;
    _dragShape = null;
    _dragStartPts = null;
    _dragStartPos = null;
  }

  void _placePoint(Offset position, ChartCoordinateMapper map) {
    final tool = armedTool;
    if (tool == null) return;
    final pt = _pointFromOffset(position, map);

    if (tool == DrawingType.horizontalLine) {
      _finishShape([pt]);
      return;
    }

    if (_p1 == null) {
      _p1 = pt;
      notifyListeners();
      return;
    }
    // Second tap.
    _finishShape([_p1!, pt]);
  }

  void _finishShape(List<DrawingPoint> pts) {
    final tool = armedTool;
    if (tool == null) return;
    final id =
        'd_${DateTime.now().microsecondsSinceEpoch}_${math.Random().nextInt(999)}';
    final shape = DrawingShape(
      id: id,
      type: tool,
      points: pts,
      style: DrawingStyle.defaultsFor(tool),
    );
    shapes = [...shapes, shape];
    selectedId = id;
    _p1 = null;
    _previewEnd = null;
    _creating = false;
    if (!stayInMode) {
      armedTool = null;
    }
    onShapesChanged();
    notifyListeners();
  }

  void _replaceShape(String id, DrawingShape next) {
    final i = shapes.indexWhere((s) => s.id == id);
    if (i < 0) return;
    shapes = List<DrawingShape>.from(shapes)..[i] = next;
    notifyListeners();
  }

  DrawingPoint _pointFromOffset(Offset pos, ChartCoordinateMapper map) {
    var time = map.xToTime(pos.dx);
    var price = map.yToPrice(pos.dy);

    if (magnet) {
      final c = map.candleAtX(pos.dx);
      if (c != null) {
        // Snap to nearest OHLC within ~10 dp.
        final candidates = [c.open, c.high, c.low, c.close];
        double best = price;
        double bestDist = double.infinity;
        for (final p in candidates) {
          final y = map.priceToY(p);
          final d = (y - pos.dy).abs();
          if (d < bestDist && d <= 10) {
            bestDist = d;
            best = p;
          }
        }
        price = best;
        time = c.time;
      }
    }
    return DrawingPoint(time: time, price: price);
  }
}
