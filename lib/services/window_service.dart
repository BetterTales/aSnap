import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../models/qr_code.dart';
import '../utils/macos_key_codes.dart';

/// A visible on-screen window detected via CGWindowListCopyWindowInfo.
class DetectedWindow {
  final Rect rect;
  const DetectedWindow({required this.rect});
}

/// Raw BGRA pixel data + the captured display's logical size and CG origin.
class ScreenCapture {
  /// Raw BGRA pixel bytes (no PNG encoding).
  final Uint8List bytes;

  /// Physical pixel dimensions of the captured image.
  final int pixelWidth;
  final int pixelHeight;

  /// Bytes per row (may include padding beyond pixelWidth × 4).
  final int bytesPerRow;

  /// Logical (point) size of the captured display.
  final Size screenSize;

  /// Top-left origin of this display in global CG coordinates.
  final Offset screenOrigin;

  const ScreenCapture({
    required this.bytes,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.bytesPerRow,
    required this.screenSize,
    required this.screenOrigin,
  });
}

class LaunchAtLoginState {
  const LaunchAtLoginState({
    required this.supported,
    required this.enabled,
    required this.requiresApproval,
  });

  factory LaunchAtLoginState.fromMap(Map<dynamic, dynamic> map) {
    return LaunchAtLoginState(
      supported: map['supported'] as bool? ?? false,
      enabled: map['enabled'] as bool? ?? false,
      requiresApproval: map['requiresApproval'] as bool? ?? false,
    );
  }

  final bool supported;
  final bool enabled;
  final bool requiresApproval;
}

enum NativeToolbarPlacement { belowWindow, belowAnchor }

class NativeToolbarRequest {
  const NativeToolbarRequest._({
    required this.placement,
    required this.anchorRect,
    required this.showPin,
    required this.showHistoryControls,
    required this.canUndo,
    required this.canRedo,
    required this.showOcr,
    required this.activeTool,
  });

  const NativeToolbarRequest.belowWindow({
    required bool showPin,
    required bool showHistoryControls,
    required bool canUndo,
    required bool canRedo,
    required bool showOcr,
    String? activeTool,
  }) : this._(
         placement: NativeToolbarPlacement.belowWindow,
         anchorRect: null,
         showPin: showPin,
         showHistoryControls: showHistoryControls,
         canUndo: canUndo,
         canRedo: canRedo,
         showOcr: showOcr,
         activeTool: activeTool,
       );

  const NativeToolbarRequest.belowAnchor({
    required Rect anchorRect,
    required bool showPin,
    required bool showHistoryControls,
    required bool canUndo,
    required bool canRedo,
    required bool showOcr,
    String? activeTool,
  }) : this._(
         placement: NativeToolbarPlacement.belowAnchor,
         anchorRect: anchorRect,
         showPin: showPin,
         showHistoryControls: showHistoryControls,
         canUndo: canUndo,
         canRedo: canRedo,
         showOcr: showOcr,
         activeTool: activeTool,
       );

  final NativeToolbarPlacement placement;
  final Rect? anchorRect;
  final bool showPin;
  final bool showHistoryControls;
  final bool canUndo;
  final bool canRedo;
  final bool showOcr;
  final String? activeTool;

  Map<String, Object?> toMap({required int requestId, required int sessionId}) {
    return {
      'placement': placement.name,
      if (anchorRect != null)
        'anchorRect': {
          'x': anchorRect!.left,
          'y': anchorRect!.top,
          'width': anchorRect!.width,
          'height': anchorRect!.height,
        },
      'showPin': showPin,
      'showHistoryControls': showHistoryControls,
      'canUndo': canUndo,
      'canRedo': canRedo,
      'showOcr': showOcr,
      'activeTool': activeTool,
      'requestId': requestId,
      'sessionId': sessionId,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NativeToolbarRequest &&
        other.placement == placement &&
        other.anchorRect == anchorRect &&
        other.showPin == showPin &&
        other.showHistoryControls == showHistoryControls &&
        other.canUndo == canUndo &&
        other.canRedo == canRedo &&
        other.showOcr == showOcr &&
        other.activeTool == activeTool;
  }

  @override
  int get hashCode => Object.hash(
    placement,
    anchorRect,
    showPin,
    showHistoryControls,
    canUndo,
    canRedo,
    showOcr,
    activeTool,
  );
}

class NativeToolbarFrameUpdate {
  const NativeToolbarFrameUpdate({
    required this.rect,
    required this.requestId,
    required this.sessionId,
  });

  factory NativeToolbarFrameUpdate.fromMap(Map<dynamic, dynamic> map) {
    return NativeToolbarFrameUpdate(
      rect: Rect.fromLTWH(
        (map['x'] as num).toDouble(),
        (map['y'] as num).toDouble(),
        (map['width'] as num).toDouble(),
        (map['height'] as num).toDouble(),
      ),
      requestId: (map['requestId'] as num).toInt(),
      sessionId: (map['sessionId'] as num).toInt(),
    );
  }

  final Rect rect;
  final int requestId;
  final int sessionId;
}

class WindowService {
  /// Minimum preview window size for normal (non-scroll) captures.
  /// Scroll captures use a fullscreen overlay instead of this window.
  static const _minPreviewSize = Size(80, 60);
  static const _windowsFixedScrollPreviewSize = Size(960, 720);
  static const _scrollPreviewMaxScreenFraction = 0.85;
  static const _channel = MethodChannel('com.asnap/window');
  int _toolbarRequestId = 0;
  final int _toolbarSessionId = DateTime.now().microsecondsSinceEpoch;
  Rect? _currentPreviewWindowRect;
  Rect? _currentPreviewScreenRect;

