import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'package:a_snap/models/capture_style_settings.dart';
import 'package:a_snap/models/shortcut_bindings.dart';
import 'package:a_snap/screens/settings_screen.dart';
import 'package:a_snap/services/hotkey_service.dart';
import 'package:a_snap/services/settings_service.dart';
import 'package:a_snap/services/tray_service.dart';
import 'package:a_snap/services/window_service.dart';
import 'package:a_snap/state/settings_state.dart';
import 'package:a_snap/utils/ink_defaults.dart';
import 'package:a_snap/utils/laser_defaults.dart';

class _FakeSettingsService extends SettingsService {
  _FakeSettingsService() : super();

  ShortcutBindings? savedShortcuts;
  bool? savedOcrPreviewEnabled;
  bool? savedOcrOpenUrlPromptEnabled;
  int? savedCaptureDelaySeconds;
  CaptureStyleSettings? savedCaptureStyle;

  @override
  Future<void> saveShortcutBindings(ShortcutBindings bindings) async {
    savedShortcuts = bindings;
  }

  @override
  Future<void> saveOcrPreviewEnabled(bool enabled) async {
    savedOcrPreviewEnabled = enabled;
  }

  @override
  Future<void> saveOcrOpenUrlPromptEnabled(bool enabled) async {
    savedOcrOpenUrlPromptEnabled = enabled;
  }

  @override
  Future<void> saveCaptureDelaySeconds(int seconds) async {
    savedCaptureDelaySeconds = seconds;
  }

  @override
  Future<void> saveCaptureStyle(CaptureStyleSettings style) async {
    savedCaptureStyle = style;
  }

  @override
  Future<void> saveInkColor(Color color) async {}

  @override
  Future<void> saveInkStrokeWidth(double width) async {}

  @override
  Future<void> saveInkSmoothingTolerance(double tolerance) async {}

  @override
  Future<void> saveInkAutoFadeSeconds(double seconds) async {}

  @override
  Future<void> saveInkEraserSize(double size) async {}

  @override
  Future<void> saveLaserColor(Color color) async {}

  @override
  Future<void> saveLaserSize(double size) async {}

  @override
  Future<void> saveLaserFadeSeconds(double seconds) async {}
}

class _FakeWindowService extends WindowService {
  @override
  Future<void> setInkShortcut(HotKey hotKey) async {}

  @override
  Future<void> setLaserShortcut(HotKey hotKey) async {}
}

class _FakeHotkeyService extends HotkeyService {
  final List<ShortcutBindings> updates = [];

  @override
  Future<void> updateBindings(ShortcutBindings bindings) async {
    updates.add(bindings);
  }
}

class _FakeTrayService extends TrayService {
  final List<ShortcutBindings> updates = [];

  @override
  Future<void> updateShortcuts(ShortcutBindings shortcuts) async {
    updates.add(shortcuts);
  }
}

class _SettingsHarness {
  _SettingsHarness({
    required this.state,
    required this.settingsService,
    required this.hotkeyService,
    required this.trayService,
  });

  final SettingsState state;
  final _FakeSettingsService settingsService;
  final _FakeHotkeyService hotkeyService;
  final _FakeTrayService trayService;
}

ShortcutBindings _customShortcuts() {
  final primaryModifier = Platform.isMacOS
      ? HotKeyModifier.meta
      : HotKeyModifier.control;
  return ShortcutBindings.defaults().copyWithAction(
    ShortcutAction.region,
    HotKey(
      identifier: ShortcutAction.region.id,
      key: PhysicalKeyboardKey.keyR,
      modifiers: [primaryModifier, HotKeyModifier.shift],
      scope: HotKeyScope.system,
    ),
  );
}

