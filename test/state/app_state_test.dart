import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:a_snap/state/app_state.dart';

/// Create a simple 1x1 test image using PictureRecorder.
Future<Image> _createTestImage() async {
  final recorder = PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 1, 1),
    Paint()..color = const Color(0xFFFF0000),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(1, 1);
  picture.dispose();
  return image;
}

Future<void> _expectImageUsable(WidgetTester tester, Image image) async {
  final byteData = await tester.runAsync(
    () => image.toByteData(format: ImageByteFormat.png),
  );
  expect(byteData, isNotNull);
}

void main() {
  late AppState state;

  setUp(() {
    state = AppState();
  });

  tearDown(() {
    state.clear();
  });

  group('initial state', () {
    test('starts idle with null fields', () {
      expect(state.status, CaptureStatus.idle);
      expect(state.workflow, isA<IdleWorkflow>());
      expect(state.capturedImage, isNull);
      expect(state.decodedFullScreen, isNull);
      expect(state.windowRects, isNull);
      expect(state.screenSize, isNull);
      expect(state.screenOrigin, isNull);
    });
  });

  group('setPreparingCapture', () {
    test('transitions to capturing and notifies', () {
      var notified = false;
      state.addListener(() => notified = true);

      state.setPreparingCapture(kind: CaptureKind.region);

      expect(state.status, CaptureStatus.capturing);
      expect(state.workflow, isA<PreparingCaptureWorkflow>());
      expect(notified, isTrue);
    });
  });

  group('setCapturedImage', () {
    testWidgets('stores image and transitions to captured', (tester) async {
      final image = await _createTestImage();
      state.setCapturedImage(image);

      expect(state.status, CaptureStatus.captured);
      expect(state.workflow, isA<PreviewWorkflow>());
      expect(state.capturedImage, isNotNull);
      expect(state.decodedFullScreen, isNull);
      expect(state.windowRects, isNull);
      expect(state.screenSize, isNull);
      expect(state.screenOrigin, isNull);
    });
  });

  group('detach image lifecycle', () {
    testWidgets('detachCapturedImage keeps image usable after clear', (
      tester,
    ) async {
      final image = await _createTestImage();
      state.setCapturedImage(image);

      final detached = state.detachCapturedImage();
      expect(detached, same(image));

      state.clear();

      expect(state.capturedImage, isNull);
      await _expectImageUsable(tester, detached!);
      detached.dispose();
    });

    testWidgets(
      'detachCapturedImage keeps old image alive across replacement',
      (tester) async {
        final image = await _createTestImage();
        state.setCapturedImage(image);

        final detached = state.detachCapturedImage();
        final replacement = await _createTestImage();
        state.setCapturedImage(replacement);

        expect(state.capturedImage, same(replacement));
        await _expectImageUsable(tester, detached!);
        detached.dispose();
      },
    );

    testWidgets('detachDecodedFullScreen keeps image usable after clear', (
      tester,
    ) async {
      final image = await _createTestImage();
      state.setSelecting(
        decodedImage: image,
        windowRects: const [],
        screenSize: const Size(1280, 720),
        screenOrigin: const Offset(10, 20),
      );

      final detached = state.detachDecodedFullScreen();
      expect(detached, same(image));

      state.clear();

      expect(state.decodedFullScreen, isNull);
      await _expectImageUsable(tester, detached!);
      detached.dispose();
    });
  });

  group('updateWindowRects', () {
    testWidgets('updates rects and notifies', (tester) async {
      var notified = false;
      state.addListener(() => notified = true);

      final image = await _createTestImage();
      state.setSelecting(
        decodedImage: image,
        windowRects: const [],
        screenSize: const Size(1280, 720),
        screenOrigin: const Offset(10, 20),
      );

      notified = false;
      final rects = [const Rect.fromLTWH(0, 0, 100, 100)];
      state.updateWindowRects(rects);

      expect(state.windowRects, rects);
      expect(notified, isTrue);
    });
  });

  group('selection workflow', () {
    testWidgets('stores selection payload in typed workflow', (tester) async {
      final image = await _createTestImage();
      final rects = [const Rect.fromLTWH(0, 0, 100, 100)];
      const screenSize = Size(1920, 1080);
      const screenOrigin = Offset(100, 200);
      state.setSelecting(
        decodedImage: image,
        windowRects: rects,
        screenSize: screenSize,
        screenOrigin: screenOrigin,
      );

      expect(state.windowRects, rects);
      expect(state.workflow, isA<RegionSelectionWorkflow>());
      expect(state.screenSize, screenSize);
      expect(state.screenOrigin, screenOrigin);
    });
  });

  group('scroll workflow edges', () {
    test('setScrollCapturing is a no-op without selection context', () {
      state.setScrollCapturing(
        captureRegion: const Rect.fromLTWH(0, 0, 100, 100),
      );

      expect(state.workflow, isA<IdleWorkflow>());
      expect(state.status, CaptureStatus.idle);
    });

    testWidgets(
      'setScrollResult falls back to preview when screen context is missing',
      (tester) async {
        final image = await _createTestImage();

        state.setScrollResult(image);

        expect(state.workflow, isA<PreviewWorkflow>());
        expect(state.status, CaptureStatus.captured);
        expect(state.isScrollCapture, isTrue);
        expect(state.capturedImage, same(image));
      },
    );

    testWidgets(
      'updateScrollPreview updates image without notifying listeners',
      (tester) async {
        final image = await _createTestImage();
        state.setScrollSelecting(
          decodedImage: image,
          windowRects: const [],
          screenSize: const Size(800, 600),
          screenOrigin: const Offset(20, 30),
        );
        state.setScrollCapturing(
          captureRegion: const Rect.fromLTWH(25, 35, 300, 200),
        );

        var notifications = 0;
        state.addListener(() => notifications++);

        final preview = await _createTestImage();
        state.updateScrollPreview(preview);

        expect(state.scrollPreviewImage, same(preview));
        expect(notifications, 0);

        state.clear();
        preview.dispose();
      },
    );
  });

  group('nudge', () {
    test('notifies listeners without changing state', () {
      var notifyCount = 0;
      state.addListener(() => notifyCount++);

      state.nudge();

      expect(notifyCount, 1);
      expect(state.status, CaptureStatus.idle);
    });
  });

  group('clear', () {
    testWidgets('resets all fields to initial state', (tester) async {
      final image = await _createTestImage();
      state.setCapturedImage(image);
      expect(state.status, CaptureStatus.captured);

      state.clear();

      expect(state.status, CaptureStatus.idle);
      expect(state.workflow, isA<IdleWorkflow>());
      expect(state.capturedImage, isNull);
      expect(state.decodedFullScreen, isNull);
      expect(state.windowRects, isNull);
      expect(state.screenSize, isNull);
      expect(state.screenOrigin, isNull);
    });
  });

  group('capturedImageAsPng', () {
    testWidgets('returns PNG bytes from captured image', (tester) async {
      final image = await _createTestImage();
      state.setCapturedImage(image);

      // toByteData(format: png) is a real engine call — needs runAsync.
      final png = await tester.runAsync(() => state.capturedImageAsPng());

      expect(png, isNotNull);
      // PNG magic bytes
      expect(png!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    });

    test('returns null when no image captured', () async {
      final png = await state.capturedImageAsPng();
      expect(png, isNull);
    });
  });

  group('state machine transitions', () {
    testWidgets('idle → capturing → captured → idle', (tester) async {
      expect(state.status, CaptureStatus.idle);

      state.setPreparingCapture(kind: CaptureKind.fullScreen);
      expect(state.status, CaptureStatus.capturing);

      final image = await _createTestImage();
      state.setCapturedImage(image);
      expect(state.status, CaptureStatus.captured);

      state.clear();
      expect(state.status, CaptureStatus.idle);
    });

    testWidgets('scroll selection → scroll capturing → scroll result', (
      tester,
    ) async {
      final image = await _createTestImage();
      state.setScrollSelecting(
        decodedImage: image,
        windowRects: const [Rect.fromLTWH(0, 0, 100, 100)],
        screenSize: const Size(800, 600),
        screenOrigin: const Offset(20, 30),
      );

      expect(state.workflow, isA<RegionSelectionWorkflow>());
      expect(state.status, CaptureStatus.scrollSelecting);

      state.setScrollCapturing(
        captureRegion: const Rect.fromLTWH(25, 35, 300, 200),
      );
      expect(state.workflow, isA<ScrollCapturingWorkflow>());
      expect(state.status, CaptureStatus.scrollCapturing);
      expect(state.screenOrigin, const Offset(20, 30));

      final result = await _createTestImage();
      state.setScrollResult(result);

      expect(state.workflow, isA<ScrollResultWorkflow>());
      expect(state.status, CaptureStatus.scrollResult);
      expect(state.screenSize, const Size(800, 600));
      expect(state.screenOrigin, const Offset(20, 30));
    });
  });
}
