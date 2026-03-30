import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../models/capture_style_settings.dart';
import '../models/shortcut_bindings.dart';
import '../services/hotkey_service.dart';
import '../services/settings_service.dart';
import '../services/tray_service.dart';
import '../services/window_service.dart';
import '../utils/ink_defaults.dart';
import '../utils/laser_defaults.dart';

class SettingsState extends ChangeNotifier {
  SettingsState({
    required ShortcutBindings initialShortcuts,
    required bool initialOcrPreviewEnabled,
    required bool initialOcrOpenUrlPromptEnabled,
    required CaptureStyleSettings initialCaptureStyle,
    required Color initialInkColor,
    required double initialInkStrokeWidth,
    required double initialInkSmoothingTolerance,
    required double initialInkAutoFadeSeconds,
    required double initialInkEraserSize,
    required Color initialLaserColor,
    required double initialLaserSize,
    required double initialLaserFadeSeconds,
    required SettingsService settingsService,
    required WindowService windowService,
    required HotkeyService hotkeyService,
    required TrayService trayService,
  }) : _shortcuts = initialShortcuts,
       _ocrPreviewEnabled = initialOcrPreviewEnabled,
       _ocrOpenUrlPromptEnabled = initialOcrOpenUrlPromptEnabled,
       _captureStyle = initialCaptureStyle,
       _inkColor = initialInkColor,
       _inkStrokeWidth = initialInkStrokeWidth,
       _inkSmoothingTolerance = initialInkSmoothingTolerance,
       _inkAutoFadeSeconds = initialInkAutoFadeSeconds,
       _inkEraserSize = initialInkEraserSize,
       _laserColor = initialLaserColor,
       _laserSize = initialLaserSize,
       _laserFadeSeconds = initialLaserFadeSeconds,
       _settingsService = settingsService,
       _windowService = windowService,
       _hotkeyService = hotkeyService,
       _trayService = trayService;

  final SettingsService _settingsService;
  final WindowService _windowService;
  final HotkeyService _hotkeyService;
  final TrayService _trayService;

  ShortcutBindings _shortcuts;
  ShortcutBindings get shortcuts => _shortcuts;

  bool _ocrPreviewEnabled = false;
  bool get ocrPreviewEnabled => _ocrPreviewEnabled;

  String? _ocrPreviewError;
  String? get ocrPreviewError => _ocrPreviewError;

  bool _ocrOpenUrlPromptEnabled = true;
  bool get ocrOpenUrlPromptEnabled => _ocrOpenUrlPromptEnabled;

  String? _ocrOpenUrlPromptError;
  String? get ocrOpenUrlPromptError => _ocrOpenUrlPromptError;

  CaptureStyleSettings _captureStyle = const CaptureStyleSettings.defaults();
  CaptureStyleSettings get captureStyle => _captureStyle;

  String? _captureStyleError;
  String? get captureStyleError => _captureStyleError;

  Color _inkColor = kInkDefaultColor;
  Color get inkColor => _inkColor;

  double _inkStrokeWidth = kInkDefaultStrokeWidth;
  double get inkStrokeWidth => _inkStrokeWidth;

  double _inkSmoothingTolerance = kInkDefaultSmoothingTolerance;
  double get inkSmoothingTolerance => _inkSmoothingTolerance;

  double _inkAutoFadeSeconds = kInkDefaultAutoFadeSeconds;
  double get inkAutoFadeSeconds => _inkAutoFadeSeconds;

  double _inkEraserSize = kInkDefaultEraserSize;
  double get inkEraserSize => _inkEraserSize;

  Color _laserColor = kLaserDefaultColor;
  Color get laserColor => _laserColor;

  double _laserSize = kLaserDefaultSize;
  double get laserSize => _laserSize;

  double _laserFadeSeconds = kLaserDefaultFadeSeconds;
  double get laserFadeSeconds => _laserFadeSeconds;

  String? _inkColorError;
  String? get inkColorError => _inkColorError;

