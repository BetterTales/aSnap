import 'package:flutter/foundation.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../utils/constants.dart';

class HotkeyService {
  bool _registered = false;

  Future<void> register({
    required VoidCallback onFullScreen,
    required VoidCallback onRegion,
    required VoidCallback onScrollCapture,
    required VoidCallback onPin,
  }) async {
    await hotKeyManager.unregisterAll();
    await hotKeyManager.register(
      kFullScreenHotkey,
      keyDownHandler: (_) => onFullScreen(),
    );
    await hotKeyManager.register(
      kRegionHotkey,
      keyDownHandler: (_) => onRegion(),
    );
    await hotKeyManager.register(
      kScrollCaptureHotkey,
      keyDownHandler: (_) => onScrollCapture(),
    );
    await hotKeyManager.register(kPinHotkey, keyDownHandler: (_) => onPin());
    _registered = true;
  }

  Future<void> unregisterAll() async {
    if (!_registered) return;
    await hotKeyManager.unregisterAll();
    _registered = false;
  }
}
