import 'dart:ui';

import 'package:a_snap/utils/toolbar_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('computeToolbarRect', () {
    test('does not throw when screen is narrower than toolbar', () {
      final rect = computeToolbarRect(
        anchorRect: const Rect.fromLTWH(100, 50, 200, 120),
        screenSize: const Size(400, 300),
      );

      expect(rect.left, 0.0);
      expect(rect.width, kToolbarSize.width);
      expect(rect.height, kToolbarSize.height);
    });
  });

  group('computeToolbarRectBelowWindow', () {
    test('does not throw when screen is narrower than toolbar', () {
      final rect = computeToolbarRectBelowWindow(
        windowRect: const Rect.fromLTWH(100, 100, 240, 180),
        screenRect: const Rect.fromLTWH(0, 0, 400, 300),
      );

      expect(rect.left, 0.0);
      expect(rect.width, kToolbarSize.width);
      expect(rect.height, kToolbarSize.height);
    });
  });
}
