import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class CaptureService {
  static const _windowChannel = MethodChannel('com.asnap/window');

  Future<Uint8List?> captureFullScreen() async {
    if (!await _ensurePermission()) return null;

    final imagePath = await _tempImagePath();
    // Call screencapture directly without -C to exclude the mouse cursor
    final result = await Process.run('/usr/sbin/screencapture', [
      '-x',
      imagePath,
    ]);
    if (result.exitCode != 0) return null;
    return _readFile(imagePath);
  }

  /// Crop a region from a decoded full-screen image.
  /// [physicalRect] is in physical pixel coordinates.
  /// Returns a new [ui.Image] — caller owns it and must dispose.
  Future<ui.Image?> cropImage(ui.Image source, ui.Rect physicalRect) async {
    final snappedLeft = physicalRect.left.floorToDouble();
    final snappedTop = physicalRect.top.floorToDouble();
    final snappedRight = physicalRect.right.ceilToDouble();
    final snappedBottom = physicalRect.bottom.ceilToDouble();

    final clampedLeft = snappedLeft.clamp(0.0, source.width.toDouble());
    final clampedTop = snappedTop.clamp(0.0, source.height.toDouble());
    final clampedRight = snappedRight.clamp(
      clampedLeft,
      source.width.toDouble(),
    );
    final clampedBottom = snappedBottom.clamp(
      clampedTop,
      source.height.toDouble(),
    );
    final srcRect = ui.Rect.fromLTWH(
      clampedLeft,
      clampedTop,
      (clampedRight - clampedLeft).clamp(0.0, source.width - clampedLeft),
      (clampedBottom - clampedTop).clamp(0.0, source.height - clampedTop),
    );

    if (srcRect.width <= 0 || srcRect.height <= 0) {
      return null;
    }

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final dstRect = ui.Rect.fromLTWH(0, 0, srcRect.width, srcRect.height);
    canvas.drawImageRect(source, srcRect, dstRect, ui.Paint());
    final picture = recorder.endRecording();

    final cropped = await picture.toImage(
      srcRect.width.round(),
      srcRect.height.round(),
    );
    picture.dispose();

    return cropped;
  }

  Future<bool> checkPermission() async {
    if (Platform.isMacOS) {
      try {
        final allowed = await _windowChannel.invokeMethod<bool>(
          'checkScreenCapturePermission',
        );
        return allowed ?? true;
      } on MissingPluginException {
        return true;
      } on PlatformException catch (error) {
        debugPrint('[aSnap] checkScreenCapturePermission failed: $error');
        return true;
      }
    }
    return true;
  }

  Future<void> requestPermission() async {
    if (Platform.isMacOS) {
      try {
        await _windowChannel.invokeMethod('requestScreenCapturePermission');
      } on MissingPluginException {
        // Ignore and fall back to opening System Settings below.
      } on PlatformException catch (error) {
        debugPrint('[aSnap] requestScreenCapturePermission failed: $error');
      }
      // Also open System Settings directly as a fallback
      await _openScreenRecordingSettings();
    }
  }

  /// Check permission and prompt if not granted. Returns true if allowed.
  Future<bool> _ensurePermission() async {
    if (!Platform.isMacOS) return true;

    final allowed = await checkPermission();
    if (!allowed) {
      debugPrint(
        '[aSnap] Screen recording permission not granted, opening System Settings...',
      );
      await _openScreenRecordingSettings();
      return false;
    }
    return true;
  }

  /// Open macOS System Settings > Privacy & Security > Screen Recording
  Future<void> _openScreenRecordingSettings() async {
    await Process.run('open', [
      'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture',
    ]);
  }

  Future<String> _tempImagePath() async {
    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${dir.path}/asnap_capture_$timestamp.png';
  }

  Future<Uint8List?> _readFile(String imagePath) async {
    final file = File(imagePath);
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      try {
        await file.delete();
      } catch (e) {
        debugPrint(
          '[aSnap] Failed to delete temp capture file at $imagePath: $e',
        );
      }
      return bytes;
    }
    return null;
  }
}
