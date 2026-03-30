import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:a_snap/models/capture_style_settings.dart';
import 'package:a_snap/models/shortcut_bindings.dart';
import 'package:a_snap/services/settings_service.dart';
import 'package:a_snap/utils/ink_defaults.dart';
import 'package:a_snap/utils/laser_defaults.dart';

Future<Directory> _tempDir() async {
  return Directory.systemTemp.createTemp('asnap_settings_test_');
}

Future<Map<String, dynamic>> _readSettings(Directory dir) async {
  final file = File('${dir.path}/settings.json');
  final raw = jsonDecode(await file.readAsString());
  return Map<String, dynamic>.from(raw as Map);
}

void main() {
  test('loads defaults when settings file is missing', () async {
    final dir = await _tempDir();
    final service = SettingsService(supportDirectoryProvider: () async => dir);

    final shortcuts = await service.loadShortcutBindings();
    final ocrPreview = await service.loadOcrPreviewEnabled();
    final ocrOpenUrlPrompt = await service.loadOcrOpenUrlPromptEnabled();
    final captureStyle = await service.loadCaptureStyle();
    final inkColor = await service.loadInkColor();
    final inkStrokeWidth = await service.loadInkStrokeWidth();
    final inkSmoothingTolerance = await service.loadInkSmoothingTolerance();
    final inkAutoFadeSeconds = await service.loadInkAutoFadeSeconds();
    final inkEraserSize = await service.loadInkEraserSize();
    final laserColor = await service.loadLaserColor();
    final laserSize = await service.loadLaserSize();
    final laserFadeSeconds = await service.loadLaserFadeSeconds();

    expect(shortcuts.encodeJson(), ShortcutBindings.defaults().encodeJson());
    expect(ocrPreview, isFalse);
    expect(ocrOpenUrlPrompt, isTrue);
    expect(captureStyle, const CaptureStyleSettings.defaults());
    expect(inkColor, kInkDefaultColor);
    expect(inkStrokeWidth, kInkDefaultStrokeWidth);
    expect(inkSmoothingTolerance, kInkDefaultSmoothingTolerance);
    expect(inkAutoFadeSeconds, kInkDefaultAutoFadeSeconds);
    expect(inkEraserSize, kInkDefaultEraserSize);
    expect(laserColor, kLaserDefaultColor);
    expect(laserSize, kLaserDefaultSize);
    expect(laserFadeSeconds, kLaserDefaultFadeSeconds);
  });

  test('loads defaults when settings file lacks shortcuts', () async {
    final dir = await _tempDir();
    final file = File('${dir.path}/settings.json');
    await file.writeAsString(jsonEncode({'ocrPreviewEnabled': true}));
    final service = SettingsService(supportDirectoryProvider: () async => dir);

    final shortcuts = await service.loadShortcutBindings();
    final ocrPreview = await service.loadOcrPreviewEnabled();

    expect(shortcuts.encodeJson(), ShortcutBindings.defaults().encodeJson());
    expect(ocrPreview, isTrue);
  });

  test('persists OCR preview flag alongside shortcuts', () async {
    final dir = await _tempDir();
    final service = SettingsService(supportDirectoryProvider: () async => dir);
    final updated = ShortcutBindings.defaults().copyWithAction(
      ShortcutAction.region,
      ShortcutBindings.defaults().region,
    );

    await service.saveShortcutBindings(updated);
    await service.saveOcrPreviewEnabled(true);
    await service.saveOcrOpenUrlPromptEnabled(false);
    await service.saveCaptureStyle(
      const CaptureStyleSettings(
        borderRadius: 18,
        padding: 24,
        shadowEnabled: true,
      ),
    );
    await service.saveInkColor(const Color(0xFF00C853));
    await service.saveInkStrokeWidth(12);
    await service.saveInkSmoothingTolerance(2.5);
    await service.saveInkAutoFadeSeconds(5);
    await service.saveInkEraserSize(24);
    await service.saveLaserColor(const Color(0xFF2962FF));
    await service.saveLaserSize(20);
    await service.saveLaserFadeSeconds(1.2);

    var map = await _readSettings(dir);
    expect(map['ocrPreviewEnabled'], isTrue);
    expect(map['ocrOpenUrlPromptEnabled'], isFalse);
    expect(map['captureStyle'], {
      'borderRadius': 18.0,
      'padding': 24.0,
      'shadowEnabled': true,
    });
    expect(map['shortcuts'], isA<Map>());
    expect(map['inkColor'], 0xFF00C853);
    expect(map['inkStrokeWidth'], 12);
    expect(map['inkSmoothingTolerance'], 2.5);
    expect(map['inkAutoFadeSeconds'], 5);
    expect(map['inkEraserSize'], 24);
    expect(map['laserColor'], 0xFF2962FF);
    expect(map['laserSize'], 20);
    expect(map['laserFadeSeconds'], 1.2);

    await service.saveShortcutBindings(ShortcutBindings.defaults());

    map = await _readSettings(dir);
    expect(map['ocrPreviewEnabled'], isTrue);
    expect(map['ocrOpenUrlPromptEnabled'], isFalse);
    expect(map['captureStyle'], {
      'borderRadius': 18.0,
      'padding': 24.0,
      'shadowEnabled': true,
    });
    expect(map['inkColor'], 0xFF00C853);
    expect(map['inkStrokeWidth'], 12);
    expect(map['inkSmoothingTolerance'], 2.5);
    expect(map['inkAutoFadeSeconds'], 5);
    expect(map['inkEraserSize'], 24);
    expect(map['laserColor'], 0xFF2962FF);
    expect(map['laserSize'], 20);
    expect(map['laserFadeSeconds'], 1.2);
  });
}
