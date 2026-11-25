import 'package:flutter_test/flutter_test.dart';
import 'package:drezafx/chart/drawing/drawing_models.dart';
import 'package:drezafx/chart/drawing/undo_stack.dart';

void main() {
  group('DrawingShape JSON', () {
    test('round-trip', () {
      final s = DrawingShape(
        id: 'abc',
        type: DrawingType.trendline,
        points: const [
          DrawingPoint(time: 100, price: 1.2),
          DrawingPoint(time: 200, price: 1.3),
        ],
        style: const DrawingStyle(colorValue: 0xFF36A3FF, extendRight: true),
      );
      final json = s.toJson();
      final back = DrawingShape.tryFromJson(json);
      expect(back, isNotNull);
      expect(back!.id, 'abc');
      expect(back.type, DrawingType.trendline);
      expect(back.points.length, 2);
      expect(back.style.extendRight, isTrue);
    });

    test('corrupt input returns null', () {
      expect(DrawingShape.tryFromJson(null), isNull);
      expect(DrawingShape.tryFromJson({'id': 1}), isNull);
      expect(DrawingShape.tryFromJson({'id': 'x', 'type': 'nope'}), isNull);
      expect(
        DrawingShape.tryFromJson({
          'id': 'x',
          'type': 'trendline',
          'pts': [], // too few
        }),
        isNull,
      );
    });
  });

  group('DrawingUndoStack', () {
    test('undo / redo semantics', () {
      final stack = DrawingUndoStack(maxDepth: 5);
      final a = <DrawingShape>[];
      final b = [
        DrawingShape(
          id: '1',
          type: DrawingType.horizontalLine,
          points: const [DrawingPoint(time: 1, price: 1)],
          style: const DrawingStyle(),
        ),
      ];

      stack.push(a);
      expect(stack.canUndo, isTrue);
      final prev = stack.undo(b);
      expect(prev, isEmpty);
      expect(stack.canRedo, isTrue);
      final next = stack.redo(prev!);
      expect(next!.length, 1);
    });
  });
}
