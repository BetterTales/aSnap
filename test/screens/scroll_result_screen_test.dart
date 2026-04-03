import 'dart:ui' as ui;

import 'package:a_snap/models/capture_style_settings.dart';
import 'package:a_snap/screens/scroll_result_screen.dart';
import 'package:a_snap/services/window_service.dart';
import 'package:a_snap/state/annotation_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeWindowService extends WindowService {
  @override
  Future<void> showToolbarPanel({
    required NativeToolbarRequest request,
  }) async {}

  @override
  Future<void> hideToolbarPanel() async {}
}

Future<ui.Image> _createTestImage({int width = 300, int height = 2200}) async {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tall scroll results remain scrollable in preview', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final image = await _createTestImage();
    final annotationState = AnnotationState();

    addTearDown(image.dispose);
    addTearDown(annotationState.clear);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(
          child: ScrollResultScreen(
            stitchedImage: image,
            annotationState: annotationState,
            windowService: _FakeWindowService(),
            onCopy: () {},
            onSave: () {},
            onDiscard: () {},
            onOcr: () {},
            onCopyText: (_) {},
            captureStyle: const CaptureStyleSettings.defaults(),
            captureScale: 1.0,
            showCaptureStyleChrome: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final scrollViewFinder = find.byType(SingleChildScrollView);
    expect(scrollViewFinder, findsOneWidget);
    final scrollView = tester.widget<SingleChildScrollView>(scrollViewFinder);
    final controller = scrollView.controller;
    expect(controller, isNotNull);
    expect(controller!.offset, 0.0);

    await tester.drag(scrollViewFinder, const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
  });
}
