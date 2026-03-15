import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/qr_code.dart';
import '../services/window_service.dart';

class QrCodeOverlay extends StatefulWidget {
  final ui.Image image;
  final Rect imageDisplayRect;
  final Size imagePixelSize;
  final Offset imagePixelOrigin;
  final WindowService windowService;
  final ValueChanged<String> onCopy;
  final bool enabled;

  const QrCodeOverlay({
    super.key,
    required this.image,
    required this.imageDisplayRect,
    required this.imagePixelSize,
    this.imagePixelOrigin = Offset.zero,
    required this.windowService,
    required this.onCopy,
    required this.enabled,
  });

  @override
  State<QrCodeOverlay> createState() => _QrCodeOverlayState();
}

class _QrCodeOverlayState extends State<QrCodeOverlay> {
  List<QrCodeResult> _codes = const [];
  int _scanToken = 0;

  @override
  void initState() {
    super.initState();
    _startScan(widget.image);
  }

  @override
  void didUpdateWidget(QrCodeOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.image, oldWidget.image)) {
      _startScan(widget.image);
    }
  }

  Future<void> _startScan(ui.Image image) async {
    final token = ++_scanToken;
    setState(() => _codes = const []);

    ByteData? byteData;
    try {
      byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    } catch (_) {
      return;
    }
    final pngBytes = byteData?.buffer.asUint8List();
    if (pngBytes == null) return;

    final results = await widget.windowService.detectQRCodes(
      pngBytes: pngBytes,
    );
    if (!mounted || token != _scanToken) return;
    setState(() => _codes = results);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();
    if (_codes.isEmpty) return const SizedBox.shrink();
    if (widget.imagePixelSize.width <= 0 ||
        widget.imagePixelSize.height <= 0 ||
        widget.imageDisplayRect.width <= 0 ||
        widget.imageDisplayRect.height <= 0) {
      return const SizedBox.shrink();
    }

    final scaleX = widget.imageDisplayRect.width / widget.imagePixelSize.width;
    final scaleY =
        widget.imageDisplayRect.height / widget.imagePixelSize.height;
    if (scaleX == 0 || scaleY == 0) return const SizedBox.shrink();

    final displayPixelRect = Rect.fromLTWH(
      0,
      0,
      widget.imagePixelSize.width,
      widget.imagePixelSize.height,
    );

    final children = <Widget>[];
    for (final code in _codes) {
      final relative = code.bounds.shift(-widget.imagePixelOrigin);
      final visible = relative.intersect(displayPixelRect);
      if (visible.isEmpty) continue;
      final rect = Rect.fromLTWH(
        widget.imageDisplayRect.left + visible.left * scaleX,
        widget.imageDisplayRect.top + visible.top * scaleY,
        visible.width * scaleX,
        visible.height * scaleY,
      );
      final clipped = rect.intersect(widget.imageDisplayRect);
      if (clipped.isEmpty) continue;
      children.add(
        Positioned.fromRect(
          rect: clipped,
          child: _QrCodeHighlight(payload: code.payload, onCopy: widget.onCopy),
        ),
      );
    }

    if (children.isEmpty) return const SizedBox.shrink();

    return Stack(children: children);
  }
}

class _QrCodeHighlight extends StatelessWidget {
  static const _strokeColor = Color(0xFF25D6B3);
  static const _fillColor = Color(0x3325D6B3);
  static const _labelBackground = Color(0xCC0C0C0C);

  final String payload;
  final ValueChanged<String> onCopy;

  const _QrCodeHighlight({required this.payload, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onCopy(payload),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _fillColor,
            border: Border.all(color: _strokeColor, width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _labelBackground,
                  border: Border.all(
                    color: _strokeColor.withValues(alpha: 0.6),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(
                    'Click to copy',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
