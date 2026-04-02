import 'dart:io';

import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';

import '../models/shortcut_bindings.dart';
import '../utils/constants.dart';

class TrayService with TrayListener {
  static const _channel = MethodChannel('com.asnap/window');

  VoidCallback? onCaptureFullScreen;
  VoidCallback? onCaptureRegion;
  VoidCallback? onCaptureScroll;
  VoidCallback? onOcr;
  VoidCallback? onInk;
  VoidCallback? onLaser;
  VoidCallback? onPin;
  VoidCallback? onOpenSettings;
  VoidCallback? onQuit;

  Menu _buildMenu() {
    return Menu(
      items: [
        MenuItem(key: 'capture_region', label: 'Region'),
        MenuItem(key: 'capture_scroll', label: 'Scroll'),
        MenuItem(key: 'capture_full_screen', label: 'Full Screen'),
        MenuItem(key: 'ocr', label: 'OCR'),
        MenuItem.separator(),
        MenuItem(key: 'ink', label: 'Ink'),
        MenuItem(key: 'laser', label: 'Laser'),
        MenuItem.separator(),
        MenuItem(key: 'pin', label: 'Pin'),
        MenuItem.separator(),
        MenuItem(key: 'settings', label: 'Settings'),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: 'Quit $kAppName'),
      ],
    );
  }

  Future<void> init({required ShortcutBindings shortcuts}) async {
    await trayManager.setIcon(kTrayIconPath, isTemplate: true, iconSize: 18);
    await trayManager.setToolTip(kTrayTooltip);

    // Use tray_manager for menu creation and display (proper NSStatusItem
    // integration). On macOS, register shortcuts separately so the native
    // side can patch keyEquivalent on the menu items before they render.
    await trayManager.setContextMenu(_buildMenu());

    if (Platform.isMacOS) {
      await updateShortcuts(shortcuts);
    }

    trayManager.addListener(this);
  }

  Future<void> updateShortcuts(ShortcutBindings shortcuts) async {
    if (!Platform.isMacOS) return;
    // Rebuild the menu so the next popup uses fresh NSMenuItems before native
    // keyEquivalent patching runs.
    await trayManager.setContextMenu(_buildMenu());
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
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  Future<void> destroy() async {
    trayManager.removeListener(this);
    await trayManager.destroy();
  }
}
