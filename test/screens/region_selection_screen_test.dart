import 'dart:ui' as ui;

import 'package:a_snap/screens/region_selection_screen.dart';
import 'package:a_snap/services/window_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeWindowService extends WindowService {
  @override
  Future<void> showToolbarPanel({
    required NativeToolbarRequest request,
  }) async {}

  @override
  Future<void> hideToolbarPanel() async {}
}

const _windowManagerChannel = MethodChannel('window_manager');

Future<ui.Image> _createTestImage({int width = 240, int height = 160}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF4A90E2),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

dynamic _selectionPainter(WidgetTester tester) {
  for (final customPaint in tester.widgetList<CustomPaint>(
    find.byType(CustomPaint),
  )) {
    final painter = customPaint.painter;
    if (painter != null &&
        painter.runtimeType.toString() == '_SelectionPainter') {
      return painter;
    }
  }
  fail('Selection painter not found');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowManagerChannel, (call) async {
          switch (call.method) {
            case 'focus':
              return true;
            case 'isFocused':
              return true;
            default:
              return null;
          }
        });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowManagerChannel, null);
  });

  testWidgets('does not draw crosshair until pointer position is known', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final image = await _createTestImage();
    addTearDown(image.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(
          child: RegionSelectionScreen(
            decodedImage: image,
            windowRects: const [],
            onCancel: () {},
            windowService: _FakeWindowService(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(_selectionPainter(tester).isDrawing, isFalse);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(100, 100));
    await tester.pump();
    await mouse.moveTo(const Offset(120, 120));
    await tester.pump();

    expect(_selectionPainter(tester).isDrawing, isTrue);
  });
}
