import 'package:flutter/material.dart';

import '../models/annotation.dart';

class FloatingAnnotationToolbar extends StatelessWidget {
  const FloatingAnnotationToolbar({
    super.key,
    required this.anchorLink,
    required this.activeTool,
    required this.onToolPressed,
    required this.onActionPressed,
    required this.showPin,
    required this.showHistoryControls,
    required this.canUndo,
    required this.canRedo,
    required this.showOcr,
  });

  final LayerLink anchorLink;
  final ShapeType? activeTool;
  final ValueChanged<ShapeType> onToolPressed;
  final ValueChanged<String> onActionPressed;
  final bool showPin;
  final bool showHistoryControls;
  final bool canUndo;
  final bool canRedo;
  final bool showOcr;

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: anchorLink,
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xE61E1E1E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x33FFFFFF)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final tool in ShapeType.values)
                _ToolbarButton(
                  icon: _toolIcon(tool),
                  tooltip: _toolLabel(tool),
                  selected: activeTool == tool,
                  onPressed: () => onToolPressed(tool),
                ),
              if (showHistoryControls) ...[
                const _ToolbarDivider(),
                _ToolbarButton(
                  icon: Icons.undo_rounded,
                  tooltip: 'Undo',
                  enabled: canUndo,
                  onPressed: canUndo ? () => onActionPressed('undo') : null,
                ),
                _ToolbarButton(
                  icon: Icons.redo_rounded,
                  tooltip: 'Redo',
                  enabled: canRedo,
                  onPressed: canRedo ? () => onActionPressed('redo') : null,
                ),
              ],
              const _ToolbarDivider(),
              _ToolbarButton(
                icon: Icons.copy_rounded,
                tooltip: 'Copy',
                onPressed: () => onActionPressed('copy'),
              ),
              _ToolbarButton(
                icon: Icons.download_rounded,
                tooltip: 'Save',
                onPressed: () => onActionPressed('save'),
              ),
              if (showPin)
                _ToolbarButton(
                  icon: Icons.push_pin_outlined,
                  tooltip: 'Pin',
                  onPressed: () => onActionPressed('pin'),
                ),
              if (showOcr)
                _ToolbarButton(
                  icon: Icons.text_snippet_outlined,
                  tooltip: 'OCR',
                  onPressed: () => onActionPressed('ocr'),
                ),
              _ToolbarButton(
                icon: Icons.close_rounded,
                tooltip: 'Close',
                onPressed: () => onActionPressed('close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _toolIcon(ShapeType type) {
    switch (type) {
      case ShapeType.rectangle:
        return Icons.crop_square_rounded;
      case ShapeType.ellipse:
        return Icons.circle_outlined;
      case ShapeType.arrow:
        return Icons.arrow_right_alt_rounded;
      case ShapeType.line:
        return Icons.horizontal_rule_rounded;
      case ShapeType.pencil:
        return Icons.edit_rounded;
      case ShapeType.marker:
        return Icons.brush_rounded;
      case ShapeType.mosaic:
        return Icons.blur_on_rounded;
      case ShapeType.number:
        return Icons.looks_one_rounded;
      case ShapeType.text:
        return Icons.title_rounded;
    }
  }

  static String _toolLabel(ShapeType type) {
    switch (type) {
      case ShapeType.rectangle:
        return 'Rectangle';
      case ShapeType.ellipse:
        return 'Ellipse';
      case ShapeType.arrow:
        return 'Arrow';
      case ShapeType.line:
        return 'Line';
      case ShapeType.pencil:
        return 'Pencil';
      case ShapeType.marker:
        return 'Marker';
      case ShapeType.mosaic:
        return 'Mosaic';
      case ShapeType.number:
        return 'Number';
      case ShapeType.text:
        return 'Text';
    }
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.enabled = true,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final foreground = enabled
        ? (selected ? Colors.white : Colors.white70)
        : Colors.white24;
    final background = selected ? const Color(0x332984FF) : Colors.transparent;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 350),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: foreground),
          ),
        ),
      ),
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: const Color(0x26FFFFFF),
    );
  }
}
