import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../state/app_state.dart';
import '../state/ink_state.dart';
import '../state/laser_state.dart';
import '../widgets/ink_overlay.dart';
import '../widgets/laser_overlay.dart';

class InkOverlayScreen extends StatefulWidget {
  const InkOverlayScreen({
    super.key,
    required this.inkState,
    required this.laserState,
    required this.drawingEnabled,
    required this.tool,
    required this.inkHotKey,
    required this.laserHotKey,
    required this.onInkKeyDown,
    required this.onInkKeyUp,
    required this.onLaserKeyDown,
    required this.onLaserKeyUp,
    required this.strokeColor,
    required this.strokeWidth,
    required this.smoothingTolerance,
    required this.autoFadeSeconds,
    required this.eraserSize,
    required this.laserColor,
    required this.laserSize,
    required this.laserFadeSeconds,
    required this.onEraserSizeChanged,
    required this.onExitRequested,
  });

  final InkState inkState;
  final LaserState laserState;
  final bool drawingEnabled;
  final InkTool tool;
  final HotKey inkHotKey;
  final HotKey laserHotKey;
  final VoidCallback onInkKeyDown;
  final VoidCallback onInkKeyUp;
  final VoidCallback onLaserKeyDown;
  final VoidCallback onLaserKeyUp;
  final Color strokeColor;
  final double strokeWidth;
  final double smoothingTolerance;
  final double autoFadeSeconds;
  final double eraserSize;
  final Color laserColor;
  final double laserSize;
  final double laserFadeSeconds;
  final ValueChanged<double> onEraserSizeChanged;
  final Future<void> Function() onExitRequested;

  @override
  State<InkOverlayScreen> createState() => _InkOverlayScreenState();
}

class _InkOverlayScreenState extends State<InkOverlayScreen> {
  late Set<PhysicalKeyboardKey> _inkShortcutPhysicalKeys;
  late Set<PhysicalKeyboardKey> _laserShortcutPhysicalKeys;

  @override
  void initState() {
    super.initState();
    _rebuildShortcutKeys();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    if (widget.drawingEnabled) {
      _scheduleCursorRefresh();
    }
  }

  @override
  void didUpdateWidget(InkOverlayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.inkHotKey != widget.inkHotKey ||
        oldWidget.laserHotKey != widget.laserHotKey) {
      _rebuildShortcutKeys();
    }
    final wasActive = oldWidget.drawingEnabled;
    final isActive = widget.drawingEnabled;
    final toolChanged = oldWidget.tool != widget.tool;
    if ((!wasActive && isActive) || (isActive && toolChanged)) {
      _scheduleCursorRefresh();
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  void _rebuildShortcutKeys() {
    final inkKeys = <PhysicalKeyboardKey>{widget.inkHotKey.physicalKey};
    for (final modifier
        in widget.inkHotKey.modifiers ?? const <HotKeyModifier>[]) {
      inkKeys.addAll(modifier.physicalKeys);
    }
    _inkShortcutPhysicalKeys = inkKeys;

    final laserKeys = <PhysicalKeyboardKey>{widget.laserHotKey.physicalKey};
    for (final modifier
        in widget.laserHotKey.modifiers ?? const <HotKeyModifier>[]) {
      laserKeys.addAll(modifier.physicalKeys);
    }
    _laserShortcutPhysicalKeys = laserKeys;
  }

  void _scheduleCursorRefresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      RendererBinding.instance.mouseTracker.updateAllDevices();
    });
  }

  bool _areModifiersPressed(HotKey hotKey) {
    final required = hotKey.modifiers ?? const <HotKeyModifier>[];
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
          _areModifiersPressed(widget.inkHotKey)) {
        widget.onInkKeyDown();
      }
      if (event.physicalKey == widget.laserHotKey.physicalKey &&
          _areModifiersPressed(widget.laserHotKey)) {
        widget.onLaserKeyDown();
      }
    } else if (event is KeyUpEvent) {
      if (_inkShortcutPhysicalKeys.contains(event.physicalKey)) {
        widget.onInkKeyUp();
      }
      if (_laserShortcutPhysicalKeys.contains(event.physicalKey)) {
        widget.onLaserKeyUp();
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final inkActive = widget.drawingEnabled && widget.tool == InkTool.ink;
    final laserActive = widget.drawingEnabled && widget.tool == InkTool.laser;
    final overlayCursor = (inkActive || laserActive)
        ? SystemMouseCursors.none
        : MouseCursor.defer;

    return ColoredBox(
      color: Colors.transparent,
      child: MouseRegion(
        cursor: overlayCursor,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !inkActive,
                child: InkOverlay(
                  inkState: widget.inkState,
                  drawingEnabled: inkActive,
                  strokeColor: widget.strokeColor,
                  strokeWidth: widget.strokeWidth,
                  smoothingTolerance: widget.smoothingTolerance,
                  autoFadeSeconds: widget.autoFadeSeconds,
                  eraserSize: widget.eraserSize,
                  onEraserSizeChanged: widget.onEraserSizeChanged,
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !laserActive,
                child: LaserOverlay(
                  laserState: widget.laserState,
                  drawingEnabled: laserActive,
                  color: widget.laserColor,
                  size: widget.laserSize,
                  fadeSeconds: widget.laserFadeSeconds,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
