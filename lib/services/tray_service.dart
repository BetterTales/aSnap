import 'dart:io';

import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';

import '../models/shortcut_bindings.dart';
import '../utils/constants.dart';

class TrayService with TrayListener {
  static const _channel = MethodChannel('com.asnap/window');
  static const _trayChannel = MethodChannel('tray_manager');
  ShortcutBindings _shortcuts = ShortcutBindings.defaults();

  VoidCallback? onCaptureFullScreen;
  VoidCallback? onCaptureRegion;
  VoidCallback? onCaptureScroll;
  VoidCallback? onOcr;
  VoidCallback? onInk;
  VoidCallback? onLaser;
  VoidCallback? onPin;
  VoidCallback? onOpenSettings;
  VoidCallback? onQuit;

  String _menuLabel(ShortcutAction action) {
    final base = action.label;
    if (!Platform.isWindows) {
      return base;
    }
    return '$base\t${shortcutDisplayLabel(_shortcuts.forAction(action))}';
  }

  Menu _buildMenu() {
    final items = <MenuItem>[
      MenuItem(key: 'capture_region', label: _menuLabel(ShortcutAction.region)),
      MenuItem(
        key: 'capture_scroll',
        label: _menuLabel(ShortcutAction.scrollCapture),
      ),
      MenuItem(
        key: 'capture_full_screen',
        label: _menuLabel(ShortcutAction.fullScreen),
      ),
    ];

    if (Platform.isMacOS) {
      items.addAll([
        MenuItem(key: 'ocr', label: _menuLabel(ShortcutAction.ocr)),
        MenuItem.separator(),
      ]);
    } else {
      items.add(MenuItem.separator());
    }

    items.addAll([
      MenuItem(key: 'ink', label: _menuLabel(ShortcutAction.ink)),
      MenuItem(key: 'laser', label: _menuLabel(ShortcutAction.laser)),
    ]);

    if (Platform.isMacOS) {
      items.addAll([
        MenuItem.separator(),
        MenuItem(key: 'pin', label: _menuLabel(ShortcutAction.pin)),
      ]);
    }

    items.addAll([
      MenuItem.separator(),
      MenuItem(key: 'settings', label: 'Settings'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Quit $kAppName'),
    ]);

    return Menu(items: items);
  }

  Future<void> _showContextMenu() {
    if (Platform.isWindows) {
      return _trayChannel.invokeMethod('popUpContextMenu', {
        'bringAppToFront': true,
      });
    }
    return trayManager.popUpContextMenu();
  }

  Future<void> init({required ShortcutBindings shortcuts}) async {
    await trayManager.setIcon(
      kTrayIconPath,
      isTemplate: Platform.isMacOS,
      iconSize: 18,
    );
    await trayManager.setToolTip(kTrayTooltip);

    await updateShortcuts(shortcuts);

    trayManager.addListener(this);
  }

  Future<void> updateShortcuts(ShortcutBindings shortcuts) async {
    _shortcuts = shortcuts;
    // Rebuild the menu so the next popup uses fresh NSMenuItems before native
    // keyEquivalent patching runs (macOS) or so labels refresh (Windows).
    await trayManager.setContextMenu(_buildMenu());
    if (!Platform.isMacOS) return;
    await _channel.invokeMethod(
      'registerTrayShortcuts',
      trayShortcutDescriptors(shortcuts),
    );
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'capture_full_screen':
        onCaptureFullScreen?.call();
        return;
      case 'capture_region':
        onCaptureRegion?.call();
        return;
      case 'capture_scroll':
        onCaptureScroll?.call();
        return;
      case 'ocr':
        onOcr?.call();
        return;
      case 'ink':
        onInk?.call();
        return;
      case 'laser':
        onLaser?.call();
        return;
      case 'pin':
        onPin?.call();
        return;
      case 'settings':
        onOpenSettings?.call();
        return;
      case 'quit':
        onQuit?.call();
        return;
    }
  }

  @override
  void onTrayIconMouseDown() {
    _showContextMenu();
  }

  @override
  void onTrayIconRightMouseDown() {
    _showContextMenu();
  }

  Future<void> destroy() async {
    trayManager.removeListener(this);
    await trayManager.destroy();
  }
}
