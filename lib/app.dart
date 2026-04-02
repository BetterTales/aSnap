import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/ink_overlay_screen.dart';
import 'screens/preview_screen.dart';
import 'screens/region_selection_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/scroll_result_screen.dart';
import 'services/window_service.dart';
import 'models/shortcut_bindings.dart';
import 'state/annotation_state.dart';
import 'state/app_state.dart';
import 'state/ink_state.dart';
import 'state/laser_state.dart';
import 'state/settings_state.dart';
import 'widgets/scroll_progress_badge.dart';

class ASnapApp extends StatelessWidget {
  final AppState appState;
  final AnnotationState annotationState;
  final InkState inkState;
  final LaserState laserState;
  final SettingsState settingsState;
  final WindowService windowService;
  final GlobalKey<NavigatorState> navigatorKey;
  final VoidCallback onCopy;
  final VoidCallback onSave;
  final VoidCallback? onPin;
  final VoidCallback onDiscard;
  final VoidCallback onOcr;
  final ValueChanged<String> onCopyText;
  final void Function(Rect selectionRect) onRegionSelected;
  final void Function(Rect selectionRect) onRegionOcr;

  /// Snipaste-style overlay actions for region capture.
  final void Function(Rect selectionRect)? onRegionCopy;
  final void Function(Rect selectionRect)? onRegionSave;
  final void Function(Rect selectionRect)? onRegionPin;

