import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../models/capture_style_settings.dart';

const kCaptureShadowSigma = 8.0;
const kCaptureShadowOffset = Offset(0, 8);
const kCaptureShadowColor = Color(0x40000000);

@immutable
class CaptureStyleLayout {
  const CaptureStyleLayout({
    required this.contentSize,
    required this.contentRect,
    required this.outerSize,
    required this.outerInsets,
    required this.borderRadius,
    required this.shadowEnabled,
  });

  final Size contentSize;
  final Rect contentRect;
  final Size outerSize;
  final EdgeInsets outerInsets;
  final double borderRadius;
  final bool shadowEnabled;
}

CaptureStyleLayout computeCaptureStyleLayout(
  Size contentSize,
  CaptureStyleSettings settings,
) {
  final safeContentWidth = math.max(contentSize.width, 1.0);
  final safeContentHeight = math.max(contentSize.height, 1.0);
  final maxRadius = math.min(safeContentWidth, safeContentHeight) / 2;
  final borderRadius = settings.borderRadius.clamp(0.0, maxRadius);
  final padding = math.max(settings.padding, 0.0);

  final shadowExtent = settings.shadowEnabled ? kCaptureShadowSigma * 3 : 0.0;
  final shadowInsets = settings.shadowEnabled
      ? EdgeInsets.fromLTRB(
          shadowExtent,
          shadowExtent,
          shadowExtent,
          shadowExtent + kCaptureShadowOffset.dy,
        )
      : EdgeInsets.zero;
  final outerInsets = EdgeInsets.fromLTRB(
    shadowInsets.left + padding,
    shadowInsets.top + padding,
    shadowInsets.right + padding,
    shadowInsets.bottom + padding,
  );
  final contentRect = Rect.fromLTWH(
    outerInsets.left,
    outerInsets.top,
    safeContentWidth,
    safeContentHeight,
  );

  return CaptureStyleLayout(
    contentSize: Size(safeContentWidth, safeContentHeight),
    contentRect: contentRect,
    outerSize: Size(
      safeContentWidth + outerInsets.horizontal,
      safeContentHeight + outerInsets.vertical,
    ),
    outerInsets: outerInsets,
    borderRadius: borderRadius,
    shadowEnabled: settings.shadowEnabled,
  );
}

Rect projectCaptureStyleRect(
  Rect sourceRect, {
  required Size sourceBounds,
  required Rect destinationBounds,
}) {
  final scaleX = destinationBounds.width / sourceBounds.width;
  final scaleY = destinationBounds.height / sourceBounds.height;
  return Rect.fromLTWH(
    destinationBounds.left + (sourceRect.left * scaleX),
    destinationBounds.top + (sourceRect.top * scaleY),
    sourceRect.width * scaleX,
    sourceRect.height * scaleY,
  );
}

void paintCaptureShadow(
  ui.Canvas canvas, {
  required Rect contentRect,
  required double borderRadius,
  required bool shadowEnabled,
}) {
  if (!shadowEnabled) return;

  final shadowPaint = ui.Paint()
    ..color = kCaptureShadowColor
    ..maskFilter = const ui.MaskFilter.blur(
      ui.BlurStyle.normal,
      kCaptureShadowSigma,
    );
  final shadowRect = contentRect.shift(kCaptureShadowOffset);
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(shadowRect, ui.Radius.circular(borderRadius)),
    shadowPaint,
  );
}

Future<ui.Image> renderCaptureStyle(
  ui.Image source,
  CaptureStyleSettings settings,
) async {
  final layout = computeCaptureStyleLayout(
    Size(source.width.toDouble(), source.height.toDouble()),
    settings,
  );

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);

  paintCaptureShadow(
    canvas,
    contentRect: layout.contentRect,
    borderRadius: layout.borderRadius,
    shadowEnabled: layout.shadowEnabled,
  );

  final clipRRect = ui.RRect.fromRectAndRadius(
    layout.contentRect,
    ui.Radius.circular(layout.borderRadius),
  );
  canvas.save();
  canvas.clipRRect(clipRRect, doAntiAlias: true);
  canvas.drawImageRect(
    source,
    Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
    layout.contentRect,
    ui.Paint()..filterQuality = ui.FilterQuality.high,
  );
  canvas.restore();

  final picture = recorder.endRecording();
  final image = await picture.toImage(
    layout.outerSize.width.ceil(),
    layout.outerSize.height.ceil(),
  );
  picture.dispose();
  return image;
}
