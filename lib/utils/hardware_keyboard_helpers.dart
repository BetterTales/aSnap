import 'dart:io';

import 'package:flutter/services.dart';

bool isPrimaryShortcutModifierPressed() {
  final pressedKeys = HardwareKeyboard.instance.logicalKeysPressed;
  if (Platform.isMacOS) {
    return pressedKeys.contains(LogicalKeyboardKey.metaLeft) ||
        pressedKeys.contains(LogicalKeyboardKey.metaRight);
  }
  return pressedKeys.contains(LogicalKeyboardKey.controlLeft) ||
      pressedKeys.contains(LogicalKeyboardKey.controlRight);
}

bool isShiftModifierPressed() {
  final pressedKeys = HardwareKeyboard.instance.logicalKeysPressed;
  return pressedKeys.contains(LogicalKeyboardKey.shiftLeft) ||
      pressedKeys.contains(LogicalKeyboardKey.shiftRight);
}
