import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../state/ink_state.dart';
import '../utils/ink_defaults.dart';

class InkOverlay extends StatefulWidget {
  const InkOverlay({
    super.key,
    required this.inkState,
    required this.drawingEnabled,
    required this.strokeColor,
    required this.strokeWidth,
    required this.smoothingTolerance,
    required this.autoFadeSeconds,
    required this.eraserSize,
    required this.onEraserSizeChanged,
  });

  final InkState inkState;
  final bool drawingEnabled;
  final Color strokeColor;
  final double strokeWidth;
  final double smoothingTolerance;
  final double autoFadeSeconds;
  final double eraserSize;
  final ValueChanged<double> onEraserSizeChanged;

  @override
  State<InkOverlay> createState() => _InkOverlayState();
}

class _InkOverlayState extends State<InkOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  Offset? _cursorPosition;
  bool _cursorIsEraser = false;
  bool _rightButtonDown = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, value: 1);
  }

  @override
  void didUpdateWidget(InkOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.drawingEnabled && widget.drawingEnabled) {
      _cancelFade();
      return;
    }
    if (oldWidget.drawingEnabled && !widget.drawingEnabled) {
      _startFadeIfNeeded();
      return;
    }
    if (oldWidget.autoFadeSeconds > 0 && widget.autoFadeSeconds <= 0) {
      _cancelFade();
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void _startFadeIfNeeded() {
    if (widget.autoFadeSeconds <= 0) return;
    if (!widget.inkState.hasStrokes) return;
    _fadeController.stop();
    _fadeController.value = 1;
    _fadeController.duration = Duration(
      milliseconds: (widget.autoFadeSeconds * 1000).round(),
    );
    _fadeController.animateTo(0, curve: Curves.easeOut).whenComplete(() {
      if (!mounted) return;
      if (widget.drawingEnabled) return;
      if (!widget.inkState.hasStrokes) return;
      widget.inkState.clear();
      _fadeController.value = 1;
    });
  }

  void _cancelFade() {
    _fadeController.stop();
    if (_fadeController.value != 1) {
      _fadeController.value = 1;
    }
  }

  void _updateCursorPosition(Offset position) {
    if (!widget.drawingEnabled) return;
    if (_cursorPosition == position) return;
    setState(() {
      _cursorPosition = position;
    });
  }

  void _clearCursorPosition() {
    if (_cursorPosition == null) return;
    setState(() {
      _cursorPosition = null;
      _cursorIsEraser = false;
      _rightButtonDown = false;
    });
  }

  void _setCursorIsEraser(bool isEraser) {
    if (_cursorIsEraser == isEraser) return;
    setState(() {
      _cursorIsEraser = isEraser;
    });
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.drawingEnabled) return;
    final isPrimary = (event.buttons & kPrimaryButton) != 0;
    final isSecondary = (event.buttons & kSecondaryButton) != 0;
    if (!isPrimary && !isSecondary) return;
    _rightButtonDown = isSecondary;
    final isEraser = isSecondary;
    _updateCursorPosition(event.localPosition);
    _setCursorIsEraser(isEraser);
    _cancelFade();
    widget.inkState.startStroke(
      event.localPosition,
      color: widget.strokeColor,
      strokeWidth: isEraser ? widget.eraserSize : widget.strokeWidth,
      isEraser: isEraser,
      smoothingTolerance: widget.smoothingTolerance,
    );
  }

  void _onPointerMove(PointerMoveEvent event) {
    _updateCursorPosition(event.localPosition);
    if (!widget.drawingEnabled) return;
    final hasButton =
        (event.buttons & (kPrimaryButton | kSecondaryButton)) != 0;
    if (!hasButton) return;
    final isEraser = (event.buttons & kSecondaryButton) != 0;
    _rightButtonDown = isEraser;
    _setCursorIsEraser(isEraser);
    widget.inkState.appendStroke(event.localPosition);
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!widget.drawingEnabled) return;
    widget.inkState.finishStroke();
    _setCursorIsEraser(false);
    _rightButtonDown = false;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (!widget.drawingEnabled) return;
    _rightButtonDown = false;
    _setCursorIsEraser(false);
  }

  void _onPointerHover(PointerHoverEvent event) {
    _updateCursorPosition(event.localPosition);
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (!widget.drawingEnabled) return;
    if (event is! PointerScrollEvent) return;
    if (!_rightButtonDown) return;
    if (event.scrollDelta.dy == 0) return;
    const step = 1.0;
    final direction = event.scrollDelta.dy.sign;
    final next = (widget.eraserSize + (-direction * step)).clamp(
      kInkMinEraserSize,
      kInkMaxEraserSize,
    );
    if (next == widget.eraserSize) return;
    if (_cursorIsEraser) {
      widget.inkState.updateActiveStrokeWidth(next);
    }
    widget.onEraserSizeChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final content = RepaintBoundary(
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _InkPainter(widget.inkState),
              size: Size.infinite,
            ),
          ),
          if (widget.drawingEnabled && _cursorPosition != null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _InkCursorPainter(
                    position: _cursorPosition!,
                    radius:
                        (_cursorIsEraser
                            ? widget.eraserSize
                            : widget.strokeWidth) /
                        2,
                    isEraser: _cursorIsEraser,
                    color: widget.strokeColor,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    final faded = FadeTransition(opacity: _fadeController, child: content);

    final cursor = widget.drawingEnabled
        ? SystemMouseCursors.none
        : MouseCursor.defer;

    final decorated = MouseRegion(
      cursor: cursor,
      onHover: _onPointerHover,
      onExit: (_) => _clearCursorPosition(),
      child: faded,
    );

    if (!widget.drawingEnabled) {
      return decorated;
    }

    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      onPointerSignal: _onPointerSignal,
      behavior: HitTestBehavior.translucent,
      child: decorated,
    );
  }
}

class _InkPainter extends CustomPainter {
  _InkPainter(this.inkState) : super(repaint: inkState);

  final InkState inkState;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    for (final stroke in inkState.strokes) {
      _paintStroke(canvas, stroke);
    }
    final active = inkState.activeStroke;
    if (active != null) {
      _paintStroke(canvas, active);
    }
    canvas.restore();
  }

  void _paintStroke(Canvas canvas, InkStroke stroke) {
    if (stroke.points.length < 2) return;
    final path = Path()..moveTo(stroke.points.first.dx, stroke.points.first.dy);
    for (var i = 1; i < stroke.points.length; i++) {
      final point = stroke.points[i];
      path.lineTo(point.dx, point.dy);
    }
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = stroke.strokeWidth
      ..blendMode = stroke.isEraser ? BlendMode.clear : BlendMode.srcOver
      ..color = stroke.isEraser ? Colors.transparent : stroke.color;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _InkPainter oldDelegate) => false;
}

class _InkCursorPainter extends CustomPainter {
  _InkCursorPainter({
    required this.position,
    required this.radius,
    required this.isEraser,
    required this.color,
  });

  final Offset position;
  final double radius;
  final bool isEraser;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final outerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.black.withValues(alpha: 0.55);
    final innerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = isEraser ? Colors.white : color.withValues(alpha: 0.9);
    canvas.drawCircle(position, radius, outerPaint);
    canvas.drawCircle(position, radius, innerPaint);
  }

  @override
  bool shouldRepaint(covariant _InkCursorPainter oldDelegate) {
    return oldDelegate.position != position ||
        oldDelegate.radius != radius ||
        oldDelegate.isEraser != isEraser ||
        oldDelegate.color != color;
  }
}
