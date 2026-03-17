import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../models/shortcut_bindings.dart';
import '../services/hotkey_service.dart';
import '../services/settings_service.dart';
import '../services/tray_service.dart';
import '../services/window_service.dart';
import '../utils/ink_defaults.dart';

class SettingsState extends ChangeNotifier {
  SettingsState({
    required ShortcutBindings initialShortcuts,
    required bool initialOcrPreviewEnabled,
    required bool initialOcrOpenUrlPromptEnabled,
    required Color initialInkColor,
    required double initialInkStrokeWidth,
    required double initialInkSmoothingTolerance,
    required double initialInkAutoFadeSeconds,
    required double initialInkEraserSize,
    required SettingsService settingsService,
    required WindowService windowService,
    required HotkeyService hotkeyService,
    required TrayService trayService,
  }) : _shortcuts = initialShortcuts,
       _ocrPreviewEnabled = initialOcrPreviewEnabled,
       _ocrOpenUrlPromptEnabled = initialOcrOpenUrlPromptEnabled,
       _inkColor = initialInkColor,
       _inkStrokeWidth = initialInkStrokeWidth,
       _inkSmoothingTolerance = initialInkSmoothingTolerance,
       _inkAutoFadeSeconds = initialInkAutoFadeSeconds,
       _inkEraserSize = initialInkEraserSize,
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
      await _settingsService.saveShortcutBindings(shortcuts);
      _shortcuts = shortcuts;
      notifyListeners();
      return true;
    } catch (error) {
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

  void _applyLaunchAtLoginState(LaunchAtLoginState state) {
    _launchAtLoginSupported = state.supported;
    _launchAtLoginEnabled = state.enabled;
    _launchAtLoginRequiresApproval = state.requiresApproval;
  }
}
