import 'package:flutter/material.dart';

import '../contracts/chart_contracts.dart';
import 'drawing_models.dart';
import 'drawing_overlay.dart';
import 'drawing_sheet.dart';
import 'drawing_store.dart';
import 'drawing_style_bar.dart';
import 'undo_stack.dart';

/// Chart feature: Trendline, Rectangle, Horizontal Line + undo/redo.
class DrawingChartFeature extends ChartFeature {
  ChartController? _controller;
  DrawingOverlay? _overlay;
  final DrawingStore _store = DrawingStore();
  final DrawingUndoStack _undo = DrawingUndoStack();
  final ValueNotifier<bool> _armed = ValueNotifier(false);
  final ValueNotifier<bool> _canUndo = ValueNotifier(false);
  final ValueNotifier<bool> _canRedo = ValueNotifier(false);
  String? _symbol;
  bool _stayInMode = false;
  bool _magnet = false;

  // Snapshot before the current gesture for a single undo entry.
  List<DrawingShape>? _preGestureSnapshot;

  @override
  String get id => 'drawing';

  @override
  void attach(ChartController controller, BuildContext context) {
    _controller = controller;
    _symbol = controller.symbol;

    _overlay = DrawingOverlay(
      onShapesChanged: _onShapesCommitted,
      onBeforeMutation: () {
        final o = _overlay;
        if (o != null) {
          _preGestureSnapshot = List<DrawingShape>.from(o.shapes);
        }
      },
    );
    controller.addOverlay(_overlay!);
    controller.addListener(_onControllerChanged);

    _loadForSymbol(controller.symbol);
  }

  void _onControllerChanged() {
    final c = _controller;
    if (c == null) return;
    if (c.symbol != _symbol) {
      // Flush old, load new.
      if (_symbol != null && _overlay != null) {
        _store.flush(_symbol!, _overlay!.shapes);
      }
      _symbol = c.symbol;
      _undo.clear();
      _updateUndoFlags();
      _loadForSymbol(c.symbol);
    }
  }

  Future<void> _loadForSymbol(String symbol) async {
    final list = await _store.load(symbol);
    _overlay?.setShapes(list);
    notifyListeners();
  }

  void _onShapesCommitted() {
    final overlay = _overlay;
    final symbol = _symbol;
    if (overlay == null || symbol == null) return;

    // Push undo snapshot from before the gesture if we have one.
    if (_preGestureSnapshot != null) {
      _undo.push(_preGestureSnapshot!);
      _preGestureSnapshot = null;
      _updateUndoFlags();
    } else {
      // Creation / style / delete — push current-minus-last-change is hard;
      // push the previous shapes list by cloning before mutation next time.
      // For style/delete we push explicitly in those methods.
    }

    _store.saveDebounced(symbol, overlay.shapes);
    _armed.value = overlay.armedTool != null;
    notifyListeners();
  }

  void _pushUndoBeforeMutation() {
    final overlay = _overlay;
    if (overlay == null) return;
    _undo.push(overlay.shapes);
    _updateUndoFlags();
  }

  void _updateUndoFlags() {
    _canUndo.value = _undo.canUndo;
    _canRedo.value = _undo.canRedo;
  }

  @override
  void detach() {
    final c = _controller;
    final o = _overlay;
    final sym = _symbol;
    if (c != null && o != null) {
      if (sym != null) {
        _store.flush(sym, o.shapes);
      }
      c.removeOverlay(o);
      c.removeListener(_onControllerChanged);
    }
    _store.dispose();
    _overlay = null;
    _controller = null;
    _armed.value = false;
  }

