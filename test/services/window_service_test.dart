import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:a_snap/services/window_service.dart';

const _windowChannel = MethodChannel('com.asnap/window');
const _windowManagerChannel = MethodChannel('window_manager');

Future<void> _dispatchWindowCallback(
  String method,
  Map<String, Object?> arguments,
) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        _windowChannel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, arguments),
        ),
        (_) {},
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final windowService = WindowService();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowManagerChannel, (call) async {
          switch (call.method) {
            case 'isMinimized':
              return false;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowManagerChannel, null);
  });

  test('getLaunchAtLoginState falls back when plugin is unavailable', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowChannel, (call) async {
          throw MissingPluginException();
        });

    final state = await windowService.getLaunchAtLoginState();

    expect(state.supported, isFalse);
    expect(state.enabled, isFalse);
    expect(state.requiresApproval, isFalse);
  });

  test(
    'setLaunchAtLoginEnabled falls back when plugin is unavailable',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_windowChannel, (call) async {
            throw MissingPluginException();
          });

      final state = await windowService.setLaunchAtLoginEnabled(true);

      expect(state.supported, isFalse);
      expect(state.enabled, isFalse);
      expect(state.requiresApproval, isFalse);
    },
  );

  test(
    'startRectPolling forwards includeAxChildren false by default',
    () async {
      MethodCall? capturedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_windowChannel, (call) async {
            capturedCall = call;
            return null;
          });

      await windowService.startRectPolling();

      expect(capturedCall?.method, 'startRectPolling');
      expect(capturedCall?.arguments, {'includeAxChildren': false});
    },
  );

  test(
    'startRectPolling forwards includeAxChildren true when requested',
    () async {
      MethodCall? capturedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_windowChannel, (call) async {
            capturedCall = call;
            return null;
          });

      await windowService.startRectPolling(includeAxChildren: true);

      expect(capturedCall?.method, 'startRectPolling');
      expect(capturedCall?.arguments, {'includeAxChildren': true});
    },
  );

  test('revealInkOverlay forwards to the native window channel', () async {
    MethodCall? capturedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowChannel, (call) async {
          capturedCall = call;
          return null;
        });

    await windowService.revealInkOverlay();

    expect(capturedCall?.method, 'revealInkOverlay');
  });

  test('resetInkMonitorState forwards to the native window channel', () async {
    MethodCall? capturedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowChannel, (call) async {
          capturedCall = call;
          return null;
        });

    await windowService.resetInkMonitorState();

    expect(capturedCall?.method, 'resetInkMonitorState');
  });

  test('showToolbarPanel forwards placement intent and anchor rect', () async {
    MethodCall? capturedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowChannel, (call) async {
          capturedCall = call;
          return null;
        });

    await windowService.showToolbarPanel(
      request: const NativeToolbarRequest.belowAnchor(
        anchorRect: Rect.fromLTWH(12, 34, 56, 78),
        showPin: true,
        showHistoryControls: true,
        canUndo: false,
        canRedo: true,
        showOcr: true,
        activeTool: 'ellipse',
      ),
    );

    expect(capturedCall?.method, 'showToolbarPanel');
    final args = Map<String, dynamic>.from(capturedCall?.arguments as Map);
    expect(args['placement'], 'belowAnchor');
    expect(args['showPin'], isTrue);
    expect(args['showHistoryControls'], isTrue);
    expect(args['canUndo'], isFalse);
    expect(args['canRedo'], isTrue);
    expect(args['showOcr'], isTrue);
    expect(args['activeTool'], 'ellipse');
    expect(Map<String, dynamic>.from(args['anchorRect'] as Map), {
      'x': 12.0,
      'y': 34.0,
      'width': 56.0,
      'height': 78.0,
    });
  });

  test('showPreview flushes pending toolbar updates when visible', () async {
    final windowCalls = <MethodCall>[];
    final windowManagerCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowChannel, (call) async {
          windowCalls.add(call);
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowManagerChannel, (call) async {
          windowManagerCalls.add(call);
          switch (call.method) {
            case 'isMinimized':
              return false;
            default:
              return null;
          }
        });

    await windowService.showPreview(
      imageWidth: 100,
      imageHeight: 50,
      screenSize: const Size(1440, 900),
      screenOrigin: Offset.zero,
      focus: false,
    );

    expect(windowManagerCalls.map((call) => call.method), contains('show'));
    expect(
      windowCalls.map((call) => call.method),
      containsAll(['cleanupOverlayMode', 'flushPendingToolbarPanel']),
    );
  });

  test('showPreview does not flush toolbar when still transparent', () async {
    final windowCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowChannel, (call) async {
          windowCalls.add(call);
          return null;
        });

    await windowService.showPreview(
      imageWidth: 100,
      imageHeight: 50,
      screenSize: const Size(1440, 900),
      screenOrigin: Offset.zero,
      opacity: 0.0,
      focus: false,
    );

    expect(
      windowCalls.map((call) => call.method),
      isNot(contains('flushPendingToolbarPanel')),
    );
  });

  test('showScrollPreview keeps a fixed window size on Windows', () async {
    if (!Platform.isWindows) {
      return;
    }

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowChannel, (call) async {
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowManagerChannel, (call) async {
          switch (call.method) {
            case 'isMinimized':
              return false;
            default:
              return null;
          }
        });

    await windowService.showScrollPreview(
      imageWidth: 320,
      imageHeight: 2400,
      screenSize: const Size(1920, 1080),
      screenOrigin: Offset.zero,
      focus: false,
    );
    final firstRect = windowService.currentPreviewWindowRect;

    await windowService.showScrollPreview(
      imageWidth: 2000,
      imageHeight: 420,
      screenSize: const Size(1920, 1080),
      screenOrigin: Offset.zero,
      focus: false,
    );
    final secondRect = windowService.currentPreviewWindowRect;

    expect(firstRect, isNotNull);
    expect(secondRect, isNotNull);
    expect(secondRect!.size, firstRect!.size);
  });

  test('showPreview forwards native shadow preference', () async {
    final windowManagerCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowChannel, (call) async {
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowManagerChannel, (call) async {
          windowManagerCalls.add(call);
          switch (call.method) {
            case 'isMinimized':
              return false;
            default:
              return null;
          }
        });

    await windowService.showPreview(
      imageWidth: 100,
      imageHeight: 50,
      screenSize: const Size(1440, 900),
      screenOrigin: Offset.zero,
      focus: false,
      useNativeShadow: false,
    );

    expect(
      windowManagerCalls,
      contains(
        isA<MethodCall>()
            .having((call) => call.method, 'method', 'setHasShadow')
            .having((call) => call.arguments, 'arguments', <String, Object?>{
              'hasShadow': false,
            }),
      ),
    );
  });

  test('pinImage forwards native shadow preference', () async {
    MethodCall? capturedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowChannel, (call) async {
          capturedCall = call;
          return 12;
        });

    final panelId = await windowService.pinImage(
      bytes: Uint8List.fromList(List.filled(16, 255)),
      width: 2,
      height: 2,
      cgFrame: const Rect.fromLTWH(10, 20, 30, 40),
      useNativeShadow: false,
    );

    expect(panelId, 12);
    expect(capturedCall?.method, 'pinImage');
    final args = Map<String, dynamic>.from(capturedCall?.arguments as Map);
    expect(args['useNativeShadow'], isFalse);
    expect(args['frameX'], 10.0);
    expect(args['frameY'], 20.0);
    expect(args['frameWidth'], 30.0);
    expect(args['frameHeight'], 40.0);
  });

  test(
    'ensureInitialized forwards only current toolbar frame callbacks',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_windowChannel, (call) async {
            calls.add(call);
            return null;
          });

      await windowService.ensureInitialized();

      final updates = <NativeToolbarFrameUpdate>[];
      windowService.onToolbarFrameChanged = updates.add;

      await windowService.showToolbarPanel(
        request: const NativeToolbarRequest.belowWindow(
          showPin: false,
          showHistoryControls: true,
          canUndo: false,
          canRedo: false,
          showOcr: true,
        ),
      );

      final firstShowArgs = Map<String, dynamic>.from(
        calls.last.arguments as Map,
      );
      final firstRequestId = firstShowArgs['requestId'] as int;
      final sessionId = firstShowArgs['sessionId'] as int;

      await _dispatchWindowCallback('onToolbarFrameChanged', {
        'x': 10.0,
        'y': 20.0,
        'width': 30.0,
        'height': 44.0,
        'requestId': firstRequestId,
        'sessionId': sessionId,
      });

      expect(updates, hasLength(1));
      expect(updates.single.rect, const Rect.fromLTWH(10, 20, 30, 44));

      await windowService.hideToolbarPanel();
      await _dispatchWindowCallback('onToolbarFrameChanged', {
        'x': 99.0,
        'y': 88.0,
        'width': 77.0,
        'height': 44.0,
        'requestId': firstRequestId,
        'sessionId': sessionId,
      });

      expect(updates, hasLength(1));

      await windowService.showToolbarPanel(
        request: const NativeToolbarRequest.belowWindow(
          showPin: true,
          showHistoryControls: true,
          canUndo: true,
          canRedo: false,
          showOcr: true,
          activeTool: 'text',
        ),
      );

      final secondShowArgs = Map<String, dynamic>.from(
        calls.last.arguments as Map,
      );
      final secondRequestId = secondShowArgs['requestId'] as int;

      await _dispatchWindowCallback('onToolbarFrameChanged', {
        'x': 1.0,
        'y': 2.0,
        'width': 3.0,
        'height': 44.0,
        'requestId': secondRequestId,
        'sessionId': sessionId + 1,
      });

      expect(updates, hasLength(1));

      await _dispatchWindowCallback('onToolbarFrameChanged', {
        'x': 40.0,
        'y': 50.0,
        'width': 60.0,
        'height': 44.0,
        'requestId': secondRequestId,
        'sessionId': sessionId,
      });

      expect(updates, hasLength(2));
      expect(updates.last.rect, const Rect.fromLTWH(40, 50, 60, 44));
      expect(updates.last.requestId, secondRequestId);
      expect(updates.last.sessionId, sessionId);
    },
  );
}
