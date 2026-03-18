import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../models/shortcut_bindings.dart';
import '../state/settings_state.dart';
import '../utils/ink_defaults.dart';
import '../utils/laser_defaults.dart';

const _canvasColor = Color(0xFFF4EEE4);
const _surfaceColor = Color(0xFFF7F4EF);
const _surfaceBorderColor = Color(0xFFD8D0C2);
const _controlFillColor = Color(0xFFFCFAF6);
const _inkColor = Color(0xFF201A13);
const _mutedInkColor = Color(0xFF6A5F52);
const _dangerColor = Color(0xFF982C26);
const _warningColor = Color(0xFF8A5A00);
const _accentColor = Color(0xFF7A6854);
const _inactiveControlColor = Color(0xFFE5DED2);
const _shortcutButtonWidth = 220.0;
const _shortcutActionSlotWidth = 32.0;
const _inkSectionTitle = 'Ink Drawing';
const _inkColorRowHeight = 44.0;
const _laserSectionTitle = 'Laser Pointer';
const _laserColorRowHeight = 44.0;

const _inkPresetColors = [
  Color(0xFFFF0000),
  Color(0xFF00C853),
  Color(0xFF2979FF),
  Color(0xFFFFD600),
  Color(0xFFFFFFFF),
  Color(0xFF000000),
];

