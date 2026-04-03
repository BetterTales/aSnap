import 'dart:ui';

import 'package:a_snap/utils/toolbar_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('computeFloatingToolbarAnchor', () {
    test('anchors below the selection when there is room', () {
      final anchor = computeFloatingToolbarAnchor(
        anchorRect: const Rect.fromLTWH(40, 60, 120, 80),
        screenSize: const Size(800, 600),
      );

      expect(anchor, const Offset(100, 148));
    });

    test('clamps horizontally and vertically into the viewport', () {
      final anchor = computeFloatingToolbarAnchor(
        anchorRect: const Rect.fromLTWH(760, 580, 120, 40),
        screenSize: const Size(800, 600),
      );

      expect(anchor, const Offset(792, 548));
    });

    test('handles very small screens without throwing', () {
      final anchor = computeFloatingToolbarAnchor(
        anchorRect: const Rect.fromLTWH(100, 50, 200, 120),
        screenSize: const Size(12, 10),
      );

      expect(anchor.dx, inInclusiveRange(8, 8));
      expect(anchor.dy, inInclusiveRange(8, 8));
    });
  });
}