  Future<void> _openSheet(BuildContext context) async {
    final tool = await showDrawingSheet(
      context,
      stayInMode: _stayInMode,
      magnet: _magnet,
      onStayInMode: (v) {
        _stayInMode = v;
        _overlay?.stayInMode = v;
      },
      onMagnet: (v) {
        _magnet = v;
        _overlay?.magnet = v;
      },
      onClearAll: () {
        final o = _overlay;
        if (o == null) return;
        _pushUndoBeforeMutation();
        o.setShapes([]);
        o.select(null);
        _onShapesCommitted();
      },
    );
    if (tool != null) {
      _overlay?.stayInMode = _stayInMode;
      _overlay?.magnet = _magnet;
      // Snapshot before creation.
      _preGestureSnapshot = List<DrawingShape>.from(_overlay?.shapes ?? []);
      _overlay?.arm(tool);
      _armed.value = true;
      notifyListeners();
    } else {
      // Closed without choosing — disarm if was armed.
      // Keep current arm state.
    }
  }

  void _doUndo() {
    final o = _overlay;
    if (o == null) return;
    final prev = _undo.undo(o.shapes);
    if (prev == null) return;
    o.setShapes(prev);
    o.select(null);
    if (_symbol != null) _store.saveDebounced(_symbol!, prev);
    _updateUndoFlags();
    notifyListeners();
  }

  void _doRedo() {
    final o = _overlay;
    if (o == null) return;
    final next = _undo.redo(o.shapes);
    if (next == null) return;
    o.setShapes(next);
    o.select(null);
    if (_symbol != null) _store.saveDebounced(_symbol!, next);
    _updateUndoFlags();
    notifyListeners();
  }

  @override
  List<ChartToolbarItem> toolbarItems(BuildContext context) {
    return [
      ChartToolbarItem(
        id: 'drawing',
        icon: Icons.edit_outlined,
        tooltip: 'Drawing tools',
        onTap: () {
          if (_overlay?.armedTool != null) {
            // Toggle off.
            _overlay?.arm(null);
            _armed.value = false;
            notifyListeners();
          } else {
            _openSheet(context);
          }
        },
        placement: ChartToolbarPlacement.bottomBar,
        order: 40,
        active: _armed,
      ),
      ChartToolbarItem(
        id: 'undo',
        icon: Icons.undo,
        tooltip: 'Undo',
        onTap: _doUndo,
        placement: ChartToolbarPlacement.topBar,
        order: 10,
        enabled: _canUndo,
      ),
      ChartToolbarItem(
        id: 'redo',
        icon: Icons.redo,
        tooltip: 'Redo',
        onTap: _doRedo,
        placement: ChartToolbarPlacement.topBar,
        order: 11,
        enabled: _canRedo,
      ),
    ];
  }

  @override
  List<Widget> buildFloating(BuildContext context) {
    final o = _overlay;
    if (o == null) return const [];

    final widgets = <Widget>[];

    // Hint while a tool is armed and no point placed yet.
    if (o.armedTool != null && o.selectedId == null) {
      widgets.add(
        const Positioned(
          top: 8,
          left: 0,
          right: 0,
          child: Center(
            child: _HintPill(
              text: 'Tap or drag to place the first point',
            ),
          ),
        ),
      );
    }

    // Style bar for selected shape.
    final selId = o.selectedId;
    if (selId != null) {
      DrawingShape? shape;
      for (final s in o.shapes) {
        if (s.id == selId) {
          shape = s;
          break;
        }
      }
      if (shape != null) {
        final s = shape;
        widgets.add(
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(
              child: DrawingStyleBar(
                shape: s,
                onStyleChanged: (style) {
                  _pushUndoBeforeMutation();
                  o.updateSelectedStyle(style);
                  _onShapesCommitted();
                },
                onDelete: () {
                  _pushUndoBeforeMutation();
                  o.deleteSelected();
                  _onShapesCommitted();
                },
              ),
            ),
          ),
        );
      }
    }

    return widgets;
  }
}

class _HintPill extends StatelessWidget {
  const _HintPill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xCC1A1A1A),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Text(
          text,
          style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 12),
        ),
      ),
    );
  }
}
