import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
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
  final ValueNotifier<Offset?> _cursorPosition = ValueNotifier(null);
  final ValueNotifier<bool> _cursorIsEraser = ValueNotifier(false);
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
    _cursorPosition.dispose();
    _cursorIsEraser.dispose();
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
    if (_cursorPosition.value == position) return;
    _cursorPosition.value = position;
  }

  Offset _eventPosition(PointerEvent event) => event.localPosition;

  void _clearCursorPosition() {
    final hadCursor = _cursorPosition.value != null;
    final hadEraser = _cursorIsEraser.value;
    if (!hadCursor && !hadEraser && !_rightButtonDown) return;
    _cursorPosition.value = null;
    _cursorIsEraser.value = false;
    _rightButtonDown = false;
  }

  void _setCursorIsEraser(bool isEraser) {
    if (_cursorIsEraser.value == isEraser) return;
    _cursorIsEraser.value = isEraser;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.drawingEnabled) return;
    final isPrimary = (event.buttons & kPrimaryButton) != 0;
    final isSecondary = (event.buttons & kSecondaryButton) != 0;
    if (!isPrimary && !isSecondary) return;
    final position = _eventPosition(event);
    _rightButtonDown = isSecondary;
    final isEraser = isSecondary;
    _updateCursorPosition(position);
    _setCursorIsEraser(isEraser);
    _cancelFade();
    widget.inkState.startStroke(
      position,
      color: widget.strokeColor,
      strokeWidth: isEraser ? widget.eraserSize : widget.strokeWidth,
      isEraser: isEraser,
      smoothingTolerance: widget.smoothingTolerance,
    );
  }

  void _onPointerMove(PointerMoveEvent event) {
    final position = _eventPosition(event);
    _updateCursorPosition(position);
    if (!widget.drawingEnabled) return;
    final hasButton =
        (event.buttons & (kPrimaryButton | kSecondaryButton)) != 0;
    if (!hasButton) return;
    final isEraser = (event.buttons & kSecondaryButton) != 0;
    _rightButtonDown = isEraser;
    _setCursorIsEraser(isEraser);
    widget.inkState.appendStroke(position);
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!widget.drawingEnabled) return;
    widget.inkState.finishStroke();
    _setCursorIsEraser(false);
    _rightButtonDown = false;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (!widget.drawingEnabled) return;
    widget.inkState.cancelStroke();
    _rightButtonDown = false;
    _setCursorIsEraser(false);
  }

  void _onPointerHover(PointerHoverEvent event) {
    final position = _eventPosition(event);
    _updateCursorPosition(position);
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
    if (_cursorIsEraser.value) {
      widget.inkState.updateActiveStrokeWidth(next);
    }
    widget.onEraserSizeChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final repaint = Listenable.merge([
      widget.inkState,
      _cursorPosition,
      _cursorIsEraser,
    ]);
    final content = SizedBox.expand(
      child: ListenableBuilder(
        listenable: repaint,
        builder: (context, _) => CustomPaint(
          painter: _InkPainter(
            inkState: widget.inkState,
            strokeColor: widget.strokeColor,
            strokeWidth: widget.strokeWidth,
            eraserSize: widget.eraserSize,
            cursorActive: widget.drawingEnabled,
            cursorPositionListenable: _cursorPosition,
            cursorIsEraserListenable: _cursorIsEraser,
          ),
        ),
      ),
    );

    final faded = Platform.isWindows
        ? content
        : FadeTransition(opacity: _fadeController, child: content);

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
      behavior: HitTestBehavior.opaque,
      child: decorated,
    );
  }
}

class _InkPainter extends CustomPainter {
  _InkPainter({
    required this.inkState,
    required this.strokeColor,
    required this.strokeWidth,
    required this.eraserSize,
    required this.cursorActive,
    required this.cursorPositionListenable,
    required this.cursorIsEraserListenable,
  });

  final InkState inkState;
  final Color strokeColor;
  final double strokeWidth;
  final double eraserSize;
  final bool cursorActive;
  final ValueListenable<Offset?> cursorPositionListenable;
  final ValueListenable<bool> cursorIsEraserListenable;

  @override
  void paint(Canvas canvas, Size size) {
    var needsLayer = false;
    for (final stroke in inkState.strokes) {
      if (stroke.isEraser) {
        needsLayer = true;
        break;
      }
    }
    if (!needsLayer && inkState.activeStroke?.isEraser == true) {
      needsLayer = true;
    }
    if (needsLayer) {
      canvas.saveLayer(Offset.zero & size, Paint());
    }
    for (final stroke in inkState.strokes) {
      _paintStroke(canvas, stroke);
    }
    final active = inkState.activeStroke;
    if (active != null) {
      _paintStroke(canvas, active);
    }
    if (needsLayer) {
      canvas.restore();
    }

    final cursorPosition = cursorActive ? cursorPositionListenable.value : null;
    if (cursorPosition == null) {
      return;
    }

    _paintCursor(
      canvas,
      position: cursorPosition,
      radius: (cursorIsEraserListenable.value ? eraserSize : strokeWidth) / 2,
      isEraser: cursorIsEraserListenable.value,
    );
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

  void _paintCursor(
    Canvas canvas, {
    required Offset position,
    required double radius,
    required bool isEraser,
  }) {
    final outerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.black.withValues(alpha: 0.55);
    final innerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = isEraser ? Colors.white : strokeColor.withValues(alpha: 0.9);
    canvas.drawCircle(position, radius, outerPaint);
    canvas.drawCircle(position, radius, innerPaint);
  }

  @override
  bool shouldRepaint(covariant _InkPainter oldDelegate) => true;
}
