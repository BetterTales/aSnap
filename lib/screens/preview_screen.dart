import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../models/annotation.dart';
import '../services/window_service.dart';
import '../state/annotation_state.dart';
import '../state/app_state.dart';
import '../utils/toolbar_layout.dart';
import '../widgets/annotation_overlay.dart';
import '../widgets/tool_popover_mixin.dart';

/// Floating preview window for normal (non-scroll) captures.
///
/// Scroll capture results are handled by [ScrollResultScreen] in a fullscreen
/// overlay instead.
class PreviewScreen extends StatefulWidget {
  final AppState appState;
  final AnnotationState annotationState;
  final WindowService windowService;
  final VoidCallback onCopy;
  final VoidCallback onSave;
  final VoidCallback? onPin;
  final VoidCallback onDiscard;

  const PreviewScreen({
    super.key,
    required this.appState,
    required this.annotationState,
    required this.windowService,
    required this.onCopy,
    required this.onSave,
    this.onPin,
    required this.onDiscard,
  });

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> with ToolPopoverMixin {
  final _focusNode = FocusNode();
  bool _focusRetryRunning = false;
  late final void Function(String) _toolbarActionHandler;

  final _popoverAnchorLink = LayerLink();

  /// Tracks the last image to detect capture changes and reset annotation UI.
  ui.Image? _lastImage;
  Rect? _lastToolbarRect;
  bool _lastShowPin = false;
  bool _lastHasAnnotations = false;
  bool _lastCanUndo = false;
  bool _lastCanRedo = false;
  String? _lastActiveTool;

  void _resetToolbarSyncCache() {
    _lastToolbarRect = null;
    _lastShowPin = false;
    _lastHasAnnotations = false;
    _lastCanUndo = false;
    _lastCanRedo = false;
    _lastActiveTool = null;
  }

  @override
  AnnotationState get popoverAnnotationState => widget.annotationState;

  @override
  LayerLink get popoverAnchor => _popoverAnchorLink;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _toolbarActionHandler = _handleNativeToolbarAction;
    widget.windowService.onToolbarAction = _toolbarActionHandler;
  }

