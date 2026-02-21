import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

class WindowService {
  static const _minPreviewSize = Size(400, 300);
  static const _channel = MethodChannel('com.asnap/window');

  Future<void> ensureInitialized() async {
    await windowManager.ensureInitialized();
  }

  Future<void> hideOnReady() async {
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(200, 200),
        center: true,
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

  Future<void> showPreview({
    required int imageWidth,
    required int imageHeight,
  }) async {
    if (imageWidth <= 0 || imageHeight <= 0) return;

    // Exit overlay mode first in case we're coming from region selection
    await _channel.invokeMethod('exitOverlayMode');

    final display = await screenRetriever.getPrimaryDisplay();
    final screenSize = display.size;

    final maxW = screenSize.width * 0.8;
    final maxH = screenSize.height * 0.8;

    // Size window to image aspect ratio (toolbar floats over image)
    final imageAspect = imageWidth / imageHeight;
    var winW = imageWidth.toDouble();
    var winH = imageHeight.toDouble();

    if (winW > maxW) {
      winW = maxW;
      winH = winW / imageAspect;
    }
    if (winH > maxH) {
      winH = maxH;
      winW = winH * imageAspect;
    }

    winW = winW.clamp(_minPreviewSize.width, maxW);
    winH = winH.clamp(_minPreviewSize.height, maxH);

    final previewSize = Size(winW, winH);

    await windowManager.setMinimumSize(const Size(0, 0));
    await windowManager.setMaximumSize(
      Size(screenSize.width, screenSize.height),
    );
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.setSize(previewSize);
    await windowManager.setMinimumSize(previewSize);
    await windowManager.setMaximumSize(previewSize);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(true);
    await windowManager.setHasShadow(true);

    final x = (screenSize.width - previewSize.width) / 2;
    final y = (screenSize.height - previewSize.height) / 2;
    await windowManager.setPosition(Offset(x, y));

    await windowManager.show();
    await windowManager.focus();
  }

  /// Show the overlay window covering the entire screen including the menu bar.
  /// Uses a native platform channel to set a borderless window above everything.
  Future<void> showFullScreenOverlay() async {
    // Native call: borderless window, above menu bar, full screen frame
    await _channel.invokeMethod('enterOverlayMode');
  }

  /// Shrink the overlay window in-place to the selection rect for preview.
  /// Stays borderless (no corner radius) and floating above other windows.
  /// Enforces a minimum size so the toolbar always fits, expanding outward
  /// from the selection center if needed.
  Future<void> showPreviewInPlace({required Rect selectionRect}) async {
    // Enforce minimum so the toolbar never overflows
    final w = selectionRect.width.clamp(_minPreviewSize.width, double.infinity);
    final h = selectionRect.height.clamp(
      _minPreviewSize.height,
      double.infinity,
    );
    final rect = Rect.fromCenter(
      center: selectionRect.center,
      width: w,
      height: h,
    );

    await _channel.invokeMethod('resizeToRect', {
      'x': rect.left,
      'y': rect.top,
      'width': rect.width,
      'height': rect.height,
    });
  }

  Future<void> hidePreview() async {
    // Hide only — defer exitOverlayMode to the next showPreview() call.
    // Restoring styleMask on a "hidden" window can still flash because macOS
    // may briefly redisplay the window when styleMask changes.
    await windowManager.hide();
    await windowManager.setAlwaysOnTop(false);
  }
}