Future<_SettingsHarness> _pumpSettingsScreen(
  WidgetTester tester, {
  ShortcutBindings? initialShortcuts,
  ThemeMode themeMode = ThemeMode.light,
}) async {
  final settingsService = _FakeSettingsService();
  final hotkeyService = _FakeHotkeyService();
  final trayService = _FakeTrayService();
  final state = SettingsState(
    initialShortcuts: initialShortcuts ?? ShortcutBindings.defaults(),
    initialOcrPreviewEnabled: false,
    initialOcrOpenUrlPromptEnabled: true,
    initialCaptureDelaySeconds: 0,
    initialCaptureStyle: const CaptureStyleSettings.defaults(),
    initialInkColor: kInkDefaultColor,
    initialInkStrokeWidth: kInkDefaultStrokeWidth,
    initialInkSmoothingTolerance: kInkDefaultSmoothingTolerance,
    initialInkAutoFadeSeconds: kInkDefaultAutoFadeSeconds,
    initialInkEraserSize: kInkDefaultEraserSize,
    initialLaserColor: kLaserDefaultColor,
    initialLaserSize: kLaserDefaultSize,
    initialLaserFadeSeconds: kLaserDefaultFadeSeconds,
    settingsService: settingsService,
    windowService: _FakeWindowService(),
    hotkeyService: hotkeyService,
    trayService: trayService,
  );

  await tester.binding.setSurfaceSize(const Size(900, 620));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: themeMode,
      home: SettingsScreen(
        settingsState: state,
        onClose: () async {},
        onSuspendHotkeys: () async {},
        onResumeHotkeys: () async {},
      ),
    ),
  );
  await tester.pumpAndSettle();

  return _SettingsHarness(
    state: state,
    settingsService: settingsService,
    hotkeyService: hotkeyService,
    trayService: trayService,
  );
}

Finder _tabLabel(String label) => find.widgetWithText(Tab, label);

