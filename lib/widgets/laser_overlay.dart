import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../state/laser_state.dart';
import '../utils/laser_defaults.dart';

class LaserOverlay extends StatefulWidget {
  const LaserOverlay({
    super.key,
    required this.laserState,
    required this.drawingEnabled,
    required this.color,
    required this.size,
    required this.fadeSeconds,
  });

  final LaserState laserState;
  final bool drawingEnabled;
  final Color color;
  final double size;
  final double fadeSeconds;

  @override
  State<LaserOverlay> createState() => _LaserOverlayState();
}

class _LaserOverlayState extends State<LaserOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  final ValueNotifier<Offset?> _cursorPosition = ValueNotifier(null);
  Offset? _lastSamplePosition;
  double _lastSampleTime = 0;
  bool _isPrimaryDown = false;
  int _activeStrokeId = 0;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    );
    _ticker.addListener(_handleTick);
    _updateTicker();
  }

  @override
  void didUpdateWidget(LaserOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.drawingEnabled != widget.drawingEnabled) {
      _updateTicker();
      if (!widget.drawingEnabled) {
        _lastSamplePosition = null;
        _isPrimaryDown = false;
      }
    }
    if (oldWidget.fadeSeconds != widget.fadeSeconds &&
        widget.fadeSeconds <= 0) {
      widget.laserState.clear();
    }
  }

  @override
  void dispose() {
    _ticker
      ..removeListener(_handleTick)
      ..dispose();
    _cursorPosition.dispose();
    super.dispose();
  }

  void _updateTicker() {
    if (widget.drawingEnabled || widget.laserState.hasSamples) {
      if (!_ticker.isAnimating) {
        _ticker.repeat(
          min: 0,
          max: 1,
          period: const Duration(milliseconds: 16),
        );
      }
    } else {
      if (_ticker.isAnimating) {
        _ticker.stop();
      }
    }
  }

  void _handleTick() {
    if (widget.fadeSeconds > 0) {
      widget.laserState.prune(maxAgeSeconds: widget.fadeSeconds);
    } else {
      widget.laserState.clear();
    }
    _updateTicker();
  }

  void _recordSample(Offset position) {
    if (!widget.drawingEnabled || !_isPrimaryDown) return;

    final now = widget.laserState.nowSeconds();
    const minInterval = 1 / 120;
    const minDistance = 0.5;
    if (_lastSamplePosition != null) {
      final delta = position - _lastSamplePosition!;
      if (now - _lastSampleTime < minInterval && delta.distance < minDistance) {
        return;
      }
    }

    final pending = <LaserSample>[];
    final previous = _lastSamplePosition;
    final previousTime = _lastSampleTime;
    if (previous != null && previousTime > 0) {
      final delta = position - previous;
      final distance = delta.distance;
      final step = math.max(1.0, widget.size * 0.4);
      if (distance > step) {
        final extra = (distance / step).floor();
        for (var i = 1; i <= extra; i++) {
          final t = i / (extra + 1);
          pending.add(
            LaserSample(
              position: previous + delta * t,
              timestampSeconds: previousTime + (now - previousTime) * t,
              strokeId: _activeStrokeId,
            ),
          );
        }
      }
    }
    pending.add(
      LaserSample(
        position: position,
        timestampSeconds: now,
        strokeId: _activeStrokeId,
      ),
    );
    widget.laserState.addSamples(pending);
    _lastSampleTime = now;
    _lastSamplePosition = position;
    _updateTicker();
  }

  void _clearCursor() {
    _cursorPosition.value = null;
    _lastSamplePosition = null;
    _lastSampleTime = 0;
  }

  void _updateCursor(Offset position) {
    if (_cursorPosition.value == position) return;
    _cursorPosition.value = position;
  }

  void _onPointerHover(PointerHoverEvent event) {
    _updateCursor(event.localPosition);
    _recordSample(event.localPosition);
  }

  void _onPointerEnter(PointerEnterEvent event) {
    _updateCursor(event.localPosition);
  }

  void _onPointerMove(PointerMoveEvent event) {
    _updateCursor(event.localPosition);
    _recordSample(event.localPosition);
  }

  void _onPointerDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton) return;
    _isPrimaryDown = true;
    _activeStrokeId += 1;
    _lastSamplePosition = null;
    _lastSampleTime = 0;
    _updateCursor(event.localPosition);
    _recordSample(event.localPosition);
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.buttons == kPrimaryButton || event.buttons == 0) {
      _isPrimaryDown = false;
      _lastSamplePosition = null;
      _lastSampleTime = 0;
      _updateCursor(event.localPosition);
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _isPrimaryDown = false;
    _clearCursor();
  }

  @override
  Widget build(BuildContext context) {
    final repaint = Listenable.merge([
      widget.laserState,
      _ticker,
      _cursorPosition,
    ]);

    final painter = _LaserPainter(
      laserState: widget.laserState,
      color: widget.color,
      size: widget.size,
      fadeSeconds: widget.fadeSeconds,
      cursorActive: widget.drawingEnabled,
      cursorPositionListenable: _cursorPosition,
      repaint: repaint,
    );

    final content = RepaintBoundary(
      child: CustomPaint(painter: painter, size: Size.infinite),
    );

    final cursor = widget.drawingEnabled
        ? SystemMouseCursors.none
        : MouseCursor.defer;

    final decorated = MouseRegion(
      cursor: cursor,
      onEnter: _onPointerEnter,
      onHover: _onPointerHover,
      onExit: (_) => _clearCursor(),
      child: content,
    );

    if (!widget.drawingEnabled) {
      return decorated;
    }

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: decorated,
    );
  }
}

