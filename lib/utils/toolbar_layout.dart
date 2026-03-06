import 'package:flutter/painting.dart';

/// Reference toolbar footprint for placement calculations.
///
/// The visual toolbar can be scaled down by callers when available width is
/// smaller, but placement still starts from this baseline size.
const Size kToolbarSize = Size(536, 44);
const double kToolbarGap = 8.0;

/// Compute a toolbar rect relative to [anchorRect].
///
/// Priority: below anchor → above anchor → inside (bottom edge), with
/// horizontal clamping to keep the toolbar on-screen.
Rect computeToolbarRect({
  required Rect anchorRect,
  required Size screenSize,
  Size toolbarSize = kToolbarSize,
}) {
  var x = anchorRect.center.dx - toolbarSize.width / 2;
  double y;

  final belowY = anchorRect.bottom + kToolbarGap;
  final aboveY = anchorRect.top - toolbarSize.height - kToolbarGap;

  if (belowY + toolbarSize.height <= screenSize.height) {
    y = belowY;
  } else if (aboveY >= 0) {
    y = aboveY;
  } else {
    y = anchorRect.bottom - toolbarSize.height - kToolbarGap;
    if (y < anchorRect.top + kToolbarGap) {
      y = anchorRect.top + kToolbarGap;
    }
  }

  final maxX = screenSize.width - toolbarSize.width;
  if (maxX <= 0) {
    x = 0.0;
  } else {
    x = x.clamp(0.0, maxX);
  }
  return Rect.fromLTWH(x, y, toolbarSize.width, toolbarSize.height);
}

/// Compute a floating toolbar rect outside [anchorRect].
///
/// Placement priority: below anchor, then above anchor. If neither fits fully,
/// it pins to the nearest screen edge while staying outside the anchor area.
Rect computeFloatingToolbarRect({
  required Rect anchorRect,
  required Size screenSize,
  Size toolbarSize = kToolbarSize,
  EdgeInsets viewportPadding = const EdgeInsets.all(8),
}) {
  final minX = viewportPadding.left;
  final maxX = screenSize.width - viewportPadding.right - toolbarSize.width;
  final minY = viewportPadding.top;
  final maxY = screenSize.height - viewportPadding.bottom - toolbarSize.height;

  double x;
  if (maxX <= minX) {
    x = minX;
  } else {
    x = (anchorRect.center.dx - toolbarSize.width / 2).clamp(minX, maxX);
  }

  // Keep toolbar floating below anchor (never jump above).
  final y = (anchorRect.bottom + kToolbarGap).clamp(minY, maxY);

  return Rect.fromLTWH(x, y, toolbarSize.width, toolbarSize.height);
}

Rect computeToolbarRectBelowWindow({
  required Rect windowRect,
  required Rect screenRect,
}) {
  var x = windowRect.center.dx - kToolbarSize.width / 2;
  final minX = screenRect.left;
  final maxX = screenRect.right - kToolbarSize.width;
  if (maxX <= minX) {
    x = minX;
  } else {
    x = x.clamp(minX, maxX);
  }

  final minY = windowRect.bottom + kToolbarGap;
  final maxY = screenRect.bottom - kToolbarSize.height;
  final y = (minY <= maxY ? minY : maxY).clamp(screenRect.top, maxY);

  return Rect.fromLTWH(x, y, kToolbarSize.width, kToolbarSize.height);
}