const _laserPresetColors = _inkPresetColors;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settingsState,
    required this.onClose,
    required this.onSuspendHotkeys,
    required this.onResumeHotkeys,
  });

  final SettingsState settingsState;
  final Future<void> Function() onClose;
  final Future<void> Function() onSuspendHotkeys;
  final Future<void> Function() onResumeHotkeys;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<ShortcutAction, String> _shortcutValidationErrors = const {};
  ShortcutAction? _busyShortcutAction;

  ShortcutBindings get _defaultShortcuts => ShortcutBindings.defaults();

  Future<void> _closeWindow() async {
    widget.settingsState.clearShortcutError();
    setState(() {
      _shortcutValidationErrors = const {};
    });
    await widget.onClose();
  }

  Future<void> _recordShortcut(ShortcutAction action) async {
    await widget.onSuspendHotkeys();
    HotKey? recorded;
    try {
      if (!mounted) return;
      recorded = await showDialog<HotKey>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _ShortcutCaptureDialog(
          action: action,
          initialHotKey: widget.settingsState.shortcuts.forAction(action),
        ),
      );
    } finally {
      await widget.onResumeHotkeys();
    }

    if (recorded == null || !mounted) return;
    final updated = widget.settingsState.shortcuts.copyWithAction(
      action,
      recorded,
    );
    await _applyShortcutUpdate(action: action, next: updated);
  }

  Future<void> _resetShortcut(ShortcutAction action) async {
    final updated = widget.settingsState.shortcuts.copyWithAction(
      action,
      _defaultShortcuts.forAction(action),
    );
    await _applyShortcutUpdate(action: action, next: updated);
  }

  Future<void> _applyShortcutUpdate({
    required ShortcutAction action,
    required ShortcutBindings next,
  }) async {
    final validation = next.validate();
    if (!validation.isValid) {
      widget.settingsState.clearShortcutError();
      setState(() {
        _shortcutValidationErrors = validation.errors;
      });
      return;
    }

    widget.settingsState.clearShortcutError();
    setState(() {
      _shortcutValidationErrors = const {};
      _busyShortcutAction = action;
    });

    await widget.settingsState.applyShortcuts(next);
    if (!mounted) return;

    setState(() {
      _busyShortcutAction = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final theme = baseTheme.copyWith(
      colorScheme: const ColorScheme.light(surface: _surfaceColor),
      scaffoldBackgroundColor: _canvasColor,
      dividerColor: _surfaceBorderColor,
      textTheme: baseTheme.textTheme.apply(
        bodyColor: _inkColor,
        displayColor: _inkColor,
      ),
    );

    return Theme(
      data: theme,
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            _closeWindow();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Material(
          color: _canvasColor,
          child: ListenableBuilder(
            listenable: widget.settingsState,
            builder: (context, _) {
              final shortcutEntries = widget.settingsState.shortcuts.entries
                  .toList(growable: false);
              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Header(onClose: _closeWindow),
                    const SizedBox(height: 20),
                    Expanded(
                      child: Scrollbar(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'General',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 12),
                              _SurfaceGroup(
                                child: Column(
                                  children: [
                                    _LaunchAtLoginRow(
                                      settingsState: widget.settingsState,
                                    ),
                                    const _GroupDivider(),
                                    _OcrPreviewRow(
                                      settingsState: widget.settingsState,
                                    ),
                                    const _GroupDivider(),
                                    _OcrOpenUrlPromptRow(
                                      settingsState: widget.settingsState,
                                    ),
                                  ],
                                ),
                              ),
                              if (widget.settingsState.launchAtLoginBusy) ...[
                                const SizedBox(height: 10),
                                const _SectionNote(
                                  text: 'Saving launch at login preference...',
                                ),
                              ],
                              if (widget
                                  .settingsState
                                  .launchAtLoginRequiresApproval) ...[
                                const SizedBox(height: 10),
                                const _SectionNote(
                                  text:
                                      'macOS still requires approval in System Settings before launch at login will work.',
                                  color: _warningColor,
                                ),
                              ],
                              if (widget.settingsState.launchAtLoginError !=
                                  null) ...[
                                const SizedBox(height: 10),
                                _SectionNote(
                                  text:
                                      widget.settingsState.launchAtLoginError!,
                                  color: _dangerColor,
                                ),
                              ],
                              if (widget.settingsState.ocrPreviewError !=
                                  null) ...[
                                const SizedBox(height: 10),
                                _SectionNote(
                                  text: widget.settingsState.ocrPreviewError!,
                                  color: _dangerColor,
                                ),
                              ],
                              if (widget.settingsState.ocrOpenUrlPromptError !=
                                  null) ...[
                                const SizedBox(height: 10),
                                _SectionNote(
                                  text: widget
                                      .settingsState
                                      .ocrOpenUrlPromptError!,
                                  color: _dangerColor,
                                ),
                              ],
                              const SizedBox(height: 28),
                              Text(
                                'Shortcuts',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 12),
                              _SurfaceGroup(
                                child: Column(
                                  children: [
                                    for (
                                      var i = 0;
                                      i < shortcutEntries.length;
                                      i++
                                    ) ...[
                                      if (i > 0) const _GroupDivider(),
                                      _ShortcutRow(
                                        action: shortcutEntries[i].key,
                                        hotKey: shortcutEntries[i].value,
                                        defaultHotKey: _defaultShortcuts
                                            .forAction(shortcutEntries[i].key),
                                        error:
                                            _shortcutValidationErrors[shortcutEntries[i]
                                                .key],
                                        isBusy:
                                            _busyShortcutAction ==
                                            shortcutEntries[i].key,
                                        onRecord: () => _recordShortcut(
                                          shortcutEntries[i].key,
                                        ),
                                        onReset: () => _resetShortcut(
                                          shortcutEntries[i].key,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (widget.settingsState.shortcutError !=
                                  null) ...[
                                const SizedBox(height: 10),
                                _SectionNote(
                                  text: widget.settingsState.shortcutError!,
                                  color: _dangerColor,
                                ),
                              ],
                              const SizedBox(height: 28),
                              Text(
                                _inkSectionTitle,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 12),
                              _SurfaceGroup(
                                child: Column(
                                  children: [
                                    _InkColorRow(
                                      color: widget.settingsState.inkColor,
                                      onColorPicked: (color) {
                                        widget.settingsState
                                            .clearInkColorError();
                                        unawaited(
                                          widget.settingsState.setInkColor(
                                            color,
                                          ),
                                        );
                                      },
                                    ),
                                    const _GroupDivider(),
                                    _InkStrokeRow(
                                      strokeWidth:
                                          widget.settingsState.inkStrokeWidth,
                                      onStrokeWidthChanged: (value) {
                                        widget.settingsState
                                            .clearInkStrokeWidthError();
                                        unawaited(
                                          widget.settingsState
                                              .setInkStrokeWidth(value),
                                        );
                                      },
                                    ),
                                    const _GroupDivider(),
                                    _InkSmoothingRow(
                                      tolerance: widget
                                          .settingsState
                                          .inkSmoothingTolerance,
                                      onToleranceChanged: (value) {
                                        widget.settingsState
                                            .clearInkSmoothingError();
                                        unawaited(
                                          widget.settingsState
                                              .setInkSmoothingTolerance(value),
                                        );
                                      },
                                    ),
                                    const _GroupDivider(),
                                    _InkAutoFadeRow(
                                      seconds: widget
                                          .settingsState
                                          .inkAutoFadeSeconds,
                                      onSecondsChanged: (value) {
                                        widget.settingsState
                                            .clearInkAutoFadeError();
                                        unawaited(
                                          widget.settingsState
                                              .setInkAutoFadeSeconds(value),
                                        );
                                      },
                                    ),
                                    const _GroupDivider(),
                                    _InkEraserSizeRow(
                                      size: widget.settingsState.inkEraserSize,
                                      onSizeChanged: (value) {
                                        widget.settingsState
                                            .clearInkEraserSizeError();
                                        unawaited(
                                          widget.settingsState.setInkEraserSize(
                                            value,
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              const _SectionNote(
                                text:
                                    'Right-click to erase while drawing. Hold'
                                    ' right-click and scroll to resize the'
                                    ' eraser.',
                              ),
                              if (widget.settingsState.inkColorError != null ||
                                  widget.settingsState.inkStrokeWidthError !=
                                      null ||
                                  widget.settingsState.inkSmoothingError !=
                                      null ||
                                  widget.settingsState.inkAutoFadeError !=
                                      null ||
                                  widget.settingsState.inkEraserSizeError !=
                                      null) ...[
                                const SizedBox(height: 10),
                                _SectionNote(
                                  text: [
                                    if (widget.settingsState.inkColorError !=
                                        null)
                                      widget.settingsState.inkColorError!,
                                    if (widget
                                            .settingsState
                                            .inkStrokeWidthError !=
                                        null)
                                      widget.settingsState.inkStrokeWidthError!,
                                    if (widget
                                            .settingsState
                                            .inkSmoothingError !=
                                        null)
                                      widget.settingsState.inkSmoothingError!,
                                    if (widget.settingsState.inkAutoFadeError !=
                                        null)
                                      widget.settingsState.inkAutoFadeError!,
                                    if (widget
                                            .settingsState
                                            .inkEraserSizeError !=
                                        null)
                                      widget.settingsState.inkEraserSizeError!,
                                  ].join(' '),
                                  color: _dangerColor,
                                ),
                              ],
                              const SizedBox(height: 28),
                              Text(
                                _laserSectionTitle,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 12),
                              _SurfaceGroup(
                                child: Column(
                                  children: [
                                    _LaserColorRow(
                                      color: widget.settingsState.laserColor,
                                      onColorPicked: (color) {
                                        widget.settingsState
                                            .clearLaserColorError();
                                        unawaited(
                                          widget.settingsState.setLaserColor(
                                            color,
                                          ),
                                        );
                                      },
                                    ),
                                    const _GroupDivider(),
                                    _LaserSizeRow(
                                      size: widget.settingsState.laserSize,
                                      onSizeChanged: (value) {
                                        widget.settingsState
                                            .clearLaserSizeError();
                                        unawaited(
                                          widget.settingsState.setLaserSize(
                                            value,
                                          ),
                                        );
                                      },
                                    ),
                                    const _GroupDivider(),
                                    _LaserFadeRow(
                                      seconds:
                                          widget.settingsState.laserFadeSeconds,
                                      onSecondsChanged: (value) {
                                        widget.settingsState
                                            .clearLaserFadeError();
                                        unawaited(
                                          widget.settingsState
                                              .setLaserFadeSeconds(value),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              const _SectionNote(
                                text:
                                    'Hold the laser shortcut to show a pointer.'
                                    ' Release to let it fade out.',
                              ),
                              if (widget.settingsState.laserColorError !=
                                      null ||
                                  widget.settingsState.laserSizeError != null ||
                                  widget.settingsState.laserFadeError !=
                                      null) ...[
                                const SizedBox(height: 10),
                                _SectionNote(
                                  text: [
                                    if (widget.settingsState.laserColorError !=
                                        null)
                                      widget.settingsState.laserColorError!,
                                    if (widget.settingsState.laserSizeError !=
                                        null)
                                      widget.settingsState.laserSizeError!,
                                    if (widget.settingsState.laserFadeError !=
                                        null)
                                      widget.settingsState.laserFadeError!,
                                  ].join(' '),
                                  color: _dangerColor,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose});

  final Future<void> Function() onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Settings',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Close',
          onPressed: onClose,
          splashRadius: 18,
          visualDensity: VisualDensity.compact,
          color: _mutedInkColor,
          icon: const Icon(Icons.close_rounded, size: 20),
        ),
      ],
    );
  }
}

class _SurfaceGroup extends StatelessWidget {
  const _SurfaceGroup({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _surfaceBorderColor),
      ),
      child: child,
    );
  }
}

class _GroupDivider extends StatelessWidget {
  const _GroupDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, color: _surfaceBorderColor);
  }
}

class _LaunchAtLoginRow extends StatelessWidget {
  const _LaunchAtLoginRow({required this.settingsState});

  final SettingsState settingsState;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Launch at login',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (!settingsState.launchAtLoginSupported)
            Text(
              'Unavailable',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _mutedInkColor,
                fontWeight: FontWeight.w600,
              ),
            )
          else if (settingsState.launchAtLoginBusy)
            const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            )
          else
            Switch.adaptive(
              value: settingsState.launchAtLoginEnabled,
              activeTrackColor: _accentColor,
              activeThumbColor: _controlFillColor,
              inactiveTrackColor: _inactiveControlColor,
              inactiveThumbColor: _controlFillColor,
              trackOutlineColor: const WidgetStatePropertyAll(
                _surfaceBorderColor,
              ),
              onChanged:
                  settingsState.launchAtLoginSupported &&
                      !settingsState.launchAtLoginBusy
                  ? settingsState.setLaunchAtLoginEnabled
                  : null,
            ),
        ],
      ),
    );
  }
}

class _OcrPreviewRow extends StatelessWidget {
  const _OcrPreviewRow({required this.settingsState});

  final SettingsState settingsState;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Show OCR preview',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Switch.adaptive(
            value: settingsState.ocrPreviewEnabled,
            activeTrackColor: _accentColor,
            activeThumbColor: _controlFillColor,
            inactiveTrackColor: _inactiveControlColor,
            inactiveThumbColor: _controlFillColor,
            trackOutlineColor: const WidgetStatePropertyAll(
              _surfaceBorderColor,
            ),
            onChanged: (value) {
              settingsState.clearOcrPreviewError();
              settingsState.setOcrPreviewEnabled(value);
            },
          ),
        ],
      ),
    );
  }
}

class _OcrOpenUrlPromptRow extends StatelessWidget {
  const _OcrOpenUrlPromptRow({required this.settingsState});

  final SettingsState settingsState;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Prompt to open URL after OCR',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Switch.adaptive(
            value: settingsState.ocrOpenUrlPromptEnabled,
            activeTrackColor: _accentColor,
            activeThumbColor: _controlFillColor,
            inactiveTrackColor: _inactiveControlColor,
            inactiveThumbColor: _controlFillColor,
            trackOutlineColor: const WidgetStatePropertyAll(
              _surfaceBorderColor,
            ),
            onChanged: (value) {
              settingsState.clearOcrOpenUrlPromptError();
              settingsState.setOcrOpenUrlPromptEnabled(value);
            },
          ),
        ],
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({
    required this.action,
    required this.hotKey,
    required this.defaultHotKey,
    required this.error,
    required this.isBusy,
    required this.onRecord,
    required this.onReset,
  });

  final ShortcutAction action;
  final HotKey hotKey;
  final HotKey defaultHotKey;
  final String? error;
  final bool isBusy;
  final VoidCallback onRecord;
  final VoidCallback onReset;

  bool get _isDefault =>
      shortcutSignature(hotKey) == shortcutSignature(defaultHotKey);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  action.label,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: _shortcutButtonWidth + _shortcutActionSlotWidth + 8,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: _shortcutButtonWidth,
                      child: _ShortcutButton(
                        label: isBusy
                            ? 'Saving...'
                            : shortcutDisplayLabel(hotKey),
                        enabled: !isBusy,
                        onPressed: onRecord,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: _shortcutActionSlotWidth,
                      child: !_isDefault
                          ? IconButton(
                              onPressed: isBusy ? null : onReset,
                              tooltip: 'Reset',
                              splashRadius: 18,
                              visualDensity: VisualDensity.compact,
                              color: _mutedInkColor,
                              icon: const Icon(Icons.close_rounded, size: 18),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(
              error!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _dangerColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ShortcutButton extends StatelessWidget {
  const _ShortcutButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: enabled ? onPressed : null,
      style: OutlinedButton.styleFrom(
        backgroundColor: _controlFillColor,
        foregroundColor: _inkColor,
        side: const BorderSide(color: _surfaceBorderColor),
        minimumSize: const Size(_shortcutButtonWidth, 40),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: _inkColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SectionNote extends StatelessWidget {
  const _SectionNote({required this.text, this.color = _mutedInkColor});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: color,
          height: 1.45,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _InkColorRow extends StatelessWidget {
  const _InkColorRow({required this.color, required this.onColorPicked});

  final Color color;
  final ValueChanged<Color> onColorPicked;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _inkColorRowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Color',
                style: TextStyle(color: _inkColor, fontWeight: FontWeight.w600),
              ),
            ),
            for (final preset in _inkPresetColors) ...[
              _InkColorSwatch(
                color: preset,
                isSelected: color == preset,
                onTap: () => onColorPicked(preset),
              ),
              const SizedBox(width: 6),
            ],
            _InkCustomColorButton(
              currentColor: color,
              onColorPicked: onColorPicked,
            ),
          ],
        ),
      ),
    );
  }
}

class _InkStrokeRow extends StatelessWidget {
  const _InkStrokeRow({
    required this.strokeWidth,
    required this.onStrokeWidthChanged,
  });

  final double strokeWidth;
  final ValueChanged<double> onStrokeWidthChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Stroke',
                  style: TextStyle(
                    color: _inkColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${strokeWidth.round()}px',
                style: const TextStyle(
                  color: _mutedInkColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _accentColor,
              inactiveTrackColor: _inactiveControlColor,
              thumbColor: _accentColor,
              overlayColor: _accentColor.withValues(alpha: 0.15),
              trackHeight: 3,
            ),
            child: Slider(
              value: strokeWidth.clamp(kInkMinStrokeWidth, kInkMaxStrokeWidth),
              min: kInkMinStrokeWidth,
              max: kInkMaxStrokeWidth,
              divisions: (kInkMaxStrokeWidth - kInkMinStrokeWidth).round(),
              onChanged: onStrokeWidthChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _InkSmoothingRow extends StatelessWidget {
  const _InkSmoothingRow({
    required this.tolerance,
    required this.onToleranceChanged,
  });

  final double tolerance;
  final ValueChanged<double> onToleranceChanged;

  @override
  Widget build(BuildContext context) {
    final clamped = tolerance.clamp(
      kInkMinSmoothingTolerance,
      kInkMaxSmoothingTolerance,
    );
    final divisions =
        ((kInkMaxSmoothingTolerance - kInkMinSmoothingTolerance) / 0.5).round();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Smoothing',
                  style: TextStyle(
                    color: _inkColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                clamped.toStringAsFixed(1),
                style: const TextStyle(
                  color: _mutedInkColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _accentColor,
              inactiveTrackColor: _inactiveControlColor,
              thumbColor: _accentColor,
              overlayColor: _accentColor.withValues(alpha: 0.15),
              trackHeight: 3,
            ),
            child: Slider(
              value: clamped,
              min: kInkMinSmoothingTolerance,
              max: kInkMaxSmoothingTolerance,
              divisions: divisions > 0 ? divisions : null,
              onChanged: onToleranceChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _InkAutoFadeRow extends StatelessWidget {
  const _InkAutoFadeRow({
    required this.seconds,
    required this.onSecondsChanged,
  });

  final double seconds;
  final ValueChanged<double> onSecondsChanged;

  @override
  Widget build(BuildContext context) {
    final clamped = seconds.clamp(
      kInkMinAutoFadeSeconds,
      kInkMaxAutoFadeSeconds,
    );
    final divisions = ((kInkMaxAutoFadeSeconds - kInkMinAutoFadeSeconds) / 0.5)
        .round();
    final label = clamped <= 0.01 ? 'Off' : '${clamped.toStringAsFixed(1)}s';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Auto-fade',
                  style: TextStyle(
                    color: _inkColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  color: _mutedInkColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _accentColor,
              inactiveTrackColor: _inactiveControlColor,
              thumbColor: _accentColor,
              overlayColor: _accentColor.withValues(alpha: 0.15),
              trackHeight: 3,
            ),
            child: Slider(
              value: clamped,
              min: kInkMinAutoFadeSeconds,
              max: kInkMaxAutoFadeSeconds,
              divisions: divisions > 0 ? divisions : null,
              onChanged: onSecondsChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _InkEraserSizeRow extends StatelessWidget {
  const _InkEraserSizeRow({required this.size, required this.onSizeChanged});

  final double size;
  final ValueChanged<double> onSizeChanged;

  @override
  Widget build(BuildContext context) {
    final clamped = size.clamp(kInkMinEraserSize, kInkMaxEraserSize);
    final divisions = (kInkMaxEraserSize - kInkMinEraserSize).round();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Eraser size',
                  style: TextStyle(
                    color: _inkColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${clamped.round()}px',
                style: const TextStyle(
                  color: _mutedInkColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _accentColor,
              inactiveTrackColor: _inactiveControlColor,
              thumbColor: _accentColor,
              overlayColor: _accentColor.withValues(alpha: 0.15),
              trackHeight: 3,
            ),
            child: Slider(
              value: clamped,
              min: kInkMinEraserSize,
              max: kInkMaxEraserSize,
              divisions: divisions > 0 ? divisions : null,
              onChanged: onSizeChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _LaserColorRow extends StatelessWidget {
  const _LaserColorRow({required this.color, required this.onColorPicked});

  final Color color;
  final ValueChanged<Color> onColorPicked;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _laserColorRowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Color',
                style: TextStyle(color: _inkColor, fontWeight: FontWeight.w600),
              ),
            ),
            for (final preset in _laserPresetColors) ...[
              _InkColorSwatch(
                color: preset,
                isSelected: color == preset,
                onTap: () => onColorPicked(preset),
              ),
              const SizedBox(width: 6),
            ],
            _InkCustomColorButton(
              currentColor: color,
              onColorPicked: onColorPicked,
            ),
          ],
        ),
      ),
    );
  }
}

class _LaserSizeRow extends StatelessWidget {
  const _LaserSizeRow({required this.size, required this.onSizeChanged});

  final double size;
  final ValueChanged<double> onSizeChanged;

  @override
  Widget build(BuildContext context) {
    final clamped = size.clamp(kLaserMinSize, kLaserMaxSize);
    final divisions = (kLaserMaxSize - kLaserMinSize).round();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Size',
                  style: TextStyle(
                    color: _inkColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${clamped.round()}px',
                style: const TextStyle(
                  color: _mutedInkColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _accentColor,
              inactiveTrackColor: _inactiveControlColor,
              thumbColor: _accentColor,
              overlayColor: _accentColor.withValues(alpha: 0.15),
              trackHeight: 3,
            ),
            child: Slider(
              value: clamped,
              min: kLaserMinSize,
              max: kLaserMaxSize,
              divisions: divisions > 0 ? divisions : null,
              onChanged: onSizeChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _LaserFadeRow extends StatelessWidget {
  const _LaserFadeRow({required this.seconds, required this.onSecondsChanged});

  final double seconds;
  final ValueChanged<double> onSecondsChanged;

  @override
  Widget build(BuildContext context) {
    final clamped = seconds.clamp(kLaserMinFadeSeconds, kLaserMaxFadeSeconds);
    final divisions = ((kLaserMaxFadeSeconds - kLaserMinFadeSeconds) / 0.1)
        .round();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Fade',
                  style: TextStyle(
                    color: _inkColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${clamped.toStringAsFixed(1)}s',
                style: const TextStyle(
                  color: _mutedInkColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _accentColor,
              inactiveTrackColor: _inactiveControlColor,
              thumbColor: _accentColor,
              overlayColor: _accentColor.withValues(alpha: 0.15),
              trackHeight: 3,
            ),
            child: Slider(
              value: clamped,
              min: kLaserMinFadeSeconds,
              max: kLaserMaxFadeSeconds,
              divisions: divisions > 0 ? divisions : null,
              onChanged: onSecondsChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _InkColorSwatch extends StatelessWidget {
  const _InkColorSwatch({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? _accentColor : _surfaceBorderColor,
            width: isSelected ? 2 : 1,
          ),
        ),
      ),
    );
  }
}

class _InkCustomColorButton extends StatelessWidget {
  const _InkCustomColorButton({
    required this.currentColor,
    required this.onColorPicked,
  });

  final Color currentColor;
  final ValueChanged<Color> onColorPicked;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Custom color',
      visualDensity: VisualDensity.compact,
      splashRadius: 18,
      icon: const Icon(
        Icons.color_lens_outlined,
        size: 18,
        color: _mutedInkColor,
      ),
      onPressed: () async {
        var nextColor = currentColor;
        await showDialog<void>(
          context: context,
          builder: (context) {
            return AlertDialog(
              backgroundColor: _surfaceColor,
              title: const Text('Pick color'),
              content: SingleChildScrollView(
                child: ColorPicker(
                  pickerColor: currentColor,
                  onColorChanged: (color) => nextColor = color,
                  enableAlpha: true,
                  labelTypes: const [],
                  pickerAreaHeightPercent: 0.7,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    onColorPicked(nextColor);
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _ShortcutCaptureDialog extends StatefulWidget {
  const _ShortcutCaptureDialog({
    required this.action,
    required this.initialHotKey,
  });

  final ShortcutAction action;
  final HotKey initialHotKey;

  @override
  State<_ShortcutCaptureDialog> createState() => _ShortcutCaptureDialogState();
}

class _ShortcutCaptureDialogState extends State<_ShortcutCaptureDialog> {
  static const _shortcutRecorderChannel = MethodChannel(
    'com.asnap/shortcutRecorder',
  );

  HotKey? _capturedHotKey;
  List<HotKeyModifier> _pressedModifiers = const [];
  final Set<PhysicalKeyboardKey> _pressedKeys = <PhysicalKeyboardKey>{};
  final FocusNode _focusNode = FocusNode(debugLabel: 'shortcutCaptureDialog');

  @override
  void initState() {
    super.initState();
    if (Platform.isMacOS) {
      _shortcutRecorderChannel.setMethodCallHandler(_handleNativeRecorderCall);
      unawaited(_shortcutRecorderChannel.invokeMethod('start'));
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    if (Platform.isMacOS) {
      _shortcutRecorderChannel.setMethodCallHandler(null);
      unawaited(_shortcutRecorderChannel.invokeMethod('stop'));
    }
    _focusNode.dispose();
    super.dispose();
  }

  String? get _captureError {
    final hotKey = _capturedHotKey;
    if (hotKey == null) return null;
    if ((hotKey.modifiers ?? const <HotKeyModifier>[]).isEmpty) {
      return 'Use at least one modifier key.';
    }
    if (isShortcutModifierKey(hotKey.physicalKey)) {
      return 'Add a non-modifier key.';
    }
    return null;
  }

  bool get _canUseShortcut => _capturedHotKey != null && _captureError == null;

  List<HotKeyModifier> _currentPressedModifiers() {
    return shortcutModifiersFromPressedKeys(_pressedKeys);
  }

  Future<void> _handleNativeRecorderCall(MethodCall call) async {
    if (!mounted) return;

    switch (call.method) {
      case 'onShortcutRecorderChanged':
        final modifiers = _nativeModifiersFromCall(call.arguments);
        setState(() {
          _pressedModifiers = modifiers;
        });
        return;
      case 'onShortcutRecorderCaptured':
        final args = call.arguments as Map<dynamic, dynamic>?;
        final keyCode = (args?['keyCode'] as num?)?.toInt();
        if (keyCode == null) {
          return;
        }
        final physicalKey = kMacOsToPhysicalKey[keyCode];
        if (physicalKey == null) {
          return;
        }
        final modifiers = _nativeModifiersFromCall(args);
        setState(() {
          _pressedModifiers = modifiers;
          _capturedHotKey = normalizeShortcutHotKey(
            widget.action,
            HotKey(
              identifier: widget.action.id,
              key: physicalKey,
              modifiers: modifiers.isEmpty ? null : modifiers,
              scope: HotKeyScope.system,
            ),
          );
        });
        return;
      case 'onShortcutRecorderCancelled':
        Navigator.of(context).pop();
        return;
      default:
        return;
    }
  }

  List<HotKeyModifier> _nativeModifiersFromCall(Object? rawArguments) {
    if (rawArguments is! Map) {
      return const [];
    }

    final rawModifiers = rawArguments['modifiers'];
    if (rawModifiers is! List) {
      return const [];
    }

    final modifiers = rawModifiers
        .whereType<String>()
        .map((name) {
          for (final modifier in HotKeyModifier.values) {
            if (modifier.name == name) {
              return modifier;
            }
          }
          return null;
        })
        .whereType<HotKeyModifier>()
        .toList(growable: false);

    return sortModifiers(modifiers);
  }

  KeyEventResult _handleHardwareKeyEvent(KeyEvent event) {
    if (Platform.isMacOS) {
      return KeyEventResult.ignored;
    }

    if (event is KeyUpEvent) {
      _pressedKeys.remove(event.physicalKey);
      if (isShortcutModifierKey(event.physicalKey)) {
        setState(() {
          _pressedModifiers = _currentPressedModifiers();
        });
      }
      return KeyEventResult.handled;
    }

    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }

    _pressedKeys.add(event.physicalKey);
    final currentlyPressedModifiers = _currentPressedModifiers();
    if (isShortcutModifierKey(event.physicalKey)) {
      setState(() {
        _pressedModifiers = currentlyPressedModifiers;
      });
      return KeyEventResult.handled;
    }

    setState(() {
      _pressedModifiers = currentlyPressedModifiers;
      _capturedHotKey = normalizeShortcutHotKey(
        widget.action,
        HotKey(
          identifier: widget.action.id,
          key: event.physicalKey,
          modifiers: currentlyPressedModifiers.isEmpty
              ? null
              : currentlyPressedModifiers,
          scope: HotKeyScope.system,
        ),
      );
    });
    return KeyEventResult.handled;
  }

  List<String> get _previewParts {
    if (_capturedHotKey != null) {
      return shortcutDisplayParts(_capturedHotKey!);
    }
    if (_pressedModifiers.isNotEmpty) {
      return [..._pressedModifiers.map(shortcutModifierLabel), '...'];
    }
    return shortcutDisplayParts(widget.initialHotKey);
  }

  @override
  Widget build(BuildContext context) {
    final content = Dialog(
      backgroundColor: _surfaceColor,
      insetPadding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Record ${widget.action.label}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Press the full shortcut now. Ctrl, Cmd, Option, Shift, Fn, and Caps Lock can all be used as modifiers.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _mutedInkColor,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              _ShortcutVisual(parts: _previewParts),
              if (_capturedHotKey == null && _pressedModifiers.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Press a non-modifier key to complete the shortcut.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _mutedInkColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (_captureError != null) ...[
                const SizedBox(height: 14),
                Text(
                  _captureError!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _dangerColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _canUseShortcut
                        ? () => Navigator.of(context).pop(_capturedHotKey)
                        : null,
                    child: const Text('Use Shortcut'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (Platform.isMacOS) {
      return content;
    }

    return Focus(
      autofocus: true,
      focusNode: _focusNode,
      onKeyEvent: (_, event) => _handleHardwareKeyEvent(event),
      child: content,
    );
  }
}

class _ShortcutVisual extends StatelessWidget {
  const _ShortcutVisual({required this.parts});

  final List<String> parts;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final part in parts)
          DecoratedBox(
            decoration: BoxDecoration(
              color: _controlFillColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _surfaceBorderColor),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                part,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: _inkColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