  /// Called when the native side detects a Space switch during overlay mode.
  VoidCallback? onOverlayCancelled;

  /// Called when the cursor moves to a different display during overlay mode.
  VoidCallback? onOverlayDisplayChanged;

  /// Called when the native Esc key monitor detects Escape during capture setup.
  VoidCallback? onEscPressed;

  /// Called when the native scroll-stop button is clicked.
  VoidCallback? onScrollCaptureDone;

  /// Called when background rect polling delivers updated window rects.
  /// Rects are in global CG coordinates (top-left origin).
  void Function(List<DetectedWindow> windows)? onRectsUpdated;

  /// Called when the user presses Space on a pinned image panel (edit request).
  void Function(int panelId)? onEditPinnedImage;

  /// Called when the user presses Escape on a pinned image panel (close/destroy).
  void Function(int panelId)? onPinnedImageClosed;

  /// Called when a native floating toolbar button is pressed.
  void Function(String action)? onToolbarAction;

  /// Called when the native ink shortcut is pressed.
  VoidCallback? onInkKeyDown;

  /// Called when the native ink shortcut is released.
  VoidCallback? onInkKeyUp;

  /// Called when the native laser shortcut is pressed.
  VoidCallback? onLaserKeyDown;

  /// Called when the native laser shortcut is released.
  VoidCallback? onLaserKeyUp;

  /// Called when the overlay is armed for click-through dismissal and the
  /// next passthrough click is observed by the native host.
  VoidCallback? onOverlayPassthroughClick;

  /// Called after the native floating toolbar panel resolves its actual frame.
  ///
  /// The frame is reported in Flutter-local coordinates with a top-left origin.
  void Function(NativeToolbarFrameUpdate update)? onToolbarFrameChanged;

  /// True when a region selection is active (post-selection) in the overlay.
  /// Used to decide how to handle multi-display cursor moves.
  bool overlaySelectionActive = false;

  Rect? get currentPreviewWindowRect => _currentPreviewWindowRect;
  Rect? get currentPreviewScreenRect => _currentPreviewScreenRect;

  bool _effectivePreviewShadow(bool useNativeShadow) {
    if (Platform.isWindows) {
      return false;
    }
    return useNativeShadow;
  }

  TitleBarStyle _previewTitleBarStyle() {
    return Platform.isWindows ? TitleBarStyle.normal : TitleBarStyle.hidden;
  }

  bool _previewWindowButtonsVisible() {
    return !Platform.isWindows;
  }

