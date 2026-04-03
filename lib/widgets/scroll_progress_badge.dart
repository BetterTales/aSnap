import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Full-screen transparent overlay during manual scroll capture.
/// Renders two positioned children on the transparent overlay:
///  1. An animated rainbow border around the capture region
///  2. A live preview panel showing the growing stitched image
///
/// The native window has `ignoresMouseEvents = true` so scroll events pass
/// through to the content below.
class ScrollCapturePreview extends StatefulWidget {
  /// Current frame count (0 when waiting for first scroll).
  final int frameCount;

  /// Growing composite image from ScrollCaptureService (null before first frame).
  final ui.Image? previewImage;

  /// Capture region in CG coordinates (top-left origin).
  final Rect captureRegion;

  /// CG origin of the display the overlay covers.
  final Offset screenOrigin;

  /// Logical size of the display.
  final Size screenSize;

  /// Called when the user clicks the "Done" button to finish capture.
  final VoidCallback? onDone;

  /// Called with the screen-coordinate rect of the "Done" button so the native
  /// side can place a clickable button over it. The overlay ignores mouse
  /// events, so the native surface provides the hit area.
  final void Function(Rect cgRect)? onStopButtonRect;

  const ScrollCapturePreview({
    super.key,
    required this.frameCount,
    this.previewImage,
    required this.captureRegion,
    required this.screenOrigin,
    required this.screenSize,
    this.onDone,
    this.onStopButtonRect,
  });

  @override
  State<ScrollCapturePreview> createState() => _ScrollCapturePreviewState();
}