class _LaserPainter extends CustomPainter {
  _LaserPainter({
    required this.laserState,
    required this.color,
    required this.size,
    required this.fadeSeconds,
    required this.cursorActive,
    required this.cursorPositionListenable,
    super.repaint,
  });

  final LaserState laserState;
  final Color color;
  final double size;
  final double fadeSeconds;
  final bool cursorActive;
  final ValueListenable<Offset?> cursorPositionListenable;

  @override
  void paint(Canvas canvas, Size size) {
    final samples = laserState.samples;
    final now = laserState.nowSeconds();
    final fade = fadeSeconds <= 0 ? kLaserDefaultFadeSeconds : fadeSeconds;

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (samples.isNotEmpty) {
      for (var i = 1; i < samples.length; i++) {
        final current = samples[i];
        final prev = samples[i - 1];
        if (current.strokeId != prev.strokeId) continue;
        final age = now - current.timestampSeconds;
        if (age > fade) continue;
        final t = (1 - age / fade).clamp(0.0, 1.0);
        final alpha = (0.75 * t).clamp(0.0, 1.0);

        glowPaint
          ..color = color.withValues(alpha: (0.35 * alpha).clamp(0.0, 1.0))
          ..strokeWidth = this.size * 1.6;
        linePaint
          ..color = color.withValues(alpha: alpha)
          ..strokeWidth = this.size;

        canvas.drawLine(prev.position, current.position, glowPaint);
        canvas.drawLine(prev.position, current.position, linePaint);
      }
    }

    final cursorPosition = cursorActive ? cursorPositionListenable.value : null;
    final cursorDotAlpha = cursorPosition != null ? 0.9 : null;
    final cursorGlowAlpha = cursorPosition != null ? 0.5 : null;

    Offset? dotPosition;
    double? dotAlpha;
    double? glowAlpha;

    if (cursorPosition != null) {
      dotPosition = cursorPosition;
      dotAlpha = cursorDotAlpha;
      glowAlpha = cursorGlowAlpha;
    } else if (samples.isNotEmpty) {
      final latest = samples.last;
      final dotAge = now - latest.timestampSeconds;
      final dotT = (1 - dotAge / fade).clamp(0.0, 1.0);
      if (dotT > 0) {
        dotPosition = latest.position;
        dotAlpha = (0.9 * dotT).clamp(0.0, 1.0);
        glowAlpha = (0.5 * dotT).clamp(0.0, 1.0);
      }
    }

    if (dotPosition == null || dotAlpha == null || glowAlpha == null) {
      return;
    }

    final radius = this.size / 2;
    final glowRadius = radius * 2.1;
    final glow = Paint()
      ..color = color.withValues(alpha: glowAlpha)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    final dot = Paint()..color = color.withValues(alpha: dotAlpha);

    canvas.drawCircle(dotPosition, glowRadius, glow);
    canvas.drawCircle(dotPosition, radius, dot);
    canvas.drawCircle(
      dotPosition,
      math.max(1, radius * 0.35),
      Paint()..color = Colors.white.withValues(alpha: dotAlpha * 0.7),
    );
  }

  @override
  bool shouldRepaint(covariant _LaserPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.size != size ||
        oldDelegate.fadeSeconds != fadeSeconds ||
        oldDelegate.cursorActive != cursorActive;
  }
}
