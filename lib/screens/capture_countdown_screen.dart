import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_state.dart';

class CaptureCountdownScreen extends StatefulWidget {
  const CaptureCountdownScreen({
    super.key,
    required this.kind,
    required this.secondsRemaining,
    required this.onCancel,
  });

  final CaptureKind kind;
  final int secondsRemaining;
  final VoidCallback onCancel;

  @override
  State<CaptureCountdownScreen> createState() => _CaptureCountdownScreenState();
}

class _CaptureCountdownScreenState extends State<CaptureCountdownScreen> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    widget.onCancel();
    return KeyEventResult.handled;
  }

  String get _title {
    return switch (widget.kind) {
      CaptureKind.region => 'Region capture',
      CaptureKind.fullScreen => 'Full screen capture',
      CaptureKind.scroll => 'Scroll capture',
      CaptureKind.ocr => 'OCR capture',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Focus(
        focusNode: _focusNode,
        onKeyEvent: _handleKeyEvent,
        autofocus: true,
        child: Center(
          child: RepaintBoundary(
            key: const Key('capture-countdown'),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xE61B1C1E),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0x1FFFFFFF)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 18,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${widget.secondsRemaining}',
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Press Esc to cancel',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xCCFFFFFF),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
