import 'package:flutter/painting.dart';

/// Fallback toolbar height used before the native panel reports its real frame.
///
/// The macOS panel is authoritative for actual geometry; Flutter only uses
/// this during initial layout before the native callback arrives.
const double kNativeToolbarFallbackHeight = 44.0;

const double kToolbarGap = 8.0;

/// Compute a fallback toolbar anchor point outside [anchorRect].
///
/// The native AppKit panel owns the real toolbar frame. Flutter uses this
/// lightweight anchor until the native side reports the resolved frame.
Offset computeFloatingToolbarAnchor({
  required Rect anchorRect,
  required Size screenSize,
  EdgeInsets viewportPadding = const EdgeInsets.all(8),
}) {
  final minX = viewportPadding.left;
  final maxX = screenSize.width - viewportPadding.right;
  final minY = viewportPadding.top;
  final maxY = screenSize.height - viewportPadding.bottom;

  double x;
  if (maxX <= minX) {
    x = minX;
  } else {
    x = anchorRect.center.dx.clamp(minX, maxX);
  }

  // Keep toolbar floating below anchor (never jump above).
  final y = maxY <= minY
      ? minY
      : (anchorRect.bottom + kToolbarGap).clamp(minY, maxY);

  return Offset(x.toDouble(), y.toDouble());
}