void main() {
  const shortcutRecorderChannel = MethodChannel('com.asnap/shortcutRecorder');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shortcutRecorderChannel, (call) async {
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shortcutRecorderChannel, null);
  });

  testWidgets('settings screen renders in tabs', (tester) async {
    await _pumpSettingsScreen(tester);

    expect(find.text('Settings'), findsOneWidget);
    expect(_tabLabel('General'), findsOneWidget);
    expect(_tabLabel('Capture'), findsOneWidget);
    expect(_tabLabel('Shortcuts'), findsOneWidget);
    expect(_tabLabel('Ink'), findsOneWidget);
    expect(_tabLabel('Laser'), findsOneWidget);
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('Launch at login'), findsOneWidget);
    expect(find.text('Show OCR preview'), findsOneWidget);
    expect(find.text('Prompt to open URL after OCR'), findsOneWidget);
    expect(find.text('Region'), findsNothing);
    expect(find.text('Border radius'), findsNothing);
    expect(find.text('Smoothing'), findsNothing);
    expect(find.text('Fade'), findsNothing);

    await tester.tap(_tabLabel('Capture'));
    await tester.pumpAndSettle();

    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('Delay'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('3s'), findsOneWidget);
    expect(find.text('5s'), findsOneWidget);
    expect(find.text('10s'), findsOneWidget);
    expect(find.text('Border radius'), findsOneWidget);
    expect(find.text('Padding'), findsOneWidget);
    expect(find.text('Shadow'), findsOneWidget);
    expect(find.byKey(const Key('capture-style-preview')), findsOneWidget);
    expect(
      find.byKey(const Key('capture-style-preview-matte')),
      findsOneWidget,
    );

    await tester.tap(_tabLabel('Shortcuts'));
    await tester.pumpAndSettle();

    expect(find.text('Region'), findsOneWidget);
    expect(find.text('Scroll'), findsOneWidget);
    expect(find.text('Full Screen'), findsOneWidget);
    expect(find.text('Pin'), findsOneWidget);
    expect(find.text('OCR'), findsOneWidget);
    expect(find.text('Ink'), findsAtLeastNWidgets(1));
    expect(find.text('Laser'), findsAtLeastNWidgets(1));

    await tester.tap(_tabLabel('Ink'));
    await tester.pumpAndSettle();

    expect(find.text('Smoothing'), findsOneWidget);
    expect(find.text('Auto-fade'), findsOneWidget);
    expect(find.text('Eraser size'), findsOneWidget);

    await tester.tap(_tabLabel('Laser'));
    await tester.pumpAndSettle();

    expect(find.text('Fade'), findsOneWidget);
    expect(find.text('Save changes'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings screen preserves dark theme colors', (tester) async {
    await _pumpSettingsScreen(tester, themeMode: ThemeMode.dark);

    final dividers = tester.widgetList<Divider>(find.byType(Divider)).toList();

    expect(dividers, isNotEmpty);
    for (final divider in dividers) {
      expect(divider.color, const Color(0xFF48484A));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('capture tab places preview to the right on desktop widths', (
    tester,
  ) async {
    await _pumpSettingsScreen(tester);

    await tester.tap(_tabLabel('Capture'));
    await tester.pumpAndSettle();

    final previewPosition = tester.getTopLeft(find.text('Preview'));
    final controlsPosition = tester.getTopLeft(find.text('Border radius'));

    expect(previewPosition.dx, greaterThan(controlsPosition.dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('capture delay presets persist immediately', (tester) async {
    final harness = await _pumpSettingsScreen(tester);

    await tester.tap(_tabLabel('Capture'));
    await tester.pumpAndSettle();

    final segmentedButton = tester.widget<SegmentedButton<int>>(
      find.byWidgetPredicate((widget) => widget is SegmentedButton<int>),
    );
    segmentedButton.onSelectionChanged!({5});
    await tester.pumpAndSettle();

    expect(harness.state.captureDelaySeconds, 5);
    expect(harness.settingsService.savedCaptureDelaySeconds, 5);
  });

  testWidgets('shortcut rows render in shortcuts tab', (tester) async {
    await _pumpSettingsScreen(tester);

    await tester.tap(_tabLabel('Shortcuts'));
    await tester.pumpAndSettle();

    expect(find.byType(OutlinedButton), findsNWidgets(7));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reset shortcut saves immediately', (tester) async {
    final harness = await _pumpSettingsScreen(
      tester,
      initialShortcuts: _customShortcuts(),
    );

    await tester.tap(_tabLabel('Shortcuts'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Reset'));
    await tester.pumpAndSettle();

    expect(
      harness.state.shortcuts.encodeJson(),
      ShortcutBindings.defaults().encodeJson(),
    );
    expect(
      harness.settingsService.savedShortcuts?.encodeJson(),
      ShortcutBindings.defaults().encodeJson(),
    );
    expect(harness.hotkeyService.updates, hasLength(1));
    expect(harness.trayService.updates, hasLength(1));
  });

  testWidgets('capture style controls persist immediately', (tester) async {
    final harness = await _pumpSettingsScreen(tester);

    await tester.tap(_tabLabel('Capture'));
    await tester.pumpAndSettle();

    final shadowSwitch = tester.widget<Switch>(find.byType(Switch).last);
    shadowSwitch.onChanged!(true);
    await tester.pumpAndSettle();

    final borderRadiusSlider = tester
        .widgetList<Slider>(find.byType(Slider))
        .first;
    borderRadiusSlider.onChanged!(18);
    await tester.pumpAndSettle();

    final paddingSlider = tester.widgetList<Slider>(find.byType(Slider)).last;
    paddingSlider.onChanged!(24);
    await tester.pumpAndSettle();

    expect(
      harness.settingsService.savedCaptureStyle,
      const CaptureStyleSettings(
        borderRadius: 18,
        padding: 24,
        shadowEnabled: true,
      ),
    );
  });

  testWidgets('shortcut recorder previews Ctrl and mixed modifier chords', (
    tester,
  ) async {
    final harness = await _pumpSettingsScreen(tester);

    await tester.tap(_tabLabel('Shortcuts'));
    await tester.pumpAndSettle();

    final changeButton = find.byType(OutlinedButton).first;
    await tester.ensureVisible(changeButton);
    await tester.tap(changeButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    if (Platform.isMacOS) {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      await messenger.handlePlatformMessage(
        shortcutRecorderChannel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onShortcutRecorderChanged', {
            'modifiers': ['control'],
          }),
        ),
        (_) {},
      );
      await tester.pump();
    } else {
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft,
      );
      await tester.pump();
    }

    final dialogFinder = find.byType(Dialog);
    expect(
      find.descendant(of: dialogFinder, matching: find.text('Ctrl')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialogFinder, matching: find.text('...')),
      findsOneWidget,
    );

    if (Platform.isMacOS) {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      await messenger.handlePlatformMessage(
        shortcutRecorderChannel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onShortcutRecorderCaptured', {
            'keyCode': 0,
            'modifiers': ['control', 'meta'],
          }),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();
    } else {
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.metaLeft,
        physicalKey: PhysicalKeyboardKey.metaLeft,
      );
      await tester.pump();
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.keyA,
        physicalKey: PhysicalKeyboardKey.keyA,
      );
      await tester.pumpAndSettle();
    }

    expect(
      find.descendant(of: dialogFinder, matching: find.text('Ctrl')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialogFinder,
        matching: find.text(Platform.isMacOS ? 'Cmd' : 'Meta'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialogFinder, matching: find.text('A')),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Use Shortcut'));
    await tester.pumpAndSettle();

    expect(harness.settingsService.savedShortcuts, isNotNull);
    expect(harness.hotkeyService.updates, hasLength(1));
    expect(harness.trayService.updates, hasLength(1));
    final savedShortcutLabel = shortcutDisplayLabel(
      HotKey(
        key: PhysicalKeyboardKey.keyA,
        modifiers: const [HotKeyModifier.control, HotKeyModifier.meta],
        scope: HotKeyScope.system,
      ),
    );
    expect(find.text(savedShortcutLabel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
