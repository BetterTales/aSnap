import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../state/ink_state.dart';
import '../widgets/ink_overlay.dart';

class InkOverlayScreen extends StatefulWidget {
  const InkOverlayScreen({
    super.key,
    required this.inkState,
    required this.drawingEnabled,
    required this.inkHotKey,
    required this.onInkKeyDown,
    required this.onInkKeyUp,
    required this.strokeColor,
    required this.strokeWidth,
    required this.smoothingTolerance,
    required this.autoFadeSeconds,
    required this.eraserSize,
    required this.onEraserSizeChanged,
    required this.onExitRequested,
  });

  final InkState inkState;
  final bool drawingEnabled;
  final HotKey inkHotKey;
  final VoidCallback onInkKeyDown;
  final VoidCallback onInkKeyUp;
  final Color strokeColor;
  final double strokeWidth;
  final double smoothingTolerance;
  final double autoFadeSeconds;
  final double eraserSize;
  final ValueChanged<double> onEraserSizeChanged;
  final Future<void> Function() onExitRequested;

  @override
  State<InkOverlayScreen> createState() => _InkOverlayScreenState();
}

class _InkOverlayScreenState extends State<InkOverlayScreen> {
  late Set<PhysicalKeyboardKey> _shortcutPhysicalKeys;

  @override
  void initState() {
    super.initState();
    _rebuildShortcutKeys();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void didUpdateWidget(InkOverlayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.inkHotKey != widget.inkHotKey) {
      _rebuildShortcutKeys();
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  void _rebuildShortcutKeys() {
    final keys = <PhysicalKeyboardKey>{widget.inkHotKey.physicalKey};
    for (final modifier
        in widget.inkHotKey.modifiers ?? const <HotKeyModifier>[]) {
      keys.addAll(modifier.physicalKeys);
    }
    _shortcutPhysicalKeys = keys;
  }

  bool _areModifiersPressed() {
    final required = widget.inkHotKey.modifiers ?? const <HotKeyModifier>[];
    if (required.isEmpty) return true;
    final pressed = HardwareKeyboard.instance.physicalKeysPressed;
    for (final modifier in required) {
      final keys = modifier.physicalKeys;
      final anyPressed = keys.any(pressed.contains);
      if (!anyPressed) return false;
    }
    return true;
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        unawaited(widget.onExitRequested());
      }
      if (event.physicalKey == widget.inkHotKey.physicalKey &&
          _areModifiersPressed()) {
        widget.onInkKeyDown();
      }
    } else if (event is KeyUpEvent) {
      if (_shortcutPhysicalKeys.contains(event.physicalKey)) {
        widget.onInkKeyUp();
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: InkOverlay(
              inkState: widget.inkState,
              drawingEnabled: widget.drawingEnabled,
              strokeColor: widget.strokeColor,
              strokeWidth: widget.strokeWidth,
              smoothingTolerance: widget.smoothingTolerance,
              autoFadeSeconds: widget.autoFadeSeconds,
              eraserSize: widget.eraserSize,
              onEraserSizeChanged: widget.onEraserSizeChanged,
            ),
          ),
        ],
      ),
    );
  }
}
