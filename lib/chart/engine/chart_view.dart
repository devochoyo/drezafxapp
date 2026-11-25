import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../contracts/chart_contracts.dart';
import 'chart_controller_impl.dart';
import 'painters/candles_painter.dart';
import 'painters/crosshair_painter.dart';
import 'painters/grid_axes_painter.dart';
import 'painters/last_price_painter.dart';
import 'painters/overlays_painter.dart';

/// The interactive chart widget. All gestures are handled via raw [Listener]
/// for lowest latency and correct overlay arbitration.
class ChartView extends StatefulWidget {
  const ChartView({
    super.key,
    required this.controller,
  });

  final ChartControllerImpl controller;

  @override
  State<ChartView> createState() => _ChartViewState();
}

class _ChartViewState extends State<ChartView>
    with SingleTickerProviderStateMixin {
  // ---- gesture state ----------------------------------------------------
  int? _activePointer;
  Offset? _downPos;
  Offset? _lastPos;
  ChartOverlay? _capturedOverlay;
  bool _isPanning = false;
  bool _isScalingPrice = false;
  bool _isPinching = false;

  // Pinch
  final Map<int, Offset> _pointers = {};
  double? _pinchStartDist;
  double? _pinchStartCount;
  Offset? _pinchFocal;

  // Long-press → crosshair
  Timer? _longPressTimer;
  bool _crosshairActive = false;

  // Fling
  late final AnimationController _flingCtrl;
  double _lastFlingX = 0;

  // Double-tap detection on price axis
  DateTime? _lastAxisTap;
  bool _tapClearsCrosshair = false;
  final List<Offset> _vel = <Offset>[];
  final List<int> _velT = <int>[];

  ChartControllerImpl get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _flingCtrl = AnimationController.unbounded(vsync: this)
      ..addListener(_onFlingTick);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (c.loadState == ChartLoadState.idle) {
        c.reload();
      }
    });
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _flingCtrl.dispose();
    super.dispose();
  }

  // ========================================================================
  // Build — 5 RepaintBoundary layers
  // ========================================================================

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        c.onSizeChanged(size);

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Static: grid + axes
              RepaintBoundary(
                child: CustomPaint(
                  painter: GridAxesPainter(
                    mapper: c.mapperImpl,
                    viewport: c.viewport,
                    repaint: c.viewportChanges,
                  ),
                  size: size,
                ),
              ),
              // 2. Candles
              RepaintBoundary(
                child: CustomPaint(
                  painter: CandlesPainter(
                    mapper: c.mapperImpl,
                    viewport: c.viewport,
                    repaint: c.viewportChanges,
                  ),
                  size: size,
                ),
              ),
              // 3. Last-price line + tag
              RepaintBoundary(
                child: CustomPaint(
                  painter: LastPricePainter(
                    mapper: c.mapperImpl,
                    controller: c,
                    repaint: c,
                  ),
                  size: size,
                ),
              ),
              // 4. Overlays (alarms, drawings)
              RepaintBoundary(
                child: CustomPaint(
                  painter: OverlaysPainter(
                    mapper: c.mapperImpl,
                    overlays: c.overlays,
                    repaint: c.viewportChanges,
                  ),
                  size: size,
                ),
              ),
              // 5. Crosshair
              RepaintBoundary(
                child: CustomPaint(
                  painter: CrosshairPainter(
                    mapper: c.mapperImpl,
                    controller: c,
                    repaint: c,
                  ),
                  size: size,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ========================================================================
  // Gestures
  // ========================================================================

  void _onPointerDown(PointerDownEvent e) {
    _flingCtrl.stop();
    _pointers[e.pointer] = e.localPosition;

    if (_pointers.length == 2) {
      _cancelLongPress();
      _isPinching = true;
      final pts = _pointers.values.toList();
      _pinchStartDist = (pts[0] - pts[1]).distance;
      _pinchStartCount = c.viewport.visibleCount;
      c.viewport.beginPinch();
      _pinchFocal = Offset(
        (pts[0].dx + pts[1].dx) / 2,
        (pts[0].dy + pts[1].dy) / 2,
      );
      return;
    }

    if (_pointers.length > 2) return;

    _tapClearsCrosshair = c.crosshairCandle != null;
    _crosshairActive = false;
    _vel.clear();
    _activePointer = e.pointer;
    _downPos = e.localPosition;
    _lastPos = e.localPosition;
    _isPanning = false;
    _isScalingPrice = false;
    _capturedOverlay = null;

    final plot = c.mapper.plotRect;
    final inPlot = plot.contains(e.localPosition);

    if (inPlot) {
      for (var i = c.overlays.length - 1; i >= 0; i--) {
        final o = c.overlays[i];
        if (o.capturesAllPointers) {
          _capturedOverlay = o;
          o.onDragStart(e.localPosition, c.mapper);
          return;
        }
      }
      for (var i = c.overlays.length - 1; i >= 0; i--) {
        final o = c.overlays[i];
        if (o.hitTest(e.localPosition, c.mapper)) {
          _capturedOverlay = o;
          o.onDragStart(e.localPosition, c.mapper);
          return;
        }
      }
    }

    if (e.localPosition.dx > plot.right) {
      _isScalingPrice = true;
      c.viewport.beginPriceDrag();
      return;
    }

    _cancelLongPress();
    _longPressTimer = Timer(const Duration(milliseconds: 350), () {
      if (_activePointer == e.pointer && !_isPanning && !_isPinching) {
        _crosshairActive = true;
        final candle = c.mapper.candleAtX(e.localPosition.dx);
        c.setCrosshair(candle);
      }
    });
  }

  void _onPointerMove(PointerMoveEvent e) {
    _pointers[e.pointer] = e.localPosition;

    if (_isPinching && _pointers.length >= 2) {
      final pts = _pointers.values.toList();
      final dist = (pts[0] - pts[1]).distance;
      if (_pinchStartDist != null &&
          _pinchStartDist! > 0 &&
          _pinchStartCount != null) {
        final scale = dist / _pinchStartDist!;
        final focal = _pinchFocal ?? e.localPosition;
        c.viewport.pinchTo(focal.dx, scale);
        if (!c.viewport.isPriceScaleManual) {
          c.viewport.autoFitPrice(c.candles);
        }
      }
      return;
    }

    if (_activePointer != e.pointer) return;
    final last = _lastPos;
    if (last == null) return;
    final delta = e.localPosition - last;
    _lastPos = e.localPosition;

    if (_capturedOverlay != null) {
      _capturedOverlay!.onDragUpdate(e.localPosition, delta, c.mapper);
      return;
    }

    if (_isScalingPrice) {
      final startY = _downPos?.dy ?? e.localPosition.dy;
      c.viewport.priceDragTo(e.localPosition.dy - startY);
      return;
    }

    if (_crosshairActive) {
      final candle = c.mapper.candleAtX(e.localPosition.dx);
      c.setCrosshair(candle);
      return;
    }

    final down = _downPos;
    if (down != null && !_isPanning) {
      if ((e.localPosition - down).distance > 8) {
        _isPanning = true;
        _cancelLongPress();
      }
    }
    if (_isPanning) {
      _vel.add(e.localPosition);
      _velT.add(e.timeStamp.inMilliseconds);
      if (_vel.length > 6) {
        _vel.removeAt(0);
        _velT.removeAt(0);
      }
      c.viewport.panByPixels(delta.dx);
      if (c.viewport.freeMove) {
        c.viewport.panPriceByPixels(delta.dy);
      } else if (!c.viewport.isPriceScaleManual) {
        c.viewport.autoFitPrice(c.candles);
      }
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    _pointers.remove(e.pointer);

    if (_isPinching) {
      if (_pointers.length < 2) {
        _isPinching = false;
        _pinchStartDist = null;
      }
      _resetGesture();
      return;
    }

    if (_activePointer != e.pointer) return;

    if (_capturedOverlay != null) {
      final down = _downPos;
      final moved =
          down != null && (e.localPosition - down).distance > 8;
      if (!moved) {
        _capturedOverlay!.onTap(e.localPosition, c.mapper);
      }
      _capturedOverlay!.onDragEnd(c.mapper);
      _capturedOverlay = null;
      _resetGesture();
      return;
    }

    if (_isScalingPrice &&
        _downPos != null &&
        (e.localPosition - _downPos!).distance < 6) {
      _maybeDoubleTapAxis();
    }

    // Clear crosshair on a clean tap.
    if (!_isPanning &&
        !_isScalingPrice &&
        _tapClearsCrosshair &&
        _downPos != null &&
        (e.localPosition - _downPos!).distance < 8) {
      c.setCrosshair(null);
    }
    _startFling();

    _resetGesture();
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _pointers.remove(e.pointer);
    if (_capturedOverlay != null) {
      _capturedOverlay!.onDragEnd(c.mapper);
      _capturedOverlay = null;
    }
    _resetGesture();
  }

  void _resetGesture() {
    _activePointer = null;
    _downPos = null;
    _lastPos = null;
    _isPanning = false;
    _isScalingPrice = false;
    _cancelLongPress();
  }

  void _cancelLongPress() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  void _startFling() {
    if (!_isPanning || _vel.length < 2) return;
    final dt = _velT.last - _velT.first;
    if (dt <= 0 || dt > 120) return;
    final vx = (_vel.last.dx - _vel.first.dx) / dt * 1000;
    if (vx.abs() < 150) return;
    _lastFlingX = 0;
    _flingSim = FrictionSimulation(0.135, 0, vx);
    _flingCtrl.value = 0;
    _flingCtrl.animateWith(_flingSim!);
  }

  FrictionSimulation? _flingSim;

  void _onFlingTick() {
    final x = _flingCtrl.value;
    final dx = x - _lastFlingX;
    _lastFlingX = x;
    if (dx == 0) return;
    c.viewport.panByPixels(dx);
    if (!c.viewport.isPriceScaleManual) {
      c.viewport.autoFitPrice(c.candles);
    }
  }

  void _maybeDoubleTapAxis() {
    final now = DateTime.now();
    if (_lastAxisTap != null &&
        now.difference(_lastAxisTap!) < const Duration(milliseconds: 350)) {
      c.resetPriceScale();
      _lastAxisTap = null;
    } else {
      _lastAxisTap = now;
    }
  }
}
