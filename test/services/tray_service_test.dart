import 'dart:io' show Platform;

import 'package:a_snap/models/shortcut_bindings.dart';
import 'package:a_snap/services/tray_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

const _trayManagerChannel = MethodChannel('tray_manager');
const _windowChannel = MethodChannel('com.asnap/window');

Map<String, dynamic> _menuItemByKey(List<dynamic> items, String key) {
  for (final raw in items) {
    final item = Map<String, dynamic>.from(raw as Map);
    if (item['key'] == key) {
      return item;
    }
  }
  fail('Menu item with key "$key" not found');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_trayManagerChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowChannel, null);
  });

  test('Windows tray labels include shortcuts', () async {
    if (!Platform.isWindows) {
      return;
    }

    final trayCalls = <MethodCall>[];
    final windowCalls = <MethodCall>[];

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_trayManagerChannel, (call) async {
          trayCalls.add(call);
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowChannel, (call) async {
          windowCalls.add(call);
          return null;
        });

    final service = TrayService();
    final shortcuts = ShortcutBindings.defaults();
    await service.updateShortcuts(shortcuts);

    final setContextMenuCall = trayCalls.firstWhere(
      (call) => call.method == 'setContextMenu',
    );
    final arguments = Map<String, dynamic>.from(
      setContextMenuCall.arguments as Map,
    );
    final menu = Map<String, dynamic>.from(arguments['menu'] as Map);
    final items = menu['items'] as List<dynamic>;

    final regionLabel =
        _menuItemByKey(items, 'capture_region')['label'] as String;
    final scrollLabel =
        _menuItemByKey(items, 'capture_scroll')['label'] as String;
    final fullScreenLabel =
        _menuItemByKey(items, 'capture_full_screen')['label'] as String;
    final inkLabel = _menuItemByKey(items, 'ink')['label'] as String;
    final laserLabel = _menuItemByKey(items, 'laser')['label'] as String;

    expect(
      regionLabel,
      'Region\t${shortcutDisplayLabel(shortcuts.forAction(ShortcutAction.region))}',
    );
    expect(
      scrollLabel,
      'Scroll\t${shortcutDisplayLabel(shortcuts.forAction(ShortcutAction.scrollCapture))}',
    );
    expect(
      fullScreenLabel,
      'Full Screen\t${shortcutDisplayLabel(shortcuts.forAction(ShortcutAction.fullScreen))}',
    );
    expect(
      inkLabel,
      'Ink\t${shortcutDisplayLabel(shortcuts.forAction(ShortcutAction.ink))}',
    );
    expect(
      laserLabel,
      'Laser\t${shortcutDisplayLabel(shortcuts.forAction(ShortcutAction.laser))}',
    );

    expect(windowCalls, isEmpty);
  });

  test('Windows tray shortcut labels refresh after rebinding', () async {
    if (!Platform.isWindows) {
      return;
    }

    final trayCalls = <MethodCall>[];

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_trayManagerChannel, (call) async {
          trayCalls.add(call);
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowChannel, (_) async => null);

    final service = TrayService();
    final defaults = ShortcutBindings.defaults();
    final rebound = defaults.copyWithAction(
      ShortcutAction.region,
      HotKey(
        key: PhysicalKeyboardKey.keyR,
        modifiers: const [HotKeyModifier.control, HotKeyModifier.shift],
        scope: HotKeyScope.system,
      ),
    );

    await service.updateShortcuts(defaults);
    await service.updateShortcuts(rebound);

    final setContextMenuCalls = trayCalls
        .where((call) => call.method == 'setContextMenu')
        .toList();
    final latestCall = setContextMenuCalls.last;
    final arguments = Map<String, dynamic>.from(latestCall.arguments as Map);
    final menu = Map<String, dynamic>.from(arguments['menu'] as Map);
    final items = menu['items'] as List<dynamic>;
    final regionLabel =
        _menuItemByKey(items, 'capture_region')['label'] as String;

    expect(
      regionLabel,
      'Region\t${shortcutDisplayLabel(rebound.forAction(ShortcutAction.region))}',
    );
  });
}
