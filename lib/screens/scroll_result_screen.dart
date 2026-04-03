import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/capture_style_settings.dart';
import '../services/window_service.dart';
import '../state/annotation_state.dart';
import '../utils/capture_style_renderer.dart';
import '../utils/hardware_keyboard_helpers.dart';
import '../utils/toolbar_layout.dart';
import '../widgets/annotation_overlay.dart';
import '../widgets/capture_style_frame.dart';
import '../widgets/floating_annotation_toolbar.dart';
import '../widgets/native_toolbar_mixin.dart';
import '../widgets/qr_code_overlay.dart';
import '../widgets/transparent_clear_layer.dart';
import '../widgets/tool_popover_mixin.dart';

/// Fullscreen overlay that displays a scroll capture result.
///
/// The stitched image is shown in a centered, scrollable container with a
/// semi-transparent scrim behind it. Toolbar controls are rendered in a
/// separate native floating panel.
class ScrollResultScreen extends StatefulWidget {
  final ui.Image stitchedImage;
  final AnnotationState annotationState;
  final WindowService windowService;
  final VoidCallback onCopy;
  final VoidCallback onSave;
  final VoidCallback onDiscard;
  final VoidCallback onOcr;
  final ValueChanged<String> onCopyText;
  final CaptureStyleSettings captureStyle;
  final double captureScale;
  final bool showCaptureStyleChrome;

  const ScrollResultScreen({
    super.key,
    required this.stitchedImage,
    required this.annotationState,
    required this.windowService,
    required this.onCopy,
    required this.onSave,
    required this.onDiscard,
    required this.onOcr,
    required this.onCopyText,
    required this.captureStyle,
    required this.captureScale,
    required this.showCaptureStyleChrome,
  });

  @override
  State<ScrollResultScreen> createState() => _ScrollResultScreenState();
}

