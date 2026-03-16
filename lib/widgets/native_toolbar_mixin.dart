import 'dart:async';

import 'package:flutter/widgets.dart';

import '../services/window_service.dart';
import '../state/annotation_state.dart';
import '../utils/toolbar_actions.dart';
import 'tool_popover_mixin.dart';

/// Shared macOS native toolbar wiring for screens that expose annotation tools.
///
/// Dart owns the toolbar state and business logic, while AppKit renders the
/// actual floating panel. This mixin keeps action routing and sync behavior
/// identical across preview, region-selection, and scroll-result flows.
mixin NativeToolbarMixin<T extends StatefulWidget>
    on State<T>, ToolPopoverMixin<T> {
  NativeToolbarRequest? _lastToolbarRequest;
  Rect? _resolvedToolbarFrame;

  late final void Function(String) _toolbarActionHandler =
      _dispatchNativeToolbarAction;
  late final void Function(NativeToolbarFrameUpdate) _toolbarFrameHandler =
      _handleNativeToolbarFrameChanged;

  WindowService get nativeToolbarWindowService;

  AnnotationState? get nativeToolbarAnnotationState;

  bool get nativeToolbarShowPin;

  bool get nativeToolbarShowHistoryControls => true;

  bool get nativeToolbarShowOcr => false;

  void handleNativeToolbarAction(String action);

  void initNativeToolbar() {
    nativeToolbarWindowService.onToolbarAction = _toolbarActionHandler;
    nativeToolbarWindowService.onToolbarFrameChanged = _toolbarFrameHandler;
  }

  void disposeNativeToolbar() {
    if (identical(
      nativeToolbarWindowService.onToolbarAction,
      _toolbarActionHandler,
    )) {
      nativeToolbarWindowService.onToolbarAction = null;
    }
    if (identical(
      nativeToolbarWindowService.onToolbarFrameChanged,
      _toolbarFrameHandler,
    )) {
      nativeToolbarWindowService.onToolbarFrameChanged = null;
    }
    resetNativeToolbarSyncCache();
    unawaited(nativeToolbarWindowService.hideToolbarPanel());
  }

  void resetNativeToolbarSyncCache() {
    _lastToolbarRequest = null;
    _resolvedToolbarFrame = null;
  }

  void hideNativeToolbar() {
    if (_lastToolbarRequest == null && _resolvedToolbarFrame == null) {
      return;
    }
    resetNativeToolbarSyncCache();
    unawaited(nativeToolbarWindowService.hideToolbarPanel());
  }

  Rect? get resolvedNativeToolbarFrame => _resolvedToolbarFrame;

  Offset nativeToolbarAnchorPoint({
    required Size viewportSize,
    required Offset fallbackAnchor,
  }) {
    final anchor = _resolvedToolbarFrame == null
        ? fallbackAnchor
        : Offset(_resolvedToolbarFrame!.center.dx, _resolvedToolbarFrame!.top);
    return Offset(
      anchor.dx.clamp(0.0, viewportSize.width).toDouble(),
      anchor.dy.clamp(0.0, viewportSize.height).toDouble(),
    );
  }

  void syncNativeToolbar({
    required NativeToolbarPlacement placement,
    Rect? anchorRect,
  }) {
    final annotationState = nativeToolbarAnnotationState;
    final showHistoryControls = nativeToolbarShowHistoryControls;
    final canUndo = annotationState?.canUndo ?? false;
    final canRedo = annotationState?.canRedo ?? false;
    final activeTool = shapeTypeToToolId(activeShapeType);
    final request = switch (placement) {
      NativeToolbarPlacement.belowWindow => NativeToolbarRequest.belowWindow(
        showPin: nativeToolbarShowPin,
        showHistoryControls: showHistoryControls,
        canUndo: canUndo,
        canRedo: canRedo,
        showOcr: nativeToolbarShowOcr,
        activeTool: activeTool,
      ),
      NativeToolbarPlacement.belowAnchor => NativeToolbarRequest.belowAnchor(
        anchorRect: anchorRect!,
        showPin: nativeToolbarShowPin,
        showHistoryControls: showHistoryControls,
        canUndo: canUndo,
        canRedo: canRedo,
        showOcr: nativeToolbarShowOcr,
        activeTool: activeTool,
      ),
    };

    if (_lastToolbarRequest == request) {
      return;
    }

    _lastToolbarRequest = request;

    unawaited(nativeToolbarWindowService.showToolbarPanel(request: request));
  }

  void _handleNativeToolbarFrameChanged(NativeToolbarFrameUpdate update) {
    if (_resolvedToolbarFrame == update.rect || !mounted) {
      return;
    }
    setState(() {
      _resolvedToolbarFrame = update.rect;
    });
  }

  void _dispatchNativeToolbarAction(String action) {
    final shapeType = toolIdToShapeType(action);
    if (shapeType != null) {
      handleToolTap(shapeType);
      return;
    }

    switch (action) {
      case 'undo':
        nativeToolbarAnnotationState?.undo();
        return;
      case 'redo':
        nativeToolbarAnnotationState?.redo();
        return;
      default:
        handleNativeToolbarAction(action);
        return;
    }
  }
}
