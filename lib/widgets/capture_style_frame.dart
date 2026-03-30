import 'package:flutter/material.dart';

import '../utils/capture_style_renderer.dart';

class CaptureStyleFrame extends StatelessWidget {
  const CaptureStyleFrame({
    super.key,
    required this.contentRect,
    required this.borderRadius,
    required this.shadowEnabled,
    required this.child,
  });

  final Rect contentRect;
  final double borderRadius;
  final bool shadowEnabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _CaptureStyleShadowPainter(
                contentRect: contentRect,
                borderRadius: borderRadius,
                shadowEnabled: shadowEnabled,
              ),
            ),
          ),
        ),
        Positioned.fromRect(
          rect: contentRect,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: child,
          ),
        ),
      ],
    );
  }
}

class _CaptureStyleShadowPainter extends CustomPainter {
  const _CaptureStyleShadowPainter({
    required this.contentRect,
    required this.borderRadius,
    required this.shadowEnabled,
  });

  final Rect contentRect;
  final double borderRadius;
  final bool shadowEnabled;

  @override
  void paint(Canvas canvas, Size size) {
    paintCaptureShadow(
      canvas,
      contentRect: contentRect,
      borderRadius: borderRadius,
      shadowEnabled: shadowEnabled,
    );
  }

  @override
  bool shouldRepaint(covariant _CaptureStyleShadowPainter oldDelegate) {
    return contentRect != oldDelegate.contentRect ||
        borderRadius != oldDelegate.borderRadius ||
        shadowEnabled != oldDelegate.shadowEnabled;
  }
}
