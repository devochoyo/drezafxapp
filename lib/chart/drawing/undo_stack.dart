import 'drawing_models.dart';

/// Undo/redo stack for drawing edits. Depth capped at [maxDepth].
class DrawingUndoStack {
  DrawingUndoStack({this.maxDepth = 50});

  final int maxDepth;

  final List<List<DrawingShape>> _undo = [];
  final List<List<DrawingShape>> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Push a snapshot of the current shapes *before* a mutation.
  void push(List<DrawingShape> snapshot) {
    _undo.add(_clone(snapshot));
    if (_undo.length > maxDepth) {
      _undo.removeAt(0);
    }
    _redo.clear();
  }

  /// Returns the previous snapshot, or null.
  List<DrawingShape>? undo(List<DrawingShape> current) {
    if (_undo.isEmpty) return null;
    _redo.add(_clone(current));
    return _undo.removeLast();
  }

  List<DrawingShape>? redo(List<DrawingShape> current) {
    if (_redo.isEmpty) return null;
    _undo.add(_clone(current));
    return _redo.removeLast();
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }

  static List<DrawingShape> _clone(List<DrawingShape> src) =>
      List<DrawingShape>.from(src);
}