  Future<void> ensureInitialized() async {
    await windowManager.ensureInitialized();

    // Listen for native → Dart callbacks
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onOverlayCancelled') {
        onOverlayCancelled?.call();
      } else if (call.method == 'onOverlayDisplayChanged') {
        onOverlayDisplayChanged?.call();
      } else if (call.method == 'onEscPressed') {
        onEscPressed?.call();
      } else if (call.method == 'onInkKeyDown') {
        onInkKeyDown?.call();
      } else if (call.method == 'onInkKeyUp') {
        onInkKeyUp?.call();
      } else if (call.method == 'onLaserKeyDown') {
        onLaserKeyDown?.call();
      } else if (call.method == 'onLaserKeyUp') {
        onLaserKeyUp?.call();
      } else if (call.method == 'onOverlayPassthroughClick') {
        onOverlayPassthroughClick?.call();
      } else if (call.method == 'onScrollCaptureDone') {
        onScrollCaptureDone?.call();
      } else if (call.method == 'onEditPinnedImage') {
        final args = call.arguments as Map<dynamic, dynamic>?;
        final panelId = (args?['panelId'] as num?)?.toInt();
        if (panelId != null) onEditPinnedImage?.call(panelId);
      } else if (call.method == 'onPinnedImageClosed') {
        final args = call.arguments as Map<dynamic, dynamic>?;
        final panelId = (args?['panelId'] as num?)?.toInt();
        if (panelId != null) onPinnedImageClosed?.call(panelId);
      } else if (call.method == 'onToolbarAction') {
        final args = call.arguments as Map<dynamic, dynamic>?;
        final action = args?['action'] as String?;
        if (action != null) onToolbarAction?.call(action);
      } else if (call.method == 'onToolbarFrameChanged') {
        final args = call.arguments as Map<dynamic, dynamic>?;
        if (args == null) return;
        final update = NativeToolbarFrameUpdate.fromMap(args);
        if (update.sessionId != _toolbarSessionId) return;
        if (update.requestId != _toolbarRequestId) return;
        onToolbarFrameChanged?.call(update);
      } else if (call.method == 'onRectsUpdated') {
        final rawList = call.arguments as List<dynamic>?;
        if (rawList != null) {
          final windows = rawList.map((entry) {
            final map = Map<String, dynamic>.from(entry as Map);
            return DetectedWindow(
              rect: Rect.fromLTWH(
                (map['x'] as num).toDouble(),
                (map['y'] as num).toDouble(),
                (map['width'] as num).toDouble(),
                (map['height'] as num).toDouble(),
              ),
            );
          }).toList();
          onRectsUpdated?.call(windows);
        }
      }
    });

    if (Platform.isMacOS) {
      try {
        await _channel.invokeMethod('resetToolbarPanelState');
      } on MissingPluginException {
        // Older/native-mismatched builds may not expose this method.
      }
    }
  }

  Future<void> hideOnReady() async {
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1, 1),
        center: false,
        skipTaskbar: true,
        titleBarStyle: TitleBarStyle.hidden,
      ),
      () async {
        await windowManager.hide();
        await windowManager.setSkipTaskbar(true);
        await windowManager.setPreventClose(true);
      },
    );
  }

  Future<void> _prepareWindowsFullscreenOverlayWindow() async {
    if (!Platform.isWindows) return;
    await windowManager.setMinimumSize(const Size(0, 0));
    await windowManager.setMaximumSize(
      const Size(double.infinity, double.infinity),
    );
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.setHasShadow(false);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(true);
  }

  /// Show the preview window sized to the image.
  Future<Size?> showPreview({
    required int imageWidth,
    required int imageHeight,
    required Size screenSize,
    required Offset screenOrigin,
    double opacity = 1.0,
    bool focus = true,
    bool useNativeShadow = true,
  }) async {
    if (imageWidth <= 0 || imageHeight <= 0) return null;
    final effectiveUseNativeShadow = _effectivePreviewShadow(useNativeShadow);

    // Ensure hidden before cleanup to avoid any transient redraw while
    // transitioning from full-screen overlay to preview.
    await windowManager.hide();
    // Clean overlay state first in case we're coming from region selection.
    // Avoids styleMask restoration while hidden, which can flash on macOS.
    await _channel.invokeMethod('cleanupOverlayMode');

    final maxW = screenSize.width * 0.8;
    final maxH = screenSize.height * 0.8;
    const reservedToolbarHeight = 0.0;
    final maxImageH = (maxH - reservedToolbarHeight).clamp(1.0, maxH);

    // Size window to image aspect ratio (toolbar floats over image)
    final imageAspect = imageWidth / imageHeight;
    var winW = imageWidth.toDouble();
    var winH = imageHeight.toDouble();

    if (winW > maxW) {
      winW = maxW;
      winH = winW / imageAspect;
    }
    if (winH > maxImageH) {
      winH = maxImageH;
      winW = winH * imageAspect;
    }

    winW = winW.clamp(_minPreviewSize.width, maxW);
    final minImageH = maxImageH < _minPreviewSize.height
        ? maxImageH
        : _minPreviewSize.height;
    winH = winH.clamp(minImageH, maxImageH);

    final previewSize = Size(winW, winH + reservedToolbarHeight);

    await windowManager.setMinimumSize(const Size(0, 0));
    await windowManager.setMaximumSize(
      Size(screenSize.width, screenSize.height),
    );
    await windowManager.setTitleBarStyle(
      _previewTitleBarStyle(),
      windowButtonVisibility: _previewWindowButtonsVisible(),
    );
    await windowManager.setSize(previewSize);
    await windowManager.setMinimumSize(previewSize);
    await windowManager.setMaximumSize(previewSize);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(true);
    await windowManager.setHasShadow(effectiveUseNativeShadow);
    if (Platform.isMacOS || Platform.isWindows) {
      try {
        await _channel.invokeMethod('preparePreviewWindow', {
          'useNativeShadow': effectiveUseNativeShadow,
        });
      } on MissingPluginException {
        // Older or mismatched native builds may not implement this method.
      }
    }

    // Center on the cursor's display
    final x = screenOrigin.dx + (screenSize.width - previewSize.width) / 2;
    final y = screenOrigin.dy + (screenSize.height - previewSize.height) / 2;
    await windowManager.setPosition(Offset(x, y));
    _currentPreviewWindowRect = Rect.fromLTWH(
      x,
      y,
      previewSize.width,
      previewSize.height,
    );
    _currentPreviewScreenRect = Rect.fromLTWH(
      screenOrigin.dx,
      screenOrigin.dy,
      screenSize.width,
      screenSize.height,
    );

    // Restore opacity right before show — cleanupOverlayState leaves alpha=0
    // to prevent flash during styleMask restoration.
    await windowManager.setOpacity(opacity);
    await windowManager.show();
    if (opacity > 0.99) {
      await _channel.invokeMethod('flushPendingToolbarPanel');
    }
    if (focus) {
      await _focusAndActivateWindow();

      // One more pass right after show to avoid focus races during
      // overlay -> preview transitions.
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await _focusAndActivateWindow();
    }

    return previewSize;
  }

  /// Show the overlay window covering the entire screen including the menu bar.
  /// Uses a native platform channel to set a borderless window above everything.
  ///
  /// When [screenOrigin] is provided (CG coordinates), the native side targets
  /// that exact display instead of re-reading the mouse position.  This avoids
  /// a race condition where the cursor may have moved between captureScreen and
  /// enterOverlayMode.
  Future<void> showFullScreenOverlay({Offset? screenOrigin}) async {
    await _prepareWindowsFullscreenOverlayWindow();
    final args = screenOrigin != null
        ? {'screenOriginX': screenOrigin.dx, 'screenOriginY': screenOrigin.dy}
        : null;
    await _channel.invokeMethod('enterOverlayMode', args);
  }

  /// Show a transparent full-screen overlay for ink drawing.
  Future<void> enterInkOverlay({Offset? screenOrigin}) async {
    await _prepareWindowsFullscreenOverlayWindow();
    final args = screenOrigin != null
        ? {'screenOriginX': screenOrigin.dx, 'screenOriginY': screenOrigin.dy}
        : null;
    if (Platform.isMacOS || Platform.isWindows) {
      await _channel.invokeMethod('enterInkOverlayMode', args);
      return;
    }
    await _channel.invokeMethod('enterOverlayMode', args);
  }

  /// Reveal the prepared ink overlay after Flutter has rendered its first frame.
  Future<void> revealInkOverlay() async {
    if (Platform.isMacOS || Platform.isWindows) {
      await _channel.invokeMethod('revealInkOverlay');
      return;
    }
    await _channel.invokeMethod('revealOverlay');
  }

  /// Fully exit overlay mode: restore window style, level, observers.
  Future<void> exitOverlay() async {
    await _channel.invokeMethod('exitOverlayMode');
  }

  Future<void> setOverlayMousePassthrough({required bool passthrough}) async {
    if (!Platform.isMacOS && !Platform.isWindows) return;
    await _channel.invokeMethod('setOverlayMousePassthrough', {
      'passthrough': passthrough,
    });
  }

  Future<void> setOverlayDismissOnNextClick({required bool enabled}) async {
    if (!Platform.isMacOS && !Platform.isWindows) return;
    await _channel.invokeMethod('setOverlayDismissOnNextClick', {
      'enabled': enabled,
    });
  }

  Future<void> setOverlayCursorHidden({required bool hidden}) async {
    if (!Platform.isMacOS) return;
    await _channel.invokeMethod('setOverlayCursorHidden', {'hidden': hidden});
  }

  /// Clean overlay-only state without restoring styleMask.
  /// Use this for fast transitions where restoring style can flash.
  Future<void> cleanupOverlay() async {
    await _channel.invokeMethod('cleanupOverlayMode');
  }

  /// Make overlay invisible (alpha=0) for display switching.
  /// The window stays in the compositor so Flutter keeps rendering to its
  /// backing store — no surface release/reacquire flash.
  Future<void> suspendOverlay() async {
    await _channel.invokeMethod('suspendOverlay');
  }

  /// Move the invisible overlay to a new display (setFrame only).
  /// Window stays alpha=0 so Flutter can render the new content at the
  /// correct display size before [revealOverlay] makes it visible.
  Future<void> repositionOverlay({required Offset screenOrigin}) async {
    await _channel.invokeMethod('repositionOverlay', {
      'screenOriginX': screenOrigin.dx,
      'screenOriginY': screenOrigin.dy,
    });
  }

  /// Reveal the overlay (alpha=1) after Flutter has rendered the new content.
  /// Also re-activates the window and reinstalls display-change monitors.
  Future<void> revealOverlay() async {
    await _channel.invokeMethod('revealOverlay');
  }

  /// Show the preview window at an exact position and size.
  ///
  /// Unlike [showPreview] (which centers + scales), this method positions the
  /// window at the given [rect] in CG coordinates (top-left origin, absolute).
  /// It performs full window cleanup (overlay teardown, opacity restoration)
  /// making it safe to call after [suspendOverlay].
  Future<void> showPreviewAtRect({
    required Rect rect,
    double opacity = 1.0,
    bool focus = true,
    bool useNativeShadow = true,
  }) async {
    final effectiveUseNativeShadow = _effectivePreviewShadow(useNativeShadow);
    await windowManager.hide();
    await _channel.invokeMethod('cleanupOverlayMode');

    final size = Size(rect.width, rect.height);
    await windowManager.setMinimumSize(const Size(0, 0));
    await windowManager.setMaximumSize(
      const Size(double.infinity, double.infinity),
    );
    await windowManager.setTitleBarStyle(
      _previewTitleBarStyle(),
      windowButtonVisibility: _previewWindowButtonsVisible(),
    );
    await windowManager.setSize(size);
    await windowManager.setMinimumSize(size);
    await windowManager.setMaximumSize(size);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(true);
    await windowManager.setHasShadow(effectiveUseNativeShadow);
    if (Platform.isMacOS || Platform.isWindows) {
      try {
        await _channel.invokeMethod('preparePreviewWindow', {
          'useNativeShadow': effectiveUseNativeShadow,
        });
      } on MissingPluginException {
        // Older or mismatched native builds may not implement this method.
      }
    }
    await windowManager.setPosition(Offset(rect.left, rect.top));
    _currentPreviewWindowRect = rect;
    _currentPreviewScreenRect = await _screenRectForPoint(rect.center);

    await windowManager.setOpacity(opacity);
    await windowManager.show();
    if (opacity > 0.99) {
      await _channel.invokeMethod('flushPendingToolbarPanel');
    }
    if (focus) {
      await _focusAndActivateWindow();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await _focusAndActivateWindow();
    }
  }

  Future<void> revealPreviewWindow() async {
    // Use native method to reveal and trigger pending toolbar update.
    await _channel.invokeMethod('revealPreviewWindow');
    await _channel.invokeMethod('flushPendingToolbarPanel');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await _focusAndActivateWindow();
  }

  /// Shrink the overlay window in-place to the selection rect for preview.
  /// Stays borderless (no corner radius) and floating above other windows.
  /// Keeps the selected region size (toolbar is shown in a separate panel).
  Future<void> showPreviewInPlace({
    required Rect selectionRect,
    required Size screenSize,
    required Offset screenOrigin,
    bool useNativeShadow = false,
  }) async {
    await _channel.invokeMethod('resizeToRect', {
      'x': selectionRect.left,
      'y': selectionRect.top,
      'width': selectionRect.width,
      'height': selectionRect.height,
      'useNativeShadow': useNativeShadow,
    });
    _currentPreviewWindowRect = Rect.fromLTWH(
      selectionRect.left + screenOrigin.dx,
      selectionRect.top + screenOrigin.dy,
      selectionRect.width,
      selectionRect.height,
    );
    _currentPreviewScreenRect = Rect.fromLTWH(
      screenOrigin.dx,
      screenOrigin.dy,
      screenSize.width,
      screenSize.height,
    );
  }

  /// Capture the screen.
  ///
  /// When [allDisplays] is false (default), captures only the display under
  /// the mouse cursor (used for ⌘⇧1 fullscreen capture).  When true, captures
  /// all connected displays as a single composite (used for ⌘⇧2 region
  /// selection so the user can drag across monitors).
  Future<ScreenCapture?> captureScreen({
    bool allDisplays = false,
    bool includeLayeredWindows = true,
  }) async {
    final result = await _channel.invokeMethod<Map>('captureScreen', {
      'allDisplays': allDisplays,
      'includeLayeredWindows': includeLayeredWindows,
    });
    if (result == null) return null;
    return ScreenCapture(
      bytes: result['bytes'] as Uint8List,
      pixelWidth: (result['pixelWidth'] as num).toInt(),
      pixelHeight: (result['pixelHeight'] as num).toInt(),
      bytesPerRow: (result['bytesPerRow'] as num).toInt(),
      screenSize: Size(
        (result['screenWidth'] as num).toDouble(),
        (result['screenHeight'] as num).toDouble(),
      ),
      screenOrigin: Offset(
        (result['screenOriginX'] as num).toDouble(),
        (result['screenOriginY'] as num).toDouble(),
      ),
    );
  }

  /// Check macOS accessibility trust. When [prompt] is true, shows the TCC
  /// system dialog if not yet trusted. Returns true if accessibility is granted.
  Future<bool> checkAccessibility({bool prompt = false}) async {
    final result = await _channel.invokeMethod<bool>('checkAccessibility', {
      'prompt': prompt,
    });
    return result ?? false;
  }

  /// Install global + local Esc key monitors on the native side.
  /// Fires [onEscPressed] when Escape is pressed anywhere, even when the
  /// overlay window isn't visible yet (capture setup phase).
  Future<void> startEscMonitor() async {
    await _channel.invokeMethod('startEscMonitor');
  }

  /// Remove the native Esc key monitors. Safe to call even if not monitoring.
  Future<void> stopEscMonitor() async {
    await _channel.invokeMethod('stopEscMonitor');
  }

  Future<void> setInkShortcut(HotKey hotKey) async {
    if (!Platform.isMacOS) return;
    final keyCode = macOsKeyCodeForPhysicalKey(hotKey.physicalKey);
    if (keyCode == null) {
      throw Exception('Failed to encode ink shortcut key code.');
    }
    await _channel.invokeMethod('setInkShortcut', {
      'keyCode': keyCode,
      'modifiers': [...?hotKey.modifiers?.map((modifier) => modifier.name)],
    });
  }

  Future<void> setLaserShortcut(HotKey hotKey) async {
    if (!Platform.isMacOS) return;
    final keyCode = macOsKeyCodeForPhysicalKey(hotKey.physicalKey);
    if (keyCode == null) {
      throw Exception('Failed to encode laser shortcut key code.');
    }
    await _channel.invokeMethod('setLaserShortcut', {
      'keyCode': keyCode,
      'modifiers': [...?hotKey.modifiers?.map((modifier) => modifier.name)],
    });
  }

  Future<void> startInkMonitor() async {
    if (!Platform.isMacOS) return;
    await _channel.invokeMethod('startInkMonitor');
  }

  Future<void> stopInkMonitor() async {
    if (!Platform.isMacOS) return;
    await _channel.invokeMethod('stopInkMonitor');
  }

  Future<void> resetInkMonitorState() async {
    if (!Platform.isMacOS) return;
    await _channel.invokeMethod('resetInkMonitorState');
  }

  /// Start background polling for window rects on a native background thread.
  /// Results are delivered periodically via [onRectsUpdated]. By default,
  /// this only gathers top-level window frames to avoid constant AX tree walks
  /// while idle.
  Future<void> startRectPolling({bool includeAxChildren = false}) async {
    await _channel.invokeMethod('startRectPolling', {
      'includeAxChildren': includeAxChildren,
    });
  }

  /// Stop background rect polling. Safe to call even if not polling.
  Future<void> stopRectPolling() async {
    await _channel.invokeMethod('stopRectPolling');
  }

  /// Fetch visible on-screen windows (excluding our own) in front-to-back Z-order.
  /// Coordinates are in CG points (top-left origin) matching Flutter logical coords.
  /// Prefer using pre-cached rects from [startRectPolling] when available.
  Future<List<DetectedWindow>> getWindowList() async {
    final List<dynamic>? rawList = await _channel.invokeMethod<List<dynamic>>(
      'getWindowList',
    );
    if (rawList == null) return [];

    return rawList.map((entry) {
      final map = Map<String, dynamic>.from(entry as Map);
      return DetectedWindow(
        rect: Rect.fromLTWH(
          (map['x'] as num).toDouble(),
          (map['y'] as num).toDouble(),
          (map['width'] as num).toDouble(),
          (map['height'] as num).toDouble(),
        ),
      );
    }).toList();
  }

  /// Real-time AX hit-test: find the deepest accessible element at [cgPoint]
  /// (global CG coordinates, top-left origin). Returns the element's rect
  /// or `null` if nothing meaningful was found. Much more reliable than
  /// pre-walking the entire AX tree (which can hit the 10 000-rect cap
  /// before reaching some apps like Codex).
  Future<Rect?> hitTestElement(Offset cgPoint) async {
    final result = await _channel.invokeMethod<Map>('hitTestElement', {
      'x': cgPoint.dx,
      'y': cgPoint.dy,
    });
    if (result == null) return null;
    return Rect.fromLTWH(
      (result['x'] as num).toDouble(),
      (result['y'] as num).toDouble(),
      (result['width'] as num).toDouble(),
      (result['height'] as num).toDouble(),
    );
  }

  /// Capture a rectangular region of the screen.
  /// [region] is in CG coordinates (top-left origin).
  /// When [includeLayeredWindows] is false, layered/topmost overlays are
  /// excluded where the platform capture API supports it.
  /// Returns raw BGRA pixel data, or null if capture fails.
  Future<ScreenCapture?> captureRegion(
    Rect region, {
    bool includeLayeredWindows = true,
  }) async {
    final result = await _channel.invokeMethod<Map>('captureRegion', {
      'x': region.left,
      'y': region.top,
      'width': region.width,
      'height': region.height,
      'includeLayeredWindows': includeLayeredWindows,
    });
    if (result == null) return null;
    return ScreenCapture(
      bytes: result['bytes'] as Uint8List,
      pixelWidth: (result['pixelWidth'] as num).toInt(),
      pixelHeight: (result['pixelHeight'] as num).toInt(),
      bytesPerRow: (result['bytesPerRow'] as num).toInt(),
      screenSize: Size(
        (result['screenWidth'] as num).toDouble(),
        (result['screenHeight'] as num).toDouble(),
      ),
      screenOrigin: Offset(
        (result['screenOriginX'] as num).toDouble(),
        (result['screenOriginY'] as num).toDouble(),
      ),
    );
  }

  /// Show a small native button covering [cgRect] (screen coordinates) so the
  /// "Done" affordance in the Flutter overlay becomes clickable. The overlay
  /// window ignores mouse events for scroll passthrough, so this separate
  /// native surface provides the click target.
  Future<void> showScrollStopButton(Rect cgRect) async {
    await _channel.invokeMethod('showScrollStopButton', {
      'x': cgRect.left,
      'y': cgRect.top,
      'width': cgRect.width,
      'height': cgRect.height,
    });
  }

  /// Remove the native scroll-stop button.
  Future<void> hideScrollStopButton() async {
    await _channel.invokeMethod('hideScrollStopButton');
  }

  /// Transition the full-screen overlay to scroll capture mode.
  /// Keeps the window at full-screen size but makes it non-interactive
  /// (`ignoresMouseEvents = true`) and transparent. The Flutter widget
  /// renders the rainbow border and live preview panel.
  Future<void> enterScrollCaptureMode() async {
    await _channel.invokeMethod('enterScrollCaptureMode');
  }

  /// Transition from scroll capture mode back to interactive overlay.
  /// Re-enables mouse events while keeping the window fullscreen and borderless.
  Future<void> exitScrollCaptureMode() async {
    await _channel.invokeMethod('exitScrollCaptureMode');
  }

  Size _windowsScrollPreviewSize(Size screenSize) {
    final maxWidth = screenSize.width * _scrollPreviewMaxScreenFraction;
    final maxHeight = screenSize.height * _scrollPreviewMaxScreenFraction;
    final width = _windowsFixedScrollPreviewSize.width.clamp(
      _minPreviewSize.width,
      maxWidth,
    );
    final height = _windowsFixedScrollPreviewSize.height.clamp(
      _minPreviewSize.height,
      maxHeight,
    );
    return Size(width, height);
  }

  /// Show scroll capture preview: fixed window sized for tall images.
  /// Returns the computed window size for toolbar positioning.
  Future<Size?> showScrollPreview({
    required int imageWidth,
    required int imageHeight,
    required Size screenSize,
    required Offset screenOrigin,
    double opacity = 1.0,
    bool focus = true,
  }) async {
    if (imageWidth <= 0 || imageHeight <= 0) return null;
    final effectiveUseNativeShadow = _effectivePreviewShadow(true);

    // Ensure hidden before cleanup to avoid transition flash.
    await windowManager.hide();
    // Same as showPreview(): cleanup without style restoration to prevent flash.
    await _channel.invokeMethod('cleanupOverlayMode');
    final previewSize = Platform.isWindows
        ? _windowsScrollPreviewSize(screenSize)
        : () {
            final maxW = screenSize.width * 0.8;
            final maxH = screenSize.height * 0.85;
            const reservedToolbarHeight = 0.0;
            final maxImageH = (maxH - reservedToolbarHeight).clamp(1.0, maxH);

            // Size to image aspect ratio, clamped to screen bounds.
            // Tall scroll captures will naturally be constrained by maxH
            // and the Flutter widget provides scrolling.
            final imageAspect = imageWidth / imageHeight;
            var winW = imageWidth.toDouble();
            var winH = imageHeight.toDouble();

            if (winW > maxW) {
              winW = maxW;
              winH = winW / imageAspect;
            }
            if (winH > maxImageH) {
              winH = maxImageH;
              winW = winH * imageAspect;
            }

            winW = winW.clamp(_minPreviewSize.width, maxW);
            final minImageH = maxImageH < _minPreviewSize.height
                ? maxImageH
                : _minPreviewSize.height;
            winH = winH.clamp(minImageH, maxImageH);

            return Size(winW, winH + reservedToolbarHeight);
          }();

    await windowManager.setMinimumSize(const Size(0, 0));
    await windowManager.setMaximumSize(
      Size(screenSize.width, screenSize.height),
    );
    await windowManager.setTitleBarStyle(
      _previewTitleBarStyle(),
      windowButtonVisibility: _previewWindowButtonsVisible(),
    );
    await windowManager.setSize(previewSize);
    await windowManager.setMinimumSize(previewSize);
    await windowManager.setMaximumSize(previewSize);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(true);
    await windowManager.setHasShadow(effectiveUseNativeShadow);
    if (Platform.isMacOS || Platform.isWindows) {
      try {
        await _channel.invokeMethod('preparePreviewWindow', {
          'useNativeShadow': effectiveUseNativeShadow,
        });
      } on MissingPluginException {
        // Older or mismatched native builds may not implement this method.
      }
    }

    final x = screenOrigin.dx + (screenSize.width - previewSize.width) / 2;
    final y = screenOrigin.dy + (screenSize.height - previewSize.height) / 2;
    await windowManager.setPosition(Offset(x, y));
    _currentPreviewWindowRect = Rect.fromLTWH(
      x,
      y,
      previewSize.width,
      previewSize.height,
    );
    _currentPreviewScreenRect = Rect.fromLTWH(
      screenOrigin.dx,
      screenOrigin.dy,
      screenSize.width,
      screenSize.height,
    );

    // Restore opacity right before show — cleanupOverlayState leaves alpha=0
    // to prevent flash during styleMask restoration.
    await windowManager.setOpacity(opacity);
    await windowManager.show();
    if (opacity > 0.99) {
      await _channel.invokeMethod('flushPendingToolbarPanel');
    }
    if (focus) {
      await _focusAndActivateWindow();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await _focusAndActivateWindow();
    }

    return previewSize;
  }

  Future<void> hidePreview() async {
    // On macOS we defer overlay cleanup to the next show transition to avoid
    // a flash during style restoration. On Windows we restore immediately so
    // popup/overlay window styles do not leave behind stale frame artifacts.
    _currentPreviewWindowRect = null;
    _currentPreviewScreenRect = null;
    unawaited(hideToolbarPanel());
    if (Platform.isWindows) {
      await _channel.invokeMethod('dismissAppWindow');
      await windowManager.hide();
      await hideScrollStopButton();
      await windowManager.setAlwaysOnTop(false);
      return;
    }
    await windowManager.hide();
    // Window is already invisible — no need to block on this.
    unawaited(windowManager.setAlwaysOnTop(false));
  }

  Future<void> showSettingsWindow() async {
    await windowManager.hide();
    _currentPreviewWindowRect = null;
    _currentPreviewScreenRect = null;
    await _channel.invokeMethod('cleanupOverlayMode');

    const windowSize = Size(900, 620);
    await windowManager.setMinimumSize(const Size(0, 0));
    await windowManager.setMaximumSize(
      const Size(double.infinity, double.infinity),
    );
    await windowManager.setTitleBarStyle(
      Platform.isWindows ? TitleBarStyle.normal : TitleBarStyle.hidden,
      windowButtonVisibility: !Platform.isWindows,
    );
    await windowManager.setSize(windowSize);
    await windowManager.setMinimumSize(windowSize);
    await windowManager.setMaximumSize(windowSize);
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setSkipTaskbar(true);
    await windowManager.setHasShadow(true);
    await windowManager.center();

    if (Platform.isWindows) {
      // On Windows, applying the settings size while the window is hidden can
      // leave Flutter rendering the first shown frame at the stale hidden size
      // until the user manually resizes the window. Show it transparent first,
      // then repeat the fixed-size bounds update once it is visible so the
      // initial WM_SIZE reaches the embedded Flutter view.
      await windowManager.setOpacity(0.0);
      await windowManager.show();
      await Future<void>.delayed(const Duration(milliseconds: 16));
      await windowManager.setSize(windowSize);
      await windowManager.center();
    }

    await windowManager.setOpacity(1.0);
    await windowManager.show();
    await _focusAndActivateWindow();
  }

  /// Show/update the native floating toolbar panel.
  ///
  /// Flutter sends placement intent and state; AppKit computes the real panel
  /// geometry and reports the resolved frame back asynchronously.
  Future<void> showToolbarPanel({required NativeToolbarRequest request}) async {
    if (!Platform.isMacOS && !Platform.isWindows) return;
    final requestId = ++_toolbarRequestId;
    try {
      await _channel.invokeMethod(
        'showToolbarPanel',
        request.toMap(requestId: requestId, sessionId: _toolbarSessionId),
      );
    } on MissingPluginException {
      // Non-macOS runners may not provide this channel implementation.
      return;
    }
  }

  /// Hide the native floating toolbar panel.
  Future<void> hideToolbarPanel() async {
    if (!Platform.isMacOS && !Platform.isWindows) return;
    final requestId = ++_toolbarRequestId;
    try {
      await _channel.invokeMethod('hideToolbarPanel', {
        'requestId': requestId,
        'sessionId': _toolbarSessionId,
      });
    } on MissingPluginException {
      // Non-macOS runners may not provide this channel implementation.
      return;
    }
  }

  Future<String?> recognizeText({
    required Uint8List pngBytes,
    List<String>? languages,
  }) async {
    if (!Platform.isMacOS) return null;
    try {
      final result = await _channel.invokeMethod<String>('recognizeText', {
        'pngBytes': pngBytes,
        if (languages != null && languages.isNotEmpty) 'languages': languages,
      });
      return result;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<List<QrCodeResult>> detectQRCodes({
    required Uint8List pngBytes,
  }) async {
    if (!Platform.isMacOS) return const [];
    try {
      final result = await _channel.invokeMethod<List>('detectQRCodes', {
        'pngBytes': pngBytes,
      });
      if (result == null || result.isEmpty) return const [];
      final codes = <QrCodeResult>[];
      for (final entry in result) {
        if (entry is! Map) continue;
        final parsed = QrCodeResult.maybeParse(entry);
        if (parsed != null) codes.add(parsed);
      }
      return codes;
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  Future<bool> openUrl(String url) async {
    if (!Platform.isMacOS) return false;
    try {
      final result = await _channel.invokeMethod<bool>('openUrl', {'url': url});
      return result ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<LaunchAtLoginState> getLaunchAtLoginState() async {
    if (!Platform.isMacOS) {
      return const LaunchAtLoginState(
        supported: false,
        enabled: false,
        requiresApproval: false,
      );
    }

    try {
      final result = await _channel.invokeMethod<Map>('getLaunchAtLoginState');
      if (result == null) {
        return const LaunchAtLoginState(
          supported: false,
          enabled: false,
          requiresApproval: false,
        );
      }
      return LaunchAtLoginState.fromMap(result);
    } on MissingPluginException {
      return const LaunchAtLoginState(
        supported: false,
        enabled: false,
        requiresApproval: false,
      );
    }
  }

  Future<LaunchAtLoginState> setLaunchAtLoginEnabled(bool enabled) async {
    if (!Platform.isMacOS) {
      return const LaunchAtLoginState(
        supported: false,
        enabled: false,
        requiresApproval: false,
      );
    }

    try {
      final result = await _channel.invokeMethod<Map>(
        'setLaunchAtLoginEnabled',
        {'enabled': enabled},
      );
      if (result == null) {
        return const LaunchAtLoginState(
          supported: false,
          enabled: false,
          requiresApproval: false,
        );
      }
      return LaunchAtLoginState.fromMap(result);
    } on MissingPluginException {
      return const LaunchAtLoginState(
        supported: false,
        enabled: false,
        requiresApproval: false,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Pinned image panel
  // ---------------------------------------------------------------------------

  /// Pin an image as a floating native panel.
  ///
  /// [bytes] must be raw RGBA pixel data. [cgFrame] is an optional
  /// CG-coordinate rect (top-left origin) specifying the panel's screen
  /// position and size. If omitted, the panel appears at the current main
  /// Flutter window frame. Returns the native pinned panel ID on success.
  Future<int?> pinImage({
    required Uint8List bytes,
    required int width,
    required int height,
    Rect? cgFrame,
    bool useNativeShadow = true,
  }) async {
    final args = <String, dynamic>{
      'bytes': bytes,
      'width': width,
      'height': height,
      'useNativeShadow': useNativeShadow,
    };
    if (cgFrame != null) {
      args['frameX'] = cgFrame.left;
      args['frameY'] = cgFrame.top;
      args['frameWidth'] = cgFrame.width;
      args['frameHeight'] = cgFrame.height;
    }
    return (await _channel.invokeMethod<num>('pinImage', args))?.toInt();
  }

  /// Close and destroy a native pinned image panel.
  /// When [panelId] is omitted, closes all pinned panels.
  Future<void> closePinnedImage({int? panelId}) async {
    final args = panelId == null ? null : {'panelId': panelId};
    await _channel.invokeMethod('closePinnedImage', args);
  }

  /// Get the current CG-coordinate frame of a pinned image panel.
  /// Returns null if the requested panel does not exist.
  Future<Rect?> getPinnedPanelFrame({int? panelId}) async {
    final args = panelId == null ? null : {'panelId': panelId};
    final result = await _channel.invokeMethod<Map>(
      'getPinnedPanelFrame',
      args,
    );
    if (result == null) return null;
    return Rect.fromLTWH(
      (result['x'] as num).toDouble(),
      (result['y'] as num).toDouble(),
      (result['width'] as num).toDouble(),
      (result['height'] as num).toDouble(),
    );
  }

  /// Get screen info (logical size + CG origin) for the display under the cursor.
  /// Uses [captureScreen] metadata to avoid a separate native bridge.
  Future<({Size screenSize, Offset screenOrigin})?> getScreenInfo() async {
    final capture = await captureScreen();
    if (capture == null) return null;
    return (screenSize: capture.screenSize, screenOrigin: capture.screenOrigin);
  }

  Future<void> _focusAndActivateWindow() async {
    await windowManager.focus();
    // Accessory apps can be visible but not active; activate explicitly so
    // keyboard events (Esc, shortcuts) route to our window immediately.
    await _channel.invokeMethod('activateApp');
  }

  Future<Rect?> _screenRectForPoint(Offset point) async {
    final result = await _channel.invokeMethod<Map>('getScreenInfoForPoint', {
      'x': point.dx,
      'y': point.dy,
    });
    if (result == null) return null;
    return Rect.fromLTWH(
      (result['screenOriginX'] as num).toDouble(),
      (result['screenOriginY'] as num).toDouble(),
      (result['screenWidth'] as num).toDouble(),
      (result['screenHeight'] as num).toDouble(),
    );
  }
}
