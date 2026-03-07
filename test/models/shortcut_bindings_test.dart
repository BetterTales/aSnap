import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'package:a_snap/models/shortcut_bindings.dart';

void main() {
  test('shortcutModifiersFromPressedKeys includes control', () {
    final modifiers = shortcutModifiersFromPressedKeys({
      PhysicalKeyboardKey.controlLeft,
      PhysicalKeyboardKey.keyR,
    });

    expect(modifiers, contains(HotKeyModifier.control));
  });

  test('normalizeShortcutHotKey preserves control modifiers', () {
    final hotKey = normalizeShortcutHotKey(
      ShortcutAction.region,
      HotKey(
        key: PhysicalKeyboardKey.keyR,
        modifiers: const [HotKeyModifier.control, HotKeyModifier.shift],
        scope: HotKeyScope.system,
      ),
    );

    expect(
      hotKey.modifiers,
      equals(const [HotKeyModifier.control, HotKeyModifier.shift]),
    );
  });

  test('shortcutDisplayLabel matches native macOS menu ordering', () {
    final label = shortcutDisplayLabel(
      HotKey(
        key: PhysicalKeyboardKey.keyA,
        modifiers: const [HotKeyModifier.meta, HotKeyModifier.shift],
        scope: HotKeyScope.system,
      ),
    );

    expect(label, Platform.isMacOS ? '⇧⌘A' : 'Meta + Shift + A');
  });
}
