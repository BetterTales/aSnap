import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'package:a_snap/models/capture_style_settings.dart';
import 'package:a_snap/models/shortcut_bindings.dart';
import 'package:a_snap/services/hotkey_service.dart';
import 'package:a_snap/services/settings_service.dart';
import 'package:a_snap/services/tray_service.dart';
import 'package:a_snap/services/window_service.dart';
import 'package:a_snap/state/settings_state.dart';
import 'package:a_snap/utils/laser_defaults.dart';

class _FakeSettingsService extends SettingsService {
  _FakeSettingsService() : super();

  bool failSave = false;
  bool failOcrSave = false;
  bool failOcrOpenUrlSave = false;
  bool failCaptureStyleSave = false;
  bool failInkColorSave = false;
  bool failInkStrokeSave = false;
  bool failInkSmoothingSave = false;
  bool failInkAutoFadeSave = false;
  bool failInkEraserSizeSave = false;
  bool failLaserColorSave = false;
  bool failLaserSizeSave = false;
  bool failLaserFadeSave = false;
  ShortcutBindings? savedShortcuts;
  bool? savedOcrPreviewEnabled;
  bool? savedOcrOpenUrlPromptEnabled;
  CaptureStyleSettings? savedCaptureStyle;
  Color? savedInkColor;
  double? savedInkStrokeWidth;
  double? savedInkSmoothingTolerance;
  double? savedInkAutoFadeSeconds;
  double? savedInkEraserSize;
  Color? savedLaserColor;
  double? savedLaserSize;
  double? savedLaserFadeSeconds;

  @override
  Future<void> saveShortcutBindings(ShortcutBindings bindings) async {
    if (failSave) {
      throw Exception('save failed');
    }
    savedShortcuts = bindings;
  }

  @override
  Future<void> saveOcrPreviewEnabled(bool enabled) async {
    if (failOcrSave) {
      throw Exception('ocr save failed');
    }
    savedOcrPreviewEnabled = enabled;
  }

  @override
  Future<void> saveOcrOpenUrlPromptEnabled(bool enabled) async {
    if (failOcrOpenUrlSave) {
      throw Exception('ocr open url save failed');
    }
    savedOcrOpenUrlPromptEnabled = enabled;
  }

  @override
  Future<void> saveCaptureStyle(CaptureStyleSettings style) async {
    if (failCaptureStyleSave) {
      throw Exception('capture style save failed');
    }
    savedCaptureStyle = style;
  }

  @override
  Future<void> saveInkColor(Color color) async {
    if (failInkColorSave) {
      throw Exception('ink color save failed');
    }
    savedInkColor = color;
  }

  @override
  Future<void> saveInkStrokeWidth(double width) async {
    if (failInkStrokeSave) {
      throw Exception('ink stroke save failed');
    }
    savedInkStrokeWidth = width;
  }

  @override
  Future<void> saveInkSmoothingTolerance(double tolerance) async {
    if (failInkSmoothingSave) {
      throw Exception('ink smoothing save failed');
    }
    savedInkSmoothingTolerance = tolerance;
  }

  @override
  Future<void> saveInkAutoFadeSeconds(double seconds) async {
    if (failInkAutoFadeSave) {
      throw Exception('ink auto fade save failed');
    }
    savedInkAutoFadeSeconds = seconds;
  }

  @override
  Future<void> saveInkEraserSize(double size) async {
    if (failInkEraserSizeSave) {
      throw Exception('ink eraser size save failed');
    }
    savedInkEraserSize = size;
  }

  @override
  Future<void> saveLaserColor(Color color) async {
    if (failLaserColorSave) {
      throw Exception('laser color save failed');
    }
    savedLaserColor = color;
  }

  @override
  Future<void> saveLaserSize(double size) async {
    if (failLaserSizeSave) {
      throw Exception('laser size save failed');
    }
    savedLaserSize = size;
  }

  @override
  Future<void> saveLaserFadeSeconds(double seconds) async {
    if (failLaserFadeSave) {
      throw Exception('laser fade save failed');
    }
    savedLaserFadeSeconds = seconds;
  }
}

class _FakeWindowService extends WindowService {
  LaunchAtLoginState state = const LaunchAtLoginState(
    supported: false,
    enabled: false,
    requiresApproval: false,
  );

  bool failInkShortcut = false;
  int inkShortcutUpdates = 0;
  HotKey? lastInkShortcut;
  bool failLaserShortcut = false;
  int laserShortcutUpdates = 0;
  HotKey? lastLaserShortcut;

  @override
  Future<LaunchAtLoginState> getLaunchAtLoginState() async {
    return state;
  }

