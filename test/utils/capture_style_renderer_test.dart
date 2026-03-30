import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:a_snap/models/capture_style_settings.dart';
import 'package:a_snap/utils/capture_style_renderer.dart';

Future<ui.Image> _createSolidImage({
  required ui.Color color,
  int width = 40,
  int height = 24,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

Future<ui.Color> _pixelAt(ui.Image image, int x, int y) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();
  final index = ((y * image.width) + x) * 4;
  return ui.Color.fromARGB(
    bytes[index + 3],
    bytes[index],
    bytes[index + 1],
    bytes[index + 2],
  );
}

int _alpha8(ui.Color color) => (color.a * 255.0).round().clamp(0, 255);

void main() {
  test(
    'renderCaptureStyle keeps pixels equivalent for default style',
    () async {
      final source = await _createSolidImage(color: const ui.Color(0xFF00AAFF));
      final rendered = await renderCaptureStyle(
        source,
        const CaptureStyleSettings.defaults(),
      );

      expect(rendered.width, source.width);
      expect(rendered.height, source.height);
      expect(
        await _pixelAt(rendered, rendered.width ~/ 2, rendered.height ~/ 2),
        const ui.Color(0xFF00AAFF),
      );

      source.dispose();
      rendered.dispose();
    },
  );

  test('renderCaptureStyle rounds corners to transparency', () async {
    final source = await _createSolidImage(color: const ui.Color(0xFFFF0000));
    final rendered = await renderCaptureStyle(
      source,
      const CaptureStyleSettings(
        borderRadius: 10,
        padding: 0,
        shadowEnabled: false,
      ),
    );

    expect(_alpha8(await _pixelAt(rendered, 0, 0)), 0);
    expect(
      await _pixelAt(rendered, rendered.width ~/ 2, rendered.height ~/ 2),
      const ui.Color(0xFFFF0000),
    );

    source.dispose();
    rendered.dispose();
  });

  test('renderCaptureStyle expands output for padding and shadow', () async {
    final source = await _createSolidImage(color: const ui.Color(0xFF222222));
    const style = CaptureStyleSettings(
      borderRadius: 12,
      padding: 20,
      shadowEnabled: true,
    );
    final layout = computeCaptureStyleLayout(
      ui.Size(source.width.toDouble(), source.height.toDouble()),
      style,
    );
    final rendered = await renderCaptureStyle(source, style);

    expect(rendered.width, layout.outerSize.width.ceil());
    expect(rendered.height, layout.outerSize.height.ceil());
    expect(
      _alpha8(
        await _pixelAt(
          rendered,
          rendered.width ~/ 2,
          layout.contentRect.bottom.ceil() + 6,
        ),
      ),
      greaterThan(0),
    );

    source.dispose();
    rendered.dispose();
  });

  test('computeCaptureStyleLayout keeps padding additive with shadow', () {
    const baseStyle = CaptureStyleSettings(
      borderRadius: 12,
      padding: 0,
      shadowEnabled: true,
    );
    const paddedStyle = CaptureStyleSettings(
      borderRadius: 12,
      padding: 12,
      shadowEnabled: true,
    );

    final baseLayout = computeCaptureStyleLayout(
      const ui.Size(80, 40),
      baseStyle,
    );
    final paddedLayout = computeCaptureStyleLayout(
      const ui.Size(80, 40),
      paddedStyle,
    );

    expect(
      paddedLayout.outerInsets.left,
      baseLayout.outerInsets.left + paddedStyle.padding,
    );
    expect(
      paddedLayout.outerInsets.top,
      baseLayout.outerInsets.top + paddedStyle.padding,
    );
    expect(
      paddedLayout.outerInsets.right,
      baseLayout.outerInsets.right + paddedStyle.padding,
    );
    expect(
      paddedLayout.outerInsets.bottom,
      baseLayout.outerInsets.bottom + paddedStyle.padding,
    );
  });
}
