import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'package:a_snap/screens/ink_overlay_screen.dart';
import 'package:a_snap/state/app_state.dart';
import 'package:a_snap/state/ink_state.dart';
import 'package:a_snap/state/laser_state.dart';
import 'package:a_snap/widgets/laser_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  HotKey testHotKey({
    required String identifier,
    required PhysicalKeyboardKey key,
  }) {
    return HotKey(identifier: identifier, key: key, scope: HotKeyScope.inapp);
  }

  testWidgets(
    'ink overlay receives pointer events while laser overlay is inactive',
    (tester) async {
      final inkState = InkState();
      final laserState = LaserState();

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox.expand(
            child: InkOverlayScreen(
              inkState: inkState,
              laserState: laserState,
              drawingEnabled: true,
              tool: InkTool.ink,
              inkHotKey: testHotKey(
                identifier: 'ink',
                key: PhysicalKeyboardKey.keyI,
              ),
              laserHotKey: testHotKey(
                identifier: 'laser',
                key: PhysicalKeyboardKey.keyL,
              ),
              onInkKeyDown: () {},
              onInkKeyUp: () {},
              onLaserKeyDown: () {},
              onLaserKeyUp: () {},
              strokeColor: Colors.red,
              strokeWidth: 6,
              smoothingTolerance: 0,
              autoFadeSeconds: 0,
              eraserSize: 12,
              laserColor: Colors.green,
              laserSize: 20,
              laserFadeSeconds: 1,
              onEraserSizeChanged: (_) {},
              onExitRequested: () async {},
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(const Offset(100, 100));
      await tester.pump();
      await gesture.moveTo(const Offset(160, 140));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(inkState.strokes, hasLength(1));
      expect(inkState.strokes.single.points.length, greaterThan(1));
      expect(laserState.samples, isEmpty);
    },
  );

  testWidgets('laser overlay separates samples across distinct drags', (
    tester,
  ) async {
    final inkState = InkState();
    final laserState = LaserState();

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(
          child: InkOverlayScreen(
            inkState: inkState,
            laserState: laserState,
            drawingEnabled: true,
            tool: InkTool.laser,
            inkHotKey: testHotKey(
              identifier: 'ink',
              key: PhysicalKeyboardKey.keyI,
            ),
            laserHotKey: testHotKey(
              identifier: 'laser',
              key: PhysicalKeyboardKey.keyL,
            ),
            onInkKeyDown: () {},
            onInkKeyUp: () {},
            onLaserKeyDown: () {},
            onLaserKeyUp: () {},
            strokeColor: Colors.red,
            strokeWidth: 6,
            smoothingTolerance: 0,
            autoFadeSeconds: 0,
            eraserSize: 12,
            laserColor: Colors.green,
            laserSize: 20,
            laserFadeSeconds: 1,
            onEraserSizeChanged: (_) {},
            onExitRequested: () async {},
          ),
        ),
      ),
    );

    final firstDrag = await tester.startGesture(const Offset(100, 100));
    await tester.pump();
    await firstDrag.moveTo(const Offset(160, 140));
    await tester.pump();
    await firstDrag.up();
    await tester.pump();

    final secondDrag = await tester.startGesture(const Offset(240, 220));
    await tester.pump();
    await secondDrag.moveTo(const Offset(300, 260));
    await tester.pump();
    await secondDrag.up();
    await tester.pump();

    expect(inkState.strokes, isEmpty);
    expect(laserState.samples.length, greaterThan(2));
    expect(
      laserState.samples.map((sample) => sample.strokeId).toSet(),
      hasLength(2),
    );
  });

  testWidgets('laser overlay does not record hover movement while active', (
    tester,
  ) async {
    final inkState = InkState();
    final laserState = LaserState();

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(
          child: InkOverlayScreen(
            inkState: inkState,
            laserState: laserState,
            drawingEnabled: true,
            tool: InkTool.laser,
            inkHotKey: testHotKey(
              identifier: 'ink',
              key: PhysicalKeyboardKey.keyI,
            ),
            laserHotKey: testHotKey(
              identifier: 'laser',
              key: PhysicalKeyboardKey.keyL,
            ),
            onInkKeyDown: () {},
            onInkKeyUp: () {},
            onLaserKeyDown: () {},
            onLaserKeyUp: () {},
            strokeColor: Colors.red,
            strokeWidth: 6,
            smoothingTolerance: 0,
            autoFadeSeconds: 0,
            eraserSize: 12,
            laserColor: Colors.green,
            laserSize: 20,
            laserFadeSeconds: 1,
            onEraserSizeChanged: (_) {},
            onExitRequested: () async {},
          ),
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    final laserPaintFinder = find.descendant(
      of: find.byType(LaserOverlay),
      matching: find.byType(CustomPaint),
    );

    await mouse.addPointer(location: const Offset(100, 100));
    await tester.pump();
    final firstPaint = tester.widget<CustomPaint>(laserPaintFinder);
    await mouse.moveTo(const Offset(160, 140));
    await tester.pump();
    final secondPaint = tester.widget<CustomPaint>(laserPaintFinder);
    await mouse.moveTo(const Offset(220, 180));
    await tester.pump();

    expect(inkState.strokes, isEmpty);
    expect(laserState.samples, isEmpty);
    expect(identical(firstPaint.painter, secondPaint.painter), isFalse);
  });

  testWidgets('laser overlay repaints while dragging with primary button', (
    tester,
  ) async {
    final inkState = InkState();
    final laserState = LaserState();

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(
          child: InkOverlayScreen(
            inkState: inkState,
            laserState: laserState,
            drawingEnabled: true,
            tool: InkTool.laser,
            inkHotKey: testHotKey(
              identifier: 'ink',
              key: PhysicalKeyboardKey.keyI,
            ),
            laserHotKey: testHotKey(
              identifier: 'laser',
              key: PhysicalKeyboardKey.keyL,
            ),
            onInkKeyDown: () {},
            onInkKeyUp: () {},
            onLaserKeyDown: () {},
            onLaserKeyUp: () {},
            strokeColor: Colors.red,
            strokeWidth: 6,
            smoothingTolerance: 0,
            autoFadeSeconds: 0,
            eraserSize: 12,
            laserColor: Colors.green,
            laserSize: 20,
            laserFadeSeconds: 1,
            onEraserSizeChanged: (_) {},
            onExitRequested: () async {},
          ),
        ),
      ),
    );

    final laserPaintFinder = find.descendant(
      of: find.byType(LaserOverlay),
      matching: find.byType(CustomPaint),
    );

    final drag = await tester.startGesture(const Offset(100, 100));
    await tester.pump();
    final firstPaint = tester.widget<CustomPaint>(laserPaintFinder);
    await drag.moveTo(const Offset(160, 140));
    await tester.pump();
    final secondPaint = tester.widget<CustomPaint>(laserPaintFinder);
    await drag.up();
    await tester.pump();

    expect(inkState.strokes, isEmpty);
    expect(laserState.samples.length, greaterThanOrEqualTo(2));
    expect(identical(firstPaint.painter, secondPaint.painter), isFalse);
  });
}