  String? _inkStrokeWidthError;
  String? get inkStrokeWidthError => _inkStrokeWidthError;

  String? _inkSmoothingError;
  String? get inkSmoothingError => _inkSmoothingError;

  String? _inkAutoFadeError;
  String? get inkAutoFadeError => _inkAutoFadeError;

  String? _inkEraserSizeError;
  String? get inkEraserSizeError => _inkEraserSizeError;

  String? _laserColorError;
  String? get laserColorError => _laserColorError;

  String? _laserSizeError;
  String? get laserSizeError => _laserSizeError;

  String? _laserFadeError;
  String? get laserFadeError => _laserFadeError;

  bool _launchAtLoginSupported = false;
  bool get launchAtLoginSupported => _launchAtLoginSupported;

  bool _launchAtLoginEnabled = false;
  bool get launchAtLoginEnabled => _launchAtLoginEnabled;

  bool _launchAtLoginRequiresApproval = false;
  bool get launchAtLoginRequiresApproval => _launchAtLoginRequiresApproval;

  bool _launchAtLoginBusy = false;
  bool get launchAtLoginBusy => _launchAtLoginBusy;

  String? _launchAtLoginError;
  String? get launchAtLoginError => _launchAtLoginError;

  String? _shortcutError;
  String? get shortcutError => _shortcutError;

  Future<void> refreshLaunchAtLogin() async {
    _launchAtLoginBusy = true;
    _launchAtLoginError = null;
    notifyListeners();

    try {
      final state = await _windowService.getLaunchAtLoginState();
      _applyLaunchAtLoginState(state);
    } catch (error) {
      _launchAtLoginSupported = false;
      _launchAtLoginEnabled = false;
      _launchAtLoginRequiresApproval = false;
      _launchAtLoginError = error.toString();
    } finally {
      _launchAtLoginBusy = false;
      notifyListeners();
    }
  }

  Future<void> setLaunchAtLoginEnabled(bool enabled) async {
    _launchAtLoginBusy = true;
    _launchAtLoginError = null;
    notifyListeners();

    try {
      final state = await _windowService.setLaunchAtLoginEnabled(enabled);
      _applyLaunchAtLoginState(state);
    } catch (error) {
      _launchAtLoginError = error.toString();
    } finally {
      _launchAtLoginBusy = false;
      notifyListeners();
    }
  }

  Future<bool> applyShortcuts(ShortcutBindings shortcuts) async {
    final previousShortcuts = _shortcuts;
    var hotkeysUpdated = false;
    var trayUpdated = false;
    var inkUpdated = false;
    var laserUpdated = false;

    _shortcutError = null;
    notifyListeners();

    try {
      await _hotkeyService.updateBindings(shortcuts);
      hotkeysUpdated = true;
      await _trayService.updateShortcuts(shortcuts);
      trayUpdated = true;
      await _windowService.setInkShortcut(
        shortcuts.forAction(ShortcutAction.ink),
      );
      inkUpdated = true;
      await _windowService.setLaserShortcut(
        shortcuts.forAction(ShortcutAction.laser),
      );
      laserUpdated = true;
      await _settingsService.saveShortcutBindings(shortcuts);
      _shortcuts = shortcuts;
      notifyListeners();
      return true;
    } catch (error) {
      if (laserUpdated) {
        try {
          await _windowService.setLaserShortcut(
            previousShortcuts.forAction(ShortcutAction.laser),
          );
        } catch (_) {}
      }
      if (inkUpdated) {
        try {
          await _windowService.setInkShortcut(
            previousShortcuts.forAction(ShortcutAction.ink),
          );
        } catch (_) {}
      }
      if (trayUpdated) {
        try {
          await _trayService.updateShortcuts(previousShortcuts);
        } catch (_) {}
      }
      if (hotkeysUpdated) {
        try {
          await _hotkeyService.updateBindings(previousShortcuts);
        } catch (_) {}
      }
      _shortcutError = error.toString();
      notifyListeners();
      return false;
    }
  }

