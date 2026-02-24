import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:a_snap/models/annotation.dart';
import 'package:a_snap/state/annotation_state.dart';

void main() {
  group('placeStamp', () {
    test('places first stamp with label 1', () {
      final state = AnnotationState();
      state.placeStamp(const Offset(50, 50));
      expect(state.annotations.length, 1);
      expect(state.annotations[0].type, ShapeType.number);
      expect(state.annotations[0].label, 1);
      expect(state.annotations[0].start, const Offset(50, 50));
    });

    test('auto-increments label', () {
      final state = AnnotationState();
      state.placeStamp(const Offset(50, 50));
      state.placeStamp(const Offset(100, 100));
      state.placeStamp(const Offset(150, 150));
      expect(state.annotations[0].label, 1);
      expect(state.annotations[1].label, 2);
      expect(state.annotations[2].label, 3);
    });

    test('undo removes stamp and next reuses number', () {
      final state = AnnotationState();
      state.placeStamp(const Offset(50, 50));
      state.placeStamp(const Offset(100, 100));
      state.placeStamp(const Offset(150, 150));
      expect(state.annotations.length, 3);

      state.undo(); // removes #3
      expect(state.annotations.length, 2);

      state.placeStamp(const Offset(200, 200));
      expect(state.annotations.last.label, 3); // reuses 3
    });

    test('delete leaves gaps — next uses highest + 1', () {
      final state = AnnotationState();
      state.placeStamp(const Offset(50, 50));
      state.placeStamp(const Offset(100, 100));
      state.placeStamp(const Offset(150, 150));

      // Delete #2 (label=2)
      state.selectAnnotation(1);
      state.deleteSelected();
      // Remaining: label 1, label 3
      expect(state.annotations.length, 2);

      state.placeStamp(const Offset(200, 200));
      expect(state.annotations.last.label, 4); // highest (3) + 1
    });

    test('stamp is auto-selected after placement', () {
      final state = AnnotationState();
      state.placeStamp(const Offset(50, 50));
      expect(state.selectedIndex, 0);
      state.placeStamp(const Offset(100, 100));
      expect(state.selectedIndex, 1);
    });

    test('stamp uses current settings color and strokeWidth', () {
      final state = AnnotationState();
      state.updateSettings(
        const DrawingSettings(color: Color(0xFF00FF00), strokeWidth: 8),
      );
      state.placeStamp(const Offset(50, 50));
      expect(state.annotations[0].color, const Color(0xFF00FF00));
      expect(state.annotations[0].strokeWidth, 8);
    });
  });

  group('selection', () {
    test('initially no selection', () {
      final state = AnnotationState();
      expect(state.selectedIndex, isNull);
      expect(state.selectedAnnotation, isNull);
    });

    test('selectAnnotation sets selectedIndex', () {
      final state = AnnotationState();
      state.startDrawing(Offset.zero);
      state.updateDrawing(const Offset(100, 100));
      state.finishDrawing();
      state.selectAnnotation(0);
      expect(state.selectedIndex, 0);
      expect(state.selectedAnnotation, isNotNull);
    });

    test('deselectAnnotation clears selection', () {
      final state = AnnotationState();
      state.startDrawing(Offset.zero);
      state.updateDrawing(const Offset(100, 100));
      state.finishDrawing();
      state.selectAnnotation(0);
      state.deselectAnnotation();
      expect(state.selectedIndex, isNull);
    });

    test('deleteSelected removes shape and clears selection', () {
      final state = AnnotationState();
      state.startDrawing(Offset.zero);
      state.updateDrawing(const Offset(100, 100));
      state.finishDrawing();
      expect(state.annotations.length, 1);
      state.selectAnnotation(0);
      state.deleteSelected();
      expect(state.annotations.length, 0);
      expect(state.selectedIndex, isNull);
    });

    test('deleteSelected supports undo', () {
      final state = AnnotationState();
      state.startDrawing(Offset.zero);
      state.updateDrawing(const Offset(100, 100));
      state.finishDrawing();
      state.selectAnnotation(0);
      state.deleteSelected();
      expect(state.annotations.length, 0);
      state.undo();
      expect(state.annotations.length, 1);
    });

    test('undo clears selection', () {
      final state = AnnotationState();
      state.startDrawing(Offset.zero);
      state.updateDrawing(const Offset(100, 100));
      state.finishDrawing();
      state.selectAnnotation(0);
      state.undo();
      expect(state.selectedIndex, isNull);
    });
  });

  group('beginEdit / commitEdit', () {
    test('single undo entry for entire drag gesture', () {
      final state = AnnotationState();
      state.startDrawing(Offset.zero);
      state.updateDrawing(const Offset(100, 100));
      state.finishDrawing();
      state.selectAnnotation(0);

      state.beginEdit();
      // Simulate multiple drag updates.
      state.updateSelected(
        state.selectedAnnotation!.withEnd(const Offset(110, 110)),
      );
      state.updateSelected(
        state.selectedAnnotation!.withEnd(const Offset(120, 120)),
      );
      state.updateSelected(
        state.selectedAnnotation!.withEnd(const Offset(130, 130)),
      );
      state.commitEdit();

      expect(state.annotations[0].end, const Offset(130, 130));
      // One undo should revert to original.
      state.undo();
      expect(state.annotations[0].end, const Offset(100, 100));
    });

    test('updateSelected without beginEdit is no-op', () {
      final state = AnnotationState();
      state.startDrawing(Offset.zero);
      state.updateDrawing(const Offset(100, 100));
      state.finishDrawing();
      state.selectAnnotation(0);
      // No beginEdit — updateSelected should be ignored
      state.updateSelected(
        state.selectedAnnotation!.withEnd(const Offset(200, 200)),
      );
      expect(state.annotations[0].end, const Offset(100, 100));
    });
  });

  group('finishDrawing auto-selects', () {
    test('new shape is auto-selected after drawing', () {
      final state = AnnotationState();
      state.startDrawing(Offset.zero);
      state.updateDrawing(const Offset(100, 100));
      state.finishDrawing();
      expect(state.selectedIndex, 0);
    });
  });
}