  @override
  Future<void> setInkShortcut(HotKey hotKey) async {
    if (failInkShortcut) {
      throw Exception('ink shortcut update failed');
    }
    inkShortcutUpdates += 1;
    lastInkShortcut = hotKey;
  }

  @override
  Future<void> setLaserShortcut(HotKey hotKey) async {
    if (failLaserShortcut) {
      throw Exception('laser shortcut update failed');
    }
    laserShortcutUpdates += 1;
    lastLaserShortcut = hotKey;
  }
}

class _FakeHotkeyService extends HotkeyService {
  final List<ShortcutBindings> updates = [];
  bool failUpdate = false;

  @override
  Future<void> updateBindings(ShortcutBindings bindings) async {
    if (failUpdate) {
      throw Exception('hotkey update failed');
    }
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

ShortcutBindings _updatedShortcuts() {
  return ShortcutBindings.defaults().copyWithAction(
    ShortcutAction.region,
    HotKey(
      key: PhysicalKeyboardKey.keyR,
      modifiers: const [HotKeyModifier.meta, HotKeyModifier.shift],
      scope: HotKeyScope.system,
    ),
  );
}

ShortcutBindings _ctrlBackedShortcuts() {
  return ShortcutBindings.defaults().copyWithAction(
    ShortcutAction.region,
    HotKey(
      key: PhysicalKeyboardKey.keyR,
      modifiers: const [
        HotKeyModifier.control,
        HotKeyModifier.meta,
        HotKeyModifier.shift,
      ],
      scope: HotKeyScope.system,
    ),
  );
}

void main() {
  late _FakeSettingsService settingsService;
  late _FakeWindowService windowService;
  late _FakeHotkeyService hotkeyService;
  late _FakeTrayService trayService;
  late SettingsState state;

  setUp(() {
    settingsService = _FakeSettingsService();
    windowService = _FakeWindowService();
    hotkeyService = _FakeHotkeyService();
    trayService = _FakeTrayService();
    state = SettingsState(
      initialShortcuts: ShortcutBindings.defaults(),
      initialOcrPreviewEnabled: false,
      initialOcrOpenUrlPromptEnabled: true,
      initialCaptureStyle: const CaptureStyleSettings.defaults(),
      initialInkColor: const Color(0xFFFF0000),
      initialInkStrokeWidth: 6.0,
      initialInkSmoothingTolerance: 1.5,
      initialInkAutoFadeSeconds: 0,
      initialInkEraserSize: 16,
      initialLaserColor: kLaserDefaultColor,
      initialLaserSize: kLaserDefaultSize,
      initialLaserFadeSeconds: kLaserDefaultFadeSeconds,
      settingsService: settingsService,
      windowService: windowService,
      hotkeyService: hotkeyService,
      trayService: trayService,
    );
  });

  test('applyShortcuts persists successful changes', () async {
    final updated = _updatedShortcuts();

    final saved = await state.applyShortcuts(updated);

    expect(saved, isTrue);
    expect(state.shortcuts.encodeJson(), updated.encodeJson());
    expect(state.shortcutError, isNull);
    expect(settingsService.savedShortcuts?.encodeJson(), updated.encodeJson());
    expect(hotkeyService.updates, hasLength(1));
    expect(trayService.updates, hasLength(1));
    expect(hotkeyService.updates.single.encodeJson(), updated.encodeJson());
    expect(trayService.updates.single.encodeJson(), updated.encodeJson());
    expect(windowService.inkShortcutUpdates, 1);
    expect(windowService.laserShortcutUpdates, 1);
    expect(
      shortcutSignature(windowService.lastInkShortcut!),
      shortcutSignature(updated.forAction(ShortcutAction.ink)),
    );
    expect(
      shortcutSignature(windowService.lastLaserShortcut!),
      shortcutSignature(updated.forAction(ShortcutAction.laser)),
    );
  });

  test('applyShortcuts persists Ctrl-backed shortcut updates', () async {
    final updated = _ctrlBackedShortcuts();

    final saved = await state.applyShortcuts(updated);

    expect(saved, isTrue);
    expect(state.shortcuts.encodeJson(), updated.encodeJson());
    expect(settingsService.savedShortcuts?.encodeJson(), updated.encodeJson());
    expect(hotkeyService.updates.single.encodeJson(), updated.encodeJson());
    expect(trayService.updates.single.encodeJson(), updated.encodeJson());
    expect(windowService.inkShortcutUpdates, 1);
    expect(windowService.laserShortcutUpdates, 1);
    expect(
      shortcutSignature(windowService.lastInkShortcut!),
      shortcutSignature(updated.forAction(ShortcutAction.ink)),
    );
    expect(
      shortcutSignature(windowService.lastLaserShortcut!),
      shortcutSignature(updated.forAction(ShortcutAction.laser)),
    );
  });

  test('applyShortcuts rolls back runtime changes when save fails', () async {
    settingsService.failSave = true;
    final initial = state.shortcuts;
    final updated = _updatedShortcuts();

    final saved = await state.applyShortcuts(updated);

    expect(saved, isFalse);
    expect(state.shortcuts.encodeJson(), initial.encodeJson());
    expect(state.shortcutError, contains('save failed'));
    expect(settingsService.savedShortcuts, isNull);
    expect(hotkeyService.updates, hasLength(2));
    expect(trayService.updates, hasLength(2));
    expect(hotkeyService.updates.first.encodeJson(), updated.encodeJson());
    expect(hotkeyService.updates.last.encodeJson(), initial.encodeJson());
    expect(trayService.updates.first.encodeJson(), updated.encodeJson());
    expect(trayService.updates.last.encodeJson(), initial.encodeJson());
    expect(windowService.inkShortcutUpdates, 2);
    expect(windowService.laserShortcutUpdates, 2);
    expect(
      shortcutSignature(windowService.lastInkShortcut!),
      shortcutSignature(initial.forAction(ShortcutAction.ink)),
    );
    expect(
      shortcutSignature(windowService.lastLaserShortcut!),
      shortcutSignature(initial.forAction(ShortcutAction.laser)),
    );
  });

  test(
    'applyShortcuts stops before persistence when hotkey update fails',
    () async {
      hotkeyService.failUpdate = true;
      final initial = state.shortcuts;
      final updated = _updatedShortcuts();

      final saved = await state.applyShortcuts(updated);

      expect(saved, isFalse);
      expect(state.shortcuts.encodeJson(), initial.encodeJson());
      expect(state.shortcutError, contains('hotkey update failed'));
      expect(settingsService.savedShortcuts, isNull);
      expect(hotkeyService.updates, isEmpty);
      expect(trayService.updates, isEmpty);
      expect(windowService.inkShortcutUpdates, 0);
      expect(windowService.laserShortcutUpdates, 0);
    },
  );

  test('setCaptureBorderRadius persists capture style changes', () async {
    await state.setCaptureBorderRadius(18);

    expect(state.captureStyle.borderRadius, 18);
    expect(settingsService.savedCaptureStyle?.borderRadius, 18);
    expect(state.captureStyleError, isNull);
  });

  test('setCapturePadding persists capture style changes', () async {
    await state.setCapturePadding(24);

    expect(state.captureStyle.padding, 24);
    expect(settingsService.savedCaptureStyle?.padding, 24);
    expect(state.captureStyleError, isNull);
  });

  test('setCaptureShadowEnabled rolls back on save failure', () async {
    settingsService.failCaptureStyleSave = true;

    await state.setCaptureShadowEnabled(true);

    expect(state.captureStyle.shadowEnabled, isFalse);
    expect(state.captureStyleError, contains('capture style save failed'));
  });

  test('refreshLaunchAtLogin loads the native state', () async {
    windowService.state = const LaunchAtLoginState(
      supported: true,
      enabled: true,
      requiresApproval: true,
    );

    await state.refreshLaunchAtLogin();

    expect(state.launchAtLoginSupported, isTrue);
    expect(state.launchAtLoginEnabled, isTrue);
    expect(state.launchAtLoginRequiresApproval, isTrue);
    expect(state.launchAtLoginBusy, isFalse);
    expect(state.launchAtLoginError, isNull);
  });

  test('setOcrPreviewEnabled persists the setting', () async {
    await state.setOcrPreviewEnabled(true);

    expect(state.ocrPreviewEnabled, isTrue);
    expect(settingsService.savedOcrPreviewEnabled, isTrue);
    expect(state.ocrPreviewError, isNull);
  });

  test('setOcrPreviewEnabled rolls back on save failure', () async {
    settingsService.failOcrSave = true;

    await state.setOcrPreviewEnabled(true);

    expect(state.ocrPreviewEnabled, isFalse);
    expect(state.ocrPreviewError, contains('ocr save failed'));
  });

  test('setInkColor persists the setting', () async {
    const nextColor = Color(0xFF00C853);

    await state.setInkColor(nextColor);

    expect(state.inkColor, nextColor);
    expect(settingsService.savedInkColor, nextColor);
    expect(state.inkColorError, isNull);
  });

  test('setInkColor rolls back on save failure', () async {
    settingsService.failInkColorSave = true;
    const nextColor = Color(0xFF2979FF);

    await state.setInkColor(nextColor);

    expect(state.inkColor, const Color(0xFFFF0000));
    expect(state.inkColorError, contains('ink color save failed'));
  });

  test('setInkStrokeWidth persists the setting', () async {
    await state.setInkStrokeWidth(12);

    expect(state.inkStrokeWidth, 12);
    expect(settingsService.savedInkStrokeWidth, 12);
    expect(state.inkStrokeWidthError, isNull);
  });

  test('setInkStrokeWidth rolls back on save failure', () async {
    settingsService.failInkStrokeSave = true;

    await state.setInkStrokeWidth(12);

    expect(state.inkStrokeWidth, 6.0);
    expect(state.inkStrokeWidthError, contains('ink stroke save failed'));
  });

  test('setInkSmoothingTolerance persists the setting', () async {
    await state.setInkSmoothingTolerance(2.5);

    expect(state.inkSmoothingTolerance, 2.5);
    expect(settingsService.savedInkSmoothingTolerance, 2.5);
    expect(state.inkSmoothingError, isNull);
  });

  test('setInkSmoothingTolerance rolls back on save failure', () async {
    settingsService.failInkSmoothingSave = true;

    await state.setInkSmoothingTolerance(2.5);

    expect(state.inkSmoothingTolerance, 1.5);
    expect(state.inkSmoothingError, contains('ink smoothing save failed'));
  });

  test('setInkAutoFadeSeconds persists the setting', () async {
    await state.setInkAutoFadeSeconds(5);

    expect(state.inkAutoFadeSeconds, 5);
    expect(settingsService.savedInkAutoFadeSeconds, 5);
    expect(state.inkAutoFadeError, isNull);
  });

  test('setInkAutoFadeSeconds rolls back on save failure', () async {
    settingsService.failInkAutoFadeSave = true;

    await state.setInkAutoFadeSeconds(5);

    expect(state.inkAutoFadeSeconds, 0);
    expect(state.inkAutoFadeError, contains('ink auto fade save failed'));
  });

  test('setInkEraserSize persists the setting', () async {
    await state.setInkEraserSize(24);

    expect(state.inkEraserSize, 24);
    expect(settingsService.savedInkEraserSize, 24);
    expect(state.inkEraserSizeError, isNull);
  });

  test('setInkEraserSize rolls back on save failure', () async {
    settingsService.failInkEraserSizeSave = true;

    await state.setInkEraserSize(24);

    expect(state.inkEraserSize, 16);
    expect(state.inkEraserSizeError, contains('ink eraser size save failed'));
  });

  test('setLaserColor persists the setting', () async {
    const nextColor = Color(0xFF00C853);

    await state.setLaserColor(nextColor);

    expect(state.laserColor, nextColor);
    expect(settingsService.savedLaserColor, nextColor);
    expect(state.laserColorError, isNull);
  });

  test('setLaserColor rolls back on save failure', () async {
    settingsService.failLaserColorSave = true;
    const nextColor = Color(0xFF2979FF);

    await state.setLaserColor(nextColor);

    expect(state.laserColor, kLaserDefaultColor);
    expect(state.laserColorError, contains('laser color save failed'));
  });

  test('setLaserSize persists the setting', () async {
    await state.setLaserSize(20);

    expect(state.laserSize, 20);
    expect(settingsService.savedLaserSize, 20);
    expect(state.laserSizeError, isNull);
  });

  test('setLaserSize rolls back on save failure', () async {
    settingsService.failLaserSizeSave = true;

    await state.setLaserSize(20);

    expect(state.laserSize, kLaserDefaultSize);
    expect(state.laserSizeError, contains('laser size save failed'));
  });

  test('setLaserFadeSeconds persists the setting', () async {
    await state.setLaserFadeSeconds(1.2);

    expect(state.laserFadeSeconds, 1.2);
    expect(settingsService.savedLaserFadeSeconds, 1.2);
    expect(state.laserFadeError, isNull);
  });

  test('setLaserFadeSeconds rolls back on save failure', () async {
    settingsService.failLaserFadeSave = true;

    await state.setLaserFadeSeconds(1.2);

    expect(state.laserFadeSeconds, kLaserDefaultFadeSeconds);
    expect(state.laserFadeError, contains('laser fade save failed'));
  });

  test('setOcrOpenUrlPromptEnabled persists the setting', () async {
    await state.setOcrOpenUrlPromptEnabled(false);

    expect(state.ocrOpenUrlPromptEnabled, isFalse);
    expect(settingsService.savedOcrOpenUrlPromptEnabled, isFalse);
    expect(state.ocrOpenUrlPromptError, isNull);
  });

  test('setOcrOpenUrlPromptEnabled rolls back on save failure', () async {
    settingsService.failOcrOpenUrlSave = true;

    await state.setOcrOpenUrlPromptEnabled(false);

    expect(state.ocrOpenUrlPromptEnabled, isTrue);
    expect(state.ocrOpenUrlPromptError, contains('ocr open url save failed'));
  });
}