  void clearShortcutError() {
    if (_shortcutError == null) return;
    _shortcutError = null;
    notifyListeners();
  }

  Future<void> setOcrPreviewEnabled(bool enabled) async {
    if (_ocrPreviewEnabled == enabled) return;
    final previous = _ocrPreviewEnabled;
    _ocrPreviewEnabled = enabled;
    _ocrPreviewError = null;
    notifyListeners();

    try {
      await _settingsService.saveOcrPreviewEnabled(enabled);
    } catch (error) {
      _ocrPreviewEnabled = previous;
      _ocrPreviewError = error.toString();
      notifyListeners();
    }
  }

  void clearOcrPreviewError() {
    if (_ocrPreviewError == null) return;
    _ocrPreviewError = null;
    notifyListeners();
  }

  Future<void> setOcrOpenUrlPromptEnabled(bool enabled) async {
    if (_ocrOpenUrlPromptEnabled == enabled) return;
    final previous = _ocrOpenUrlPromptEnabled;
    _ocrOpenUrlPromptEnabled = enabled;
    _ocrOpenUrlPromptError = null;
    notifyListeners();

    try {
      await _settingsService.saveOcrOpenUrlPromptEnabled(enabled);
    } catch (error) {
      _ocrOpenUrlPromptEnabled = previous;
      _ocrOpenUrlPromptError = error.toString();
      notifyListeners();
    }
  }

  void clearOcrOpenUrlPromptError() {
    if (_ocrOpenUrlPromptError == null) return;
    _ocrOpenUrlPromptError = null;
    notifyListeners();
  }

  Future<void> setCaptureBorderRadius(double borderRadius) async {
    await _saveCaptureStyle(
      _captureStyle.copyWith(borderRadius: borderRadius).clamped(),
    );
  }

  Future<void> setCapturePadding(double padding) async {
    await _saveCaptureStyle(_captureStyle.copyWith(padding: padding).clamped());
  }

  Future<void> setCaptureShadowEnabled(bool enabled) async {
    await _saveCaptureStyle(_captureStyle.copyWith(shadowEnabled: enabled));
  }

  void clearCaptureStyleError() {
    if (_captureStyleError == null) return;
    _captureStyleError = null;
    notifyListeners();
  }

  Future<void> setInkColor(Color color) async {
    if (_inkColor == color) return;
    final previous = _inkColor;
    _inkColor = color;
    _inkColorError = null;
    notifyListeners();

    try {
      await _settingsService.saveInkColor(color);
    } catch (error) {
      _inkColor = previous;
      _inkColorError = error.toString();
      notifyListeners();
    }
  }

  void clearInkColorError() {
    if (_inkColorError == null) return;
    _inkColorError = null;
    notifyListeners();
  }

  Future<void> setInkStrokeWidth(double width) async {
    if ((_inkStrokeWidth - width).abs() < 0.01) return;
    final previous = _inkStrokeWidth;
    _inkStrokeWidth = width;
    _inkStrokeWidthError = null;
    notifyListeners();

    try {
      await _settingsService.saveInkStrokeWidth(width);
    } catch (error) {
      _inkStrokeWidth = previous;
      _inkStrokeWidthError = error.toString();
      notifyListeners();
    }
  }

  void clearInkStrokeWidthError() {
    if (_inkStrokeWidthError == null) return;
    _inkStrokeWidthError = null;
    notifyListeners();
  }

  Future<void> setInkSmoothingTolerance(double tolerance) async {
    if ((_inkSmoothingTolerance - tolerance).abs() < 0.01) return;
    final previous = _inkSmoothingTolerance;
    _inkSmoothingTolerance = tolerance;
    _inkSmoothingError = null;
    notifyListeners();

    try {
      await _settingsService.saveInkSmoothingTolerance(tolerance);
    } catch (error) {
      _inkSmoothingTolerance = previous;
      _inkSmoothingError = error.toString();
      notifyListeners();
    }
  }