  final void Function(Rect selectionRect)? onScrollRegionSelected;
  final VoidCallback onRegionCancel;
  final Future<Rect?> Function(Offset localPoint)? onHitTest;
  final VoidCallback? onScrollCaptureDone;
  final void Function(Rect cgRect)? onScrollStopButtonRect;
  final Future<void> Function() onCloseSettings;
  final Future<void> Function() onSuspendHotkeys;
  final Future<void> Function() onResumeHotkeys;
  final VoidCallback onInkKeyDown;
  final VoidCallback onInkKeyUp;
  final VoidCallback onLaserKeyDown;
  final VoidCallback onLaserKeyUp;
  final Future<void> Function() onInkExit;
  const ASnapApp({
    super.key,
    required this.appState,
    required this.annotationState,
    required this.inkState,
    required this.laserState,
    required this.settingsState,
    required this.windowService,
    required this.navigatorKey,
    required this.onCopy,
    required this.onSave,
    this.onPin,
    required this.onDiscard,
    required this.onOcr,
    required this.onCopyText,
    required this.onRegionSelected,
    required this.onRegionOcr,
    this.onRegionCopy,
    this.onRegionSave,
    this.onRegionPin,
    this.onScrollRegionSelected,
    required this.onRegionCancel,
    this.onHitTest,
    this.onScrollCaptureDone,
    this.onScrollStopButtonRect,
    required this.onCloseSettings,
    required this.onSuspendHotkeys,
    required this.onResumeHotkeys,
    required this.onInkKeyDown,
    required this.onInkKeyUp,
    required this.onLaserKeyDown,
    required this.onLaserKeyUp,
    required this.onInkExit,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'aSnap',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData.light(useMaterial3: true).copyWith(
        canvasColor: Colors.transparent,
        scaffoldBackgroundColor: Colors.transparent,
      ),
      darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
        canvasColor: Colors.transparent,
        scaffoldBackgroundColor: Colors.transparent,
      ),
      themeMode: ThemeMode.system,
      home: ListenableBuilder(
        listenable: Listenable.merge([appState, settingsState]),
        builder: (context, _) {
          switch (appState.workflow) {
            case RegionSelectionWorkflow(
              :final decodedImage,
              :final windowRects,
              selectionMode: SelectionMode.region,
            ):
              return RegionSelectionScreen(
                decodedImage: decodedImage,
                windowRects: windowRects,
                onCancel: onRegionCancel,
                windowService: windowService,
                onCopy: onRegionCopy,
                onSave: onRegionSave,
                onPin: onRegionPin,
                onOcr: onRegionOcr,
                onCopyText: onCopyText,
                onHitTest: onHitTest,
                annotationState: annotationState,
              );
            case RegionSelectionWorkflow(
              :final decodedImage,
              :final windowRects,
              selectionMode: SelectionMode.scroll,
            ):
              return RegionSelectionScreen(
                decodedImage: decodedImage,
                windowRects: windowRects,
                onCancel: onRegionCancel,
                windowService: windowService,
                onRegionSelected: onScrollRegionSelected ?? onRegionSelected,
                onHitTest: onHitTest,
                isQuickSelection: true,
              );
            case RegionSelectionWorkflow(
              :final decodedImage,
              :final windowRects,
              selectionMode: SelectionMode.ocr,
            ):
              return RegionSelectionScreen(
                decodedImage: decodedImage,
                windowRects: windowRects,
                onCancel: onRegionCancel,
                windowService: windowService,
                onRegionSelected: onRegionOcr,
                onHitTest: onHitTest,
                isQuickSelection: true,
              );
            case ScrollCapturingWorkflow(
              :final frameCount,
              :final previewImage,
              :final captureRegion,
              :final screenOrigin,
              :final screenSize,
            ):
              return ScrollCapturePreview(
                frameCount: frameCount,
                previewImage: previewImage,
                captureRegion: captureRegion,
                screenOrigin: screenOrigin,
                screenSize: screenSize,
                onDone: onScrollCaptureDone,
                onStopButtonRect: onScrollStopButtonRect,
              );
            case ScrollResultWorkflow(:final image):
              return ScrollResultScreen(
                stitchedImage: image,
                annotationState: annotationState,
                windowService: windowService,
                onCopy: onCopy,
                onSave: onSave,
                onDiscard: onDiscard,
                onOcr: onOcr,
                onCopyText: onCopyText,
                captureStyle: settingsState.captureStyle,
                captureScale: appState.captureScale,
                showCaptureStyleChrome: appState.applyCurrentCaptureStyle,
              );
            case SettingsWorkflow():
              return SettingsScreen(
                settingsState: settingsState,
                onClose: onCloseSettings,
                onSuspendHotkeys: onSuspendHotkeys,
                onResumeHotkeys: onResumeHotkeys,
              );
            case InkOverlayWorkflow(:final tool, :final drawingEnabled):
              return InkOverlayScreen(
                inkState: inkState,
                laserState: laserState,
                drawingEnabled: drawingEnabled,
                tool: tool,
                inkHotKey: settingsState.shortcuts.forAction(
                  ShortcutAction.ink,
                ),
                laserHotKey: settingsState.shortcuts.forAction(
                  ShortcutAction.laser,
                ),
                onInkKeyDown: onInkKeyDown,
                onInkKeyUp: onInkKeyUp,
                onLaserKeyDown: onLaserKeyDown,
                onLaserKeyUp: onLaserKeyUp,
                strokeColor: settingsState.inkColor,
                strokeWidth: settingsState.inkStrokeWidth,
                smoothingTolerance: settingsState.inkSmoothingTolerance,
                autoFadeSeconds: settingsState.inkAutoFadeSeconds,
                eraserSize: settingsState.inkEraserSize,
                laserColor: settingsState.laserColor,
                laserSize: settingsState.laserSize,
                laserFadeSeconds: settingsState.laserFadeSeconds,
                onEraserSizeChanged: (size) {
                  unawaited(settingsState.setInkEraserSize(size));
                },
                onExitRequested: onInkExit,
              );
            default:
              break;
          }
          return PreviewScreen(
            appState: appState,
            annotationState: annotationState,
            windowService: windowService,
            onCopy: onCopy,
            onSave: onSave,
            onPin: onPin,
            onDiscard: onDiscard,
            onOcr: onOcr,
            onCopyText: onCopyText,
            captureStyle: settingsState.captureStyle,
            captureScale: appState.captureScale,
            showCaptureStyleChrome: appState.applyCurrentCaptureStyle,
          );
        },
      ),
    );
  }
}