class _ScrollResultScreenState extends State<ScrollResultScreen>
    with ToolPopoverMixin, NativeToolbarMixin {
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();

  final _popoverAnchorLink = LayerLink();

  Rect _snapRect(Rect rect, double devicePixelRatio) {
    final left =
        (rect.left * devicePixelRatio).floorToDouble() / devicePixelRatio;
    final top =
        (rect.top * devicePixelRatio).floorToDouble() / devicePixelRatio;
    final right =
        (rect.right * devicePixelRatio).ceilToDouble() / devicePixelRatio;
    final bottom =
        (rect.bottom * devicePixelRatio).ceilToDouble() / devicePixelRatio;
    return Rect.fromLTRB(left, top, right, bottom);
  }

  @override
  AnnotationState get popoverAnnotationState => widget.annotationState;

  @override
  LayerLink get popoverAnchor => _popoverAnchorLink;

  @override
  WindowService get nativeToolbarWindowService => widget.windowService;

  @override
  AnnotationState get nativeToolbarAnnotationState => widget.annotationState;

  @override
  bool get nativeToolbarShowPin => false;

  @override
  bool get nativeToolbarShowOcr => Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    initNativeToolbar();
  }

  @override
  void dispose() {
    disposeNativeToolbar();
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    removePopover();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Keyboard
  // ---------------------------------------------------------------------------

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final primaryModifier = isPrimaryShortcutModifierPressed();
    final shift = isShiftModifierPressed();

    // Primary+Shift+Z -> redo
    if (primaryModifier &&
        shift &&
        event.logicalKey == LogicalKeyboardKey.keyZ) {
      widget.annotationState.redo();
      return true;
    }
    // Primary+Z -> undo
    if (primaryModifier && event.logicalKey == LogicalKeyboardKey.keyZ) {
      widget.annotationState.undo();
      return true;
    }
    // Delete/Backspace → delete selected annotation.
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      if (widget.annotationState.editingText) return false;
      if (widget.annotationState.selectedIndex != null) {
        widget.annotationState.deleteSelected();
        return true;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (widget.annotationState.editingText) {
        widget.annotationState.cancelTextEdit();
        return true;
      }
      if (popoverVisible) {
        removePopover();
        return true;
      }
      if (activeShapeType != null) {
        setState(() => activeShapeType = null);
        return true;
      }
      widget.onDiscard();
      return true;
    }
    return false;
  }

  @override
  void handleNativeToolbarAction(String action) {
    switch (action) {
      case 'copy':
        widget.onCopy();
        return;
      case 'save':
        widget.onSave();
        return;
      case 'ocr':
        widget.onOcr();
        return;
      case 'close':
        widget.onDiscard();
        return;
      default:
        return;
    }
  }

  // ---------------------------------------------------------------------------
  // Image container sizing
  // ---------------------------------------------------------------------------

  /// Compute the display rect for the image container, centered on screen.
  ///
  /// Width and height are computed independently because the container scrolls
  /// vertically — capping the height must NOT shrink the width.
  Rect _imageContainerRect(
    Size screenSize, {
    required CaptureStyleLayout captureLayout,
    required double reservedToolbarHeight,
  }) {
    final maxW = screenSize.width * 0.9;
    final availableHeight =
        (screenSize.height - reservedToolbarHeight - kToolbarGap * 2).clamp(
          1.0,
          screenSize.height,
        );
    final maxH = availableHeight < screenSize.height * 0.85
        ? availableHeight
        : screenSize.height * 0.85;

    final rawOuterWidth = captureLayout.outerSize.width;
    final rawContentWidth = captureLayout.contentSize.width;
    final rawContentHeight = captureLayout.contentSize.height;
    final scale = rawOuterWidth > maxW ? maxW / rawOuterWidth : 1.0;
    final scaledInsets = EdgeInsets.fromLTRB(
      captureLayout.outerInsets.left * scale,
      captureLayout.outerInsets.top * scale,
      captureLayout.outerInsets.right * scale,
      captureLayout.outerInsets.bottom * scale,
    );
    final contentWidth = rawContentWidth * scale;
    final fullContentHeight = rawContentHeight * scale;
    final maxViewportHeight = (maxH - scaledInsets.vertical).clamp(1.0, maxH);
    final viewportContentHeight = fullContentHeight.clamp(
      1.0,
      maxViewportHeight,
    );
    final w = (contentWidth + scaledInsets.horizontal).clamp(1.0, maxW);
    final h = (viewportContentHeight + scaledInsets.vertical).clamp(1.0, maxH);

    final x = (screenSize.width - w) / 2;
    final y = ((availableHeight - h) / 2).clamp(0.0, availableHeight - h);
    return Rect.fromLTWH(x, y, w, h);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      child: ListenableBuilder(
        listenable: widget.annotationState,
        builder: (context, _) {
          final screenSize = MediaQuery.sizeOf(context);
          final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
          final isWindows = Platform.isWindows;
          final useNativeFloatingToolbar = Platform.isMacOS || isWindows;
          final nativeToolbarHeight =
              resolvedNativeToolbarFrame?.height ??
              kNativeToolbarFallbackHeight;
          final reservedToolbarHeight = useNativeFloatingToolbar
              ? 0.0
              : nativeToolbarHeight;
          final image = widget.stitchedImage;
          final imagePixelSize = Size(
            image.width.toDouble(),
            image.height.toDouble(),
          );
          final useCaptureStyleChrome =
              widget.showCaptureStyleChrome && !Platform.isWindows;
          final style = useCaptureStyleChrome
              ? widget.captureStyle.scaled(widget.captureScale)
              : const CaptureStyleSettings.defaults();
          final useFrameChrome =
              useCaptureStyleChrome && style.hasVisibleEffect;
          final captureLayout = computeCaptureStyleLayout(
            imagePixelSize,
            style,
          );
          final containerRect = isWindows
              ? Rect.fromLTWH(0, 0, screenSize.width, screenSize.height)
              : _imageContainerRect(
                  screenSize,
                  captureLayout: captureLayout,
                  reservedToolbarHeight: reservedToolbarHeight,
                );
          final snappedContainerRect = Platform.isWindows
              ? _snapRect(containerRect, devicePixelRatio)
              : containerRect;
          final displayScale =
              snappedContainerRect.width / captureLayout.outerSize.width;
          final localContentRectRaw = Rect.fromLTWH(
            captureLayout.outerInsets.left * displayScale,
            captureLayout.outerInsets.top * displayScale,
            captureLayout.contentSize.width * displayScale,
            snappedContainerRect.height -
                ((captureLayout.outerInsets.top +
                            captureLayout.outerInsets.bottom) *
                        displayScale)
                    .clamp(0.0, containerRect.height),
          );
          final localContentRect = useFrameChrome
              ? (Platform.isWindows
                    ? _snapRect(localContentRectRaw, devicePixelRatio)
                    : localContentRectRaw)
              : Rect.fromLTWH(
                  0,
                  0,
                  snappedContainerRect.width,
                  snappedContainerRect.height,
                );
          final fullContentHeight =
              captureLayout.contentSize.height * displayScale;
          final displayBorderRadius = useFrameChrome
              ? captureLayout.borderRadius * displayScale
              : 0.0;
          final toolbarAnchor = nativeToolbarAnchorPoint(
            viewportSize: screenSize,
            fallbackAnchor: computeFloatingToolbarAnchor(
              anchorRect: snappedContainerRect,
              screenSize: screenSize,
              toolbarHeight: nativeToolbarHeight,
            ),
          );

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (useNativeFloatingToolbar) {
              syncNativeToolbar(
                placement: isWindows
                    ? NativeToolbarPlacement.belowWindow
                    : NativeToolbarPlacement.belowAnchor,
                anchorRect: isWindows ? null : containerRect,
              );
            } else {
              hideNativeToolbar();
            }
          });

          return Stack(
            children: [
              if (isWindows)
                const Positioned.fill(child: TransparentClearLayer()),
              // Scrim background (full screen).
              if (!isWindows)
                const Positioned.fill(
                  child: ColoredBox(color: Color(0x44000000)),
                ),

              // Click outside image → discard (when no tool is active).
              // Always present to keep the Stack child count stable — toggling
              // children shifts widget positions, causing the ScrollController
              // to momentarily attach to two scroll views during rebuilds.
              if (!isWindows)
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: activeShapeType != null,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: widget.onDiscard,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),

              // Image container with border.
              Positioned(
                left: snappedContainerRect.left,
                top: snappedContainerRect.top,
                width: snappedContainerRect.width,
                height: snappedContainerRect.height,
                child: CaptureStyleFrame(
                  contentRect: localContentRect,
                  borderRadius: displayBorderRadius,
                  shadowEnabled: captureLayout.shadowEnabled,
                  child: Stack(
                    children: [
                      // Scrollable image.
                      Positioned.fill(
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          child: SizedBox(
                            width: localContentRect.width,
                            height: fullContentHeight,
                            child: RawImage(
                              image: image,
                              fit: BoxFit.fitWidth,
                              filterQuality: Platform.isWindows
                                  ? FilterQuality.none
                                  : FilterQuality.low,
                              isAntiAlias: false,
                            ),
                          ),
                        ),
                      ),

                      // Annotation overlay — outside the scroll view.
                      Positioned.fill(
                        child: IgnorePointer(
                          ignoring: activeShapeType == null,
                          child: ListenableBuilder(
                            listenable: Listenable.merge([
                              _scrollController,
                              widget.annotationState,
                            ]),
                            builder: (context, _) {
                              final scrollOffset = _scrollController.hasClients
                                  ? _scrollController.offset
                                  : 0.0;
                              final imageDisplayRect = Rect.fromLTWH(
                                0,
                                -scrollOffset,
                                localContentRect.width,
                                fullContentHeight,
                              );
                              final toolActive = activeShapeType != null;
                              return Listener(
                                behavior: toolActive
                                    ? HitTestBehavior.opaque
                                    : HitTestBehavior.translucent,
                                onPointerSignal: toolActive
                                    ? (event) {
                                        if (event is PointerScrollEvent &&
                                            _scrollController.hasClients) {
                                          final max = _scrollController
                                              .position
                                              .maxScrollExtent;
                                          _scrollController.jumpTo(
                                            (_scrollController.offset +
                                                    event.scrollDelta.dy)
                                                .clamp(0.0, max),
                                          );
                                        }
                                      }
                                    : null,
                                child: AnnotationOverlay(
                                  annotationState: widget.annotationState,
                                  imageDisplayRect: imageDisplayRect,
                                  imagePixelSize: imagePixelSize,
                                  enabled: toolActive,
                                  sourceImage: image,
                                ),
                              );
                            },
                          ),
                        ),
                      ),

                      // QR code overlay — rendered above image, disabled while drawing.
                      Positioned.fill(
                        child: ListenableBuilder(
                          listenable: _scrollController,
                          builder: (context, _) {
                            final scrollOffset = _scrollController.hasClients
                                ? _scrollController.offset
                                : 0.0;
                            final imageDisplayRect = Rect.fromLTWH(
                              0,
                              -scrollOffset,
                              localContentRect.width,
                              fullContentHeight,
                            );
                            return QrCodeOverlay(
                              image: image,
                              imageDisplayRect: imageDisplayRect,
                              imagePixelSize: imagePixelSize,
                              windowService: widget.windowService,
                              onCopy: widget.onCopyText,
                              enabled:
                                  activeShapeType == null &&
                                  !widget.annotationState.editingText,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Toolbar — positioned below/above/inside the image container.
              if (useNativeFloatingToolbar)
                Positioned(
                  top: toolbarAnchor.dy,
                  left: toolbarAnchor.dx,
                  child: CompositedTransformTarget(
                    link: _popoverAnchorLink,
                    child: const SizedBox(width: 1, height: 1),
                  ),
                )
              else
                Positioned(
                  top: toolbarAnchor.dy,
                  left: toolbarAnchor.dx,
                  child: FractionalTranslation(
                    translation: const Offset(-0.5, 0),
                    child: FloatingAnnotationToolbar(
                      anchorLink: _popoverAnchorLink,
                      activeTool: activeShapeType,
                      onToolPressed: handleToolTap,
                      onActionPressed: handleNativeToolbarAction,
                      showPin: false,
                      showHistoryControls: true,
                      canUndo: widget.annotationState.canUndo,
                      canRedo: widget.annotationState.canRedo,
                      showOcr: Platform.isMacOS,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