  void clearInkSmoothingError() {
    if (_inkSmoothingError == null) return;
    _inkSmoothingError = null;
    notifyListeners();
  }

  Future<void> setInkAutoFadeSeconds(double seconds) async {
    if ((_inkAutoFadeSeconds - seconds).abs() < 0.01) return;
    final previous = _inkAutoFadeSeconds;
    _inkAutoFadeSeconds = seconds;
    _inkAutoFadeError = null;
    notifyListeners();

    try {
      await _settingsService.saveInkAutoFadeSeconds(seconds);
    } catch (error) {
      _inkAutoFadeSeconds = previous;
      _inkAutoFadeError = error.toString();
      notifyListeners();
    }
  }

  void clearInkAutoFadeError() {
    if (_inkAutoFadeError == null) return;
    _inkAutoFadeError = null;
    notifyListeners();
  }

  Future<void> setInkEraserSize(double size) async {
    if ((_inkEraserSize - size).abs() < 0.01) return;
    final previous = _inkEraserSize;
    _inkEraserSize = size;
    _inkEraserSizeError = null;
    notifyListeners();

    try {
      await _settingsService.saveInkEraserSize(size);
    } catch (error) {
      _inkEraserSize = previous;
      _inkEraserSizeError = error.toString();
      notifyListeners();
    }
  }

  void clearInkEraserSizeError() {
    if (_inkEraserSizeError == null) return;
    _inkEraserSizeError = null;
    notifyListeners();
  }

  Future<void> setLaserColor(Color color) async {
    if (_laserColor == color) return;
    final previous = _laserColor;
    _laserColor = color;
    _laserColorError = null;
    notifyListeners();

    try {
      await _settingsService.saveLaserColor(color);
    } catch (error) {
      _laserColor = previous;
      _laserColorError = error.toString();
      notifyListeners();
    }
  }

  void clearLaserColorError() {
    if (_laserColorError == null) return;
    _laserColorError = null;
    notifyListeners();
  }

  Future<void> setLaserSize(double size) async {
    if ((_laserSize - size).abs() < 0.01) return;
    final previous = _laserSize;
    _laserSize = size;
    _laserSizeError = null;
    notifyListeners();

    try {
      await _settingsService.saveLaserSize(size);
    } catch (error) {
      _laserSize = previous;
      _laserSizeError = error.toString();
      notifyListeners();
    }
  }

  void clearLaserSizeError() {
    if (_laserSizeError == null) return;
    _laserSizeError = null;
    notifyListeners();
  }

  Future<void> setLaserFadeSeconds(double seconds) async {
    if ((_laserFadeSeconds - seconds).abs() < 0.01) return;
    final previous = _laserFadeSeconds;
    _laserFadeSeconds = seconds;
    _laserFadeError = null;
    notifyListeners();

    try {
      await _settingsService.saveLaserFadeSeconds(seconds);
    } catch (error) {
      _laserFadeSeconds = previous;
      _laserFadeError = error.toString();
      notifyListeners();
    }
  }

  void clearLaserFadeError() {
    if (_laserFadeError == null) return;
    _laserFadeError = null;
    notifyListeners();
  }

  Future<void> _saveCaptureStyle(CaptureStyleSettings nextStyle) async {
    final normalized = nextStyle.clamped();
    if (_captureStyle == normalized) return;
    final previous = _captureStyle;
    _captureStyle = normalized;
    _captureStyleError = null;
    notifyListeners();

    try {
      await _settingsService.saveCaptureStyle(normalized);
    } catch (error) {
      _captureStyle = previous;
      _captureStyleError = error.toString();
      notifyListeners();
    }
  }

  void _applyLaunchAtLoginState(LaunchAtLoginState state) {
    _launchAtLoginSupported = state.supported;
    _launchAtLoginEnabled = state.enabled;
    _launchAtLoginRequiresApproval = state.requiresApproval;
  }
}