class _ScrollCapturePreviewState extends State<ScrollCapturePreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rainbowController;
  final _scrollController = ScrollController();

  static const _windowsDoneFill = Color(0xFF3E3E3E);
  static const _windowsDoneBorder = Color(0xFF969696);

  @override
  void initState() {
    super.initState();
    _rainbowController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
  }

  @override
  void didUpdateWidget(ScrollCapturePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-scroll to bottom when preview image updates
    if (widget.previewImage != oldWidget.previewImage &&
        widget.previewImage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    _rainbowController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Convert CG coordinates to local overlay coordinates.
  Rect get _localRegion => widget.captureRegion.shift(-widget.screenOrigin);

  @override
  Widget build(BuildContext context) {
    final region = _localRegion;

    // Compute preview panel position: prefer right, then left, then overlap
    const panelWidth = 350.0;
    const panelMargin = 16.0;
    const minPanelWidth = 250.0;

    final rightSpace = widget.screenSize.width - region.right;
    final leftSpace = region.left;

    double panelX;
    double effectivePanelWidth;

    if (rightSpace >= panelWidth + panelMargin * 2) {
      // Place to the right of the capture region
      panelX = region.right + panelMargin;
      effectivePanelWidth = math.min(panelWidth, rightSpace - panelMargin * 2);
    } else if (leftSpace >= panelWidth + panelMargin * 2) {
      // Place to the left
      effectivePanelWidth = math.min(panelWidth, leftSpace - panelMargin * 2);
      panelX = region.left - panelMargin - effectivePanelWidth;
    } else if (rightSpace >= minPanelWidth + panelMargin) {
      // Squeeze into right with minimum width
      panelX = region.right + panelMargin;
      effectivePanelWidth = rightSpace - panelMargin;
    } else {
      // Fallback: overlap the capture region on the right side
      effectivePanelWidth = math.min(panelWidth, widget.screenSize.width * 0.3);
      panelX = widget.screenSize.width - effectivePanelWidth - panelMargin;
    }

    // Panel height: fixed at 60% of screen height, centered vertically.
    // Independent of capture region so small selections still get a usable preview.
    final desiredPanelH = widget.screenSize.height * 0.6;
    final panelHeight = desiredPanelH.clamp(
      200.0,
      widget.screenSize.height - panelMargin * 2,
    );
    final panelY = (widget.screenSize.height - panelHeight) / 2;

    return ColoredBox(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Animated rainbow border around the capture region
          Positioned(
            left: region.left - 4,
            top: region.top - 4,
            width: region.width + 8,
            height: region.height + 8,
            child: AnimatedBuilder(
              animation: _rainbowController,
              builder: (context, _) {
                return CustomPaint(
                  painter: _RainbowBorderPainter(_rainbowController.value),
                );
              },
            ),
          ),
          // Live preview panel
          Positioned(
            left: panelX,
            top: panelY,
            width: effectivePanelWidth,
            height: panelHeight,
            child: _buildPreviewPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF0202020),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x30FFFFFF), width: 0.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x60000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            _buildStatusBar(),
            Expanded(child: _buildImageArea()),
          ],
        ),
      ),
    );
  }

  /// Key for the "Done" button so we can measure its position after layout.
  final _doneButtonKey = GlobalKey();

  /// Last reported CG rect to avoid spamming the callback.
  Rect? _lastReportedButtonRect;

  void _reportDoneButtonRect() {
    final key = _doneButtonKey;
    final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final localPos = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    // Convert overlay-local coordinates to CG screen coordinates.
    final cgRect = Rect.fromLTWH(
      localPos.dx + widget.screenOrigin.dx,
      localPos.dy + widget.screenOrigin.dy,
      size.width,
      size.height,
    );

    if (cgRect != _lastReportedButtonRect) {
      _lastReportedButtonRect = cgRect;
      widget.onStopButtonRect?.call(cgRect);
    }
  }

  Widget _buildStatusBar() {
    final hasFrames = widget.frameCount > 0;
    final showNativeDoneButton =
        hasFrames &&
        widget.onStopButtonRect != null &&
        (Platform.isMacOS || Platform.isWindows);

    // Report the "Done" button position after this frame paints.
    if (showNativeDoneButton) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reportDoneButtonRect();
      });
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0x20FFFFFF), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          if (hasFrames) ...[
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: Colors.white70,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            hasFrames ? 'Frame ${widget.frameCount}' : 'Scroll to capture',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              decoration: TextDecoration.none,
            ),
          ),
          const Spacer(),
          if (showNativeDoneButton)
            Opacity(
              opacity: Platform.isWindows ? 0 : 1,
              child: _buildDoneButtonPlaceholder(),
            )
          else
            const Text(
              'Esc cancel',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.w400,
                decoration: TextDecoration.none,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDoneButtonPlaceholder() {
    return Container(
      key: _doneButtonKey,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: Platform.isWindows ? _windowsDoneFill : const Color(0x30FFFFFF),
        borderRadius: BorderRadius.circular(6),
        border: Platform.isWindows
            ? Border.all(color: _windowsDoneBorder, width: 1)
            : null,
      ),
      child: const Text(
        'Done',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }

  Widget _buildImageArea() {
    final image = widget.previewImage;
    if (image == null) {
      return const Center(
        child: Text(
          'Scroll the content below\nto start capturing',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white30,
            fontSize: 13,
            fontWeight: FontWeight.w400,
            decoration: TextDecoration.none,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final imageHeight = constraints.maxWidth * (image.height / image.width);
        return SingleChildScrollView(
          controller: _scrollController,
          child: SizedBox(
            width: constraints.maxWidth,
            height: imageHeight,
            child: RawImage(image: image, fit: BoxFit.fitWidth),
          ),
        );
      },
    );
  }
}

/// Draws an animated rainbow glow border around the widget bounds.
class _RainbowBorderPainter extends CustomPainter {
  final double progress; // 0.0 → 1.0, cycles continuously

  _RainbowBorderPainter(this.progress);

  static const _borderWidth = 3.0;
  static const _borderRadius = 8.0;
  static const _glowSigma = 6.0;

  static const _rainbowColors = [
    Color(0xFFFF0000), // red
    Color(0xFFFF8000), // orange
    Color(0xFFFFFF00), // yellow
    Color(0xFF00FF00), // green
    Color(0xFF00FFFF), // cyan
    Color(0xFF0080FF), // blue
    Color(0xFF8000FF), // violet
    Color(0xFFFF0000), // red (loop)
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        _borderWidth / 2,
        _borderWidth / 2,
        size.width - _borderWidth,
        size.height - _borderWidth,
      ),
      const Radius.circular(_borderRadius),
    );

    final center = Offset(size.width / 2, size.height / 2);
    final rotation = progress * 2 * math.pi;

    final gradient = SweepGradient(
      center: Alignment.center,
      colors: _rainbowColors,
      transform: GradientRotation(rotation),
    );

    final shader = gradient.createShader(
      Rect.fromCircle(
        center: center,
        radius: math.max(size.width, size.height) / 2,
      ),
    );

    // Outer glow pass
    final glowPaint = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = _borderWidth + 4
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, _glowSigma)
      ..color = Colors.white.withValues(alpha: 0.5);
    canvas.drawRRect(rrect, glowPaint);

    // Solid border pass
    final borderPaint = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = _borderWidth;
    canvas.drawRRect(rrect, borderPaint);
  }

  @override
  bool shouldRepaint(_RainbowBorderPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
