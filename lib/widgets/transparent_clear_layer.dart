import 'package:flutter/material.dart';

class TransparentClearLayer extends StatelessWidget {
  const TransparentClearLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      painter: _TransparentClearPainter(),
      child: SizedBox.expand(),
    );
  }
}

class _TransparentClearPainter extends CustomPainter {
  const _TransparentClearPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Windows transparent overlays become unreliable when the entire surface is
    // fully zero-alpha. Keep an effectively invisible fill so the whole client
    // area remains part of the composed surface and hit-test region.
    final paint = Paint()
      ..blendMode = BlendMode.src
      ..color = const Color(0x01000000);
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