  @override
  void dispose() {
    if (identical(
      widget.windowService.onToolbarAction,
      _toolbarActionHandler,
    )) {
      widget.windowService.onToolbarAction = null;
    }
    _resetToolbarSyncCache();
    unawaited(widget.windowService.hideToolbarPanel());
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    removePopover();
    _focusNode.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Focus management
  // ---------------------------------------------------------------------------

  void _scheduleFocusSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _focusNode.hasFocus || _focusRetryRunning) return;
      _focusRetryRunning = true;
      _requestFocusWithRetry().whenComplete(() {
        _focusRetryRunning = false;
      });
    });
  }

  Future<void> _requestFocusWithRetry() async {
    for (var attempt = 0; attempt < 20; attempt++) {
      if (!mounted || _focusNode.hasFocus) return;
      await windowManager.focus();
      _focusNode.requestFocus();
      if (_focusNode.hasFocus) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  // ---------------------------------------------------------------------------
  // Keyboard (HardwareKeyboard — focus-independent)
  // ---------------------------------------------------------------------------

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    // Only handle keys when preview is active with an image.
    if (widget.appState.capturedImage == null) return false;

    final meta =
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.metaLeft,
        ) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.metaRight,
        );
    final shift =
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftLeft,
        ) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftRight,
        );

    // Cmd+Shift+Z → redo
    if (meta && shift && event.logicalKey == LogicalKeyboardKey.keyZ) {
      widget.annotationState.redo();
      return true;
    }
    // Cmd+Z → undo
    if (meta && event.logicalKey == LogicalKeyboardKey.keyZ) {
      widget.annotationState.undo();
      return true;
    }
    // Cmd+Shift+P → pin to screen
    if (meta && shift && event.logicalKey == LogicalKeyboardKey.keyP) {
      widget.onPin?.call();
      return true;
    }

    // Delete/Backspace → delete selected annotation.
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      // Don't delete annotation while editing text (Backspace is used in TextField).
      if (widget.annotationState.editingText) return false;
      if (widget.annotationState.selectedIndex != null) {
        widget.annotationState.deleteSelected();
        return true;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      // Cancel text editing first.
      if (widget.annotationState.editingText) {
        widget.annotationState.cancelTextEdit();
        return true;
      }
      if (popoverVisible) {
        removePopover();
        return true;
      }
      if (activeShapeType != null) {
        setState(() => activeShapeType = null);
        return true;
      }
      widget.onDiscard();
      return true;
    }
    return false;
  }

  ShapeType? _shapeTypeForAction(String action) {
    return switch (action) {
      'rectangle' => ShapeType.rectangle,
      'ellipse' => ShapeType.ellipse,
      'arrow' => ShapeType.arrow,
      'line' => ShapeType.line,
      'pencil' => ShapeType.pencil,
      'marker' => ShapeType.marker,
      'mosaic' => ShapeType.mosaic,
      'number' => ShapeType.number,
      'text' => ShapeType.text,
      _ => null,
    };
  }

  void _handleNativeToolbarAction(String action) {
    switch (action) {
      case 'copy':
        widget.onCopy();
        return;
      case 'save':
        widget.onSave();
        return;
      case 'pin':
        widget.onPin?.call();
        return;
      case 'close':
        widget.onDiscard();
        return;
      case 'undo':
        widget.annotationState.undo();
        return;
      case 'redo':
        widget.annotationState.redo();
        return;
      default:
        final shape = _shapeTypeForAction(action);
        if (shape != null) {
          handleToolTap(shape);
          return;
        }
        return;
    }
  }

  void _syncNativeToolbar(Rect toolbarRect) {
    final showPin = widget.onPin != null;
    final hasAnnotations = widget.annotationState.hasAnnotations;
    final canUndo = widget.annotationState.canUndo;
    final canRedo = widget.annotationState.canRedo;
    final activeTool = activeShapeType?.name;

    if (_lastToolbarRect == toolbarRect &&
        _lastShowPin == showPin &&
        _lastHasAnnotations == hasAnnotations &&
        _lastCanUndo == canUndo &&
        _lastCanRedo == canRedo &&
        _lastActiveTool == activeTool) {
      return;
    }

    _lastToolbarRect = toolbarRect;
    _lastShowPin = showPin;
    _lastHasAnnotations = hasAnnotations;
    _lastCanUndo = canUndo;
    _lastCanRedo = canRedo;
    _lastActiveTool = activeTool;

    unawaited(
      widget.windowService.showToolbarPanel(
        rect: toolbarRect,
        showPin: showPin,
        hasAnnotations: hasAnnotations,
        canUndo: canUndo,
        canRedo: canRedo,
        activeTool: activeTool,
        anchorToWindow: true,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.appState, widget.annotationState]),
      builder: (context, _) {
        final image = widget.appState.capturedImage;
        if (image == null) {
          _lastImage = null;
          _resetToolbarSyncCache();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            unawaited(widget.windowService.hideToolbarPanel());
          });
          return const ColoredBox(color: Color(0xFF1E1E1E));
        }

        // Reset annotation UI and toolbar cache when the image changes.
        if (!identical(image, _lastImage)) {
          if (_lastImage != null) {
            removePopover();
            activeShapeType = null;
          }
          _resetToolbarSyncCache();
        }
        _lastImage = image;

        _scheduleFocusSync();
        return Focus(
          focusNode: _focusNode,
          autofocus: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Compute the actual rect where the image renders.
              final imageSize = Size(
                image.width.toDouble(),
                image.height.toDouble(),
              );
              final toolbarSize = kToolbarSize;
              final imageViewport = constraints.biggest;
              final fitted = applyBoxFit(
                BoxFit.scaleDown,
                imageSize,
                imageViewport,
              );
              final imageDisplayRect = Alignment.center.inscribe(
                fitted.destination,
                Offset.zero & imageViewport,
              );
              // Native toolbar panel should float BELOW the preview window,
              // so don't clamp to the Flutter window bounds.
              final toolbarRect = Rect.fromLTWH(
                imageDisplayRect.center.dx - toolbarSize.width / 2,
                imageDisplayRect.bottom + kToolbarGap,
                toolbarSize.width,
                toolbarSize.height,
              );
              final popoverAnchorX = imageDisplayRect.center.dx
                  .clamp(0.0, constraints.maxWidth)
                  .toDouble();
              final popoverAnchorY = (imageDisplayRect.bottom - 1)
                  .clamp(0.0, constraints.maxHeight)
                  .toDouble();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _syncNativeToolbar(toolbarRect);
              });

              return Stack(
                fit: StackFit.expand,
                children: [
                  // Screenshot image.
                  Positioned.fromRect(
                    rect: imageDisplayRect,
                    child: RawImage(image: image, fit: BoxFit.fill),
                  ),

                  // Annotation overlay.
                  AnnotationOverlay(
                    annotationState: widget.annotationState,
                    imageDisplayRect: imageDisplayRect,
                    imagePixelSize: imageSize,
                    enabled: activeShapeType != null,
                    sourceImage: image,
                  ),

                  // Window drag area (only when NOT drawing).
                  if (activeShapeType == null)
                    Positioned.fill(
                      child: DragToMoveArea(child: const SizedBox.expand()),
                    ),

                  Positioned(
                    left: popoverAnchorX,
                    top: popoverAnchorY,
                    child: CompositedTransformTarget(
                      link: _popoverAnchorLink,
                      child: const SizedBox(width: 1, height: 1),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
