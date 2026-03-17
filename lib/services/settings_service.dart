import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:path_provider/path_provider.dart';

import '../models/shortcut_bindings.dart';
import '../utils/ink_defaults.dart';
import '../utils/laser_defaults.dart';

class SettingsService {
  SettingsService({Future<Directory> Function()? supportDirectoryProvider})
    : _supportDirectoryProvider =
          supportDirectoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _supportDirectoryProvider;

  Future<ShortcutBindings> loadShortcutBindings() async {
    try {
      final map = await _readSettingsMap();
      final shortcuts = map['shortcuts'];
      if (shortcuts is Map<String, dynamic>) {
        return ShortcutBindings.fromJson(shortcuts);
      }
      if (shortcuts is Map) {
        return ShortcutBindings.fromJson(Map<String, dynamic>.from(shortcuts));
      }
      return ShortcutBindings.defaults();
    } catch (_) {
      return ShortcutBindings.defaults();
    }
  }

  Future<void> saveShortcutBindings(ShortcutBindings bindings) async {
    final map = await _readSettingsMap();
    final next = _normalizeSettingsMap(map);
    next['shortcuts'] = bindings.toJson();
    await _writeSettingsMap(next);
  }

  Future<bool> loadOcrPreviewEnabled() async {
    try {
      final map = await _readSettingsMap();
      final value = map['ocrPreviewEnabled'];
      if (value is bool) return value;
    } catch (_) {}
    return false;
  }

  Future<void> saveOcrPreviewEnabled(bool enabled) async {
    final map = await _readSettingsMap();
    final next = _normalizeSettingsMap(map);
    next['ocrPreviewEnabled'] = enabled;
    await _writeSettingsMap(next);
  }

  Future<bool> loadOcrOpenUrlPromptEnabled() async {
    try {
      final map = await _readSettingsMap();
      final value = map['ocrOpenUrlPromptEnabled'];
      if (value is bool) return value;
    } catch (_) {}
    return true;
  }

  Future<void> saveOcrOpenUrlPromptEnabled(bool enabled) async {
    final map = await _readSettingsMap();
    final next = _normalizeSettingsMap(map);
    next['ocrOpenUrlPromptEnabled'] = enabled;
    await _writeSettingsMap(next);
  }

  Future<Color> loadInkColor() async {
    try {
      final map = await _readSettingsMap();
      final value = map['inkColor'];
      if (value is int) return Color(value);
    } catch (_) {}
    return kInkDefaultColor;
  }

  Future<void> saveInkColor(Color color) async {
    final map = await _readSettingsMap();
    final next = _normalizeSettingsMap(map);
    next['inkColor'] = color.toARGB32();
    await _writeSettingsMap(next);
  }

  Future<double> loadInkStrokeWidth() async {
    try {
      final map = await _readSettingsMap();
      final value = map['inkStrokeWidth'];
      if (value is num) return value.toDouble();
    } catch (_) {}
    return kInkDefaultStrokeWidth;
  }

  Future<void> saveInkStrokeWidth(double width) async {
    final map = await _readSettingsMap();
    final next = _normalizeSettingsMap(map);
    next['inkStrokeWidth'] = width;
    await _writeSettingsMap(next);
  }

  Future<double> loadInkSmoothingTolerance() async {
    try {
      final map = await _readSettingsMap();
      final value = map['inkSmoothingTolerance'];
      if (value is num) return value.toDouble();
    } catch (_) {}
    return kInkDefaultSmoothingTolerance;
  }

  Future<void> saveInkSmoothingTolerance(double tolerance) async {
    final map = await _readSettingsMap();
    final next = _normalizeSettingsMap(map);
    next['inkSmoothingTolerance'] = tolerance;
    await _writeSettingsMap(next);
  }

  Future<double> loadInkAutoFadeSeconds() async {
    try {
      final map = await _readSettingsMap();
      final value = map['inkAutoFadeSeconds'];
      if (value is num) return value.toDouble();
    } catch (_) {}
    return kInkDefaultAutoFadeSeconds;
  }

  Future<void> saveInkAutoFadeSeconds(double seconds) async {
    final map = await _readSettingsMap();
    final next = _normalizeSettingsMap(map);
    next['inkAutoFadeSeconds'] = seconds;
    await _writeSettingsMap(next);
  }

  Future<double> loadInkEraserSize() async {
    try {
      final map = await _readSettingsMap();
      final value = map['inkEraserSize'];
      if (value is num) return value.toDouble();
    } catch (_) {}
    return kInkDefaultEraserSize;
  }

  Future<void> saveInkEraserSize(double size) async {
    final map = await _readSettingsMap();
    final next = _normalizeSettingsMap(map);
    next['inkEraserSize'] = size;
    await _writeSettingsMap(next);
  }

  Future<Color> loadLaserColor() async {
    try {
      final map = await _readSettingsMap();
      final value = map['laserColor'];
      if (value is int) return Color(value);
    } catch (_) {}
    return kLaserDefaultColor;
  }

  Future<void> saveLaserColor(Color color) async {
    final map = await _readSettingsMap();
    final next = _normalizeSettingsMap(map);
    next['laserColor'] = color.toARGB32();
    await _writeSettingsMap(next);
  }

  Future<double> loadLaserSize() async {
    try {
      final map = await _readSettingsMap();
      final value = map['laserSize'];
      if (value is num) return value.toDouble();
    } catch (_) {}
    return kLaserDefaultSize;
  }

  Future<void> saveLaserSize(double size) async {
    final map = await _readSettingsMap();
    final next = _normalizeSettingsMap(map);
    next['laserSize'] = size;
    await _writeSettingsMap(next);
  }

  Future<double> loadLaserFadeSeconds() async {
    try {
      final map = await _readSettingsMap();
      final value = map['laserFadeSeconds'];
      if (value is num) return value.toDouble();
    } catch (_) {}
    return kLaserDefaultFadeSeconds;
  }

  Future<void> saveLaserFadeSeconds(double seconds) async {
    final map = await _readSettingsMap();
    final next = _normalizeSettingsMap(map);
    next['laserFadeSeconds'] = seconds;
    await _writeSettingsMap(next);
  }

  Future<File> _settingsFile() async {
    final directory = await _supportDirectoryProvider();
    return File('${directory.path}/settings.json');
  }

  Map<String, dynamic> _normalizeSettingsMap(Map<String, dynamic> map) {
    if (map.containsKey('shortcuts') ||
        map.containsKey('ocrPreviewEnabled') ||
        map.containsKey('ocrOpenUrlPromptEnabled') ||
        map.containsKey('inkColor') ||
        map.containsKey('inkStrokeWidth') ||
        map.containsKey('inkSmoothingTolerance') ||
        map.containsKey('inkAutoFadeSeconds') ||
        map.containsKey('inkEraserSize') ||
        map.containsKey('laserColor') ||
        map.containsKey('laserSize') ||
        map.containsKey('laserFadeSeconds')) {
      return {...map};
    }
    return {};
  }

  Future<Map<String, dynamic>> _readSettingsMap() async {
    final file = await _settingsFile();
    if (!await file.exists()) {
      return {};
    }
    final raw = jsonDecode(await file.readAsString());
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return {};
  }

  Future<void> _writeSettingsMap(Map<String, dynamic> map) async {
    final file = await _settingsFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(map));
  }
}
