# aSnap

macOS + Windows menu bar screenshot tool built with Flutter. Currently focused on macOS; Windows support planned.

## Build & Run

```bash
# Dev cycle: format → analyze → build debug
./scripts/dev.sh

# Full clean rebuild
./scripts/clean.sh

# Individual commands
dart format lib/
flutter analyze
flutter test
flutter build macos --debug
flutter build macos --release
```

The built app is at `build/macos/Build/Products/{Debug,Release}/a_snap.app`.

## Architecture

### File Layout

```
lib/
├── main.dart                  # Entry point, service init, capture flow orchestration
├── app.dart                   # MaterialApp, state-driven routing
├── state/
│   └── app_state.dart         # AppState (ChangeNotifier), CaptureStatus enum
├── services/
│   ├── window_service.dart    # Window lifecycle, overlay control, platform channel bridge
│   ├── tray_service.dart      # System tray menu (tray_manager)
│   ├── hotkey_service.dart    # Global hotkeys (⌘⇧1 fullscreen, ⌘⇧2 region)
│   ├── capture_service.dart   # Screenshot capture, image cropping, permissions
│   ├── clipboard_service.dart # PNG → system clipboard (super_clipboard)
│   └── file_service.dart      # Save dialog + file write
├── screens/
│   ├── preview_screen.dart          # Floating preview with toolbar
│   └── region_selection_screen.dart # Fullscreen overlay for region/element selection
├── widgets/
│   ├── preview_toolbar.dart   # Copy / Save / Discard buttons
│   └── magnifier_loupe.dart   # 8x zoom loupe with crosshair + coordinates
└── utils/
    ├── constants.dart         # App name, tray icon path, hotkey definitions
    └── file_naming.dart       # Screenshot filename: asnap_YYYY-MM-DD_HHMMSS.png
```

### macOS Native Layer

```
macos/Runner/
├── MainFlutterWindow.swift    # Overlay mode, AX hit-testing, display monitoring, platform channel
├── AppDelegate.swift          # NSApp.setActivationPolicy(.accessory) — no Dock icon
├── Info.plist                 # Screen recording + accessibility permission strings
├── DebugProfile.entitlements  # Sandbox disabled, JIT allowed
└── Release.entitlements       # Sandbox disabled
```

### Service Pattern

Services are singletons initialized sequentially in `main.dart`:
`AppState → CaptureService → ClipboardService → FileService → HotkeyService → TrayService → WindowService`

Each service has a single responsibility, uses async methods, and communicates back to Dart via callbacks.

### State Machine

```
CaptureStatus: idle → capturing → selecting → captured → idle
```

- `idle` → `capturing`: hotkey or tray menu triggers capture
- `capturing` → `selecting`: region overlay shown (fullscreen skips this)
- `selecting` → `captured`: region selected, preview shown
- `captured` → `idle`: user copies, saves, or discards

### Platform Channel

Channel: `com.asnap/window` — key methods:
- `captureScreen` — native screenshot (CGWindowListCreateImage)
- `enterOverlayMode` / `exitOverlayMode` — borderless fullscreen overlay
- `suspendOverlay` / `revealOverlay` — display switching transitions
- `hitTestElement` — real-time AX hit-test for element selection
- `getWindowList` / `startRectPolling` / `stopRectPolling` — window/element rects
- `startEscMonitor` / `stopEscMonitor` — Escape key detection
- `resizeToRect` / `repositionOverlay` — preview positioning
- `activateApp` — bring app to front

## Code Conventions

- **Naming**: `snake_case` files, `PascalCase` classes, `camelCase` methods/variables, `kPascalCase` constants
- **State**: `ChangeNotifier` + `ListenableBuilder` (no external state management packages)
- **Async**: `unawaited()` for fire-and-forget, proper `await` for sequential flow
- **Null safety**: throughout — `Uint8List?`, `Offset?`, etc.
- **Linting**: `flutter_lints` (see `analysis_options.yaml`)
- **Resource cleanup**: always `dispose()` decoded images and codecs after use

## Critical: macOS Window Lifecycle

These are hard-won lessons. Violating them breaks the app silently.

1. **Never set `visibleAtLaunch="NO"` in MainMenu.xib** — prevents Flutter engine from getting a Metal rendering surface. Dart isolate never starts. Symptom: zero output, `Invalid engine handle`.
2. **Never call `orderOut`/`setIsVisible(false)` before `RegisterGeneratedPlugins`** in MainFlutterWindow.swift — plugins need an active engine.
3. **Use `window_manager`'s `hiddenWindowAtLaunch()` in an `order()` override** to hide the window at launch.
4. **Always use `display: true` in `setFrame()`**.

## Testing

Run tests with `flutter test`.

Current coverage is still minimal (primarily filename generation, widget behavior, and AppState). When adding features or fixing bugs:
- Write unit tests for business logic (services, utilities)
- Write widget tests for UI components
- Place tests in `test/` mirroring the `lib/` structure (e.g., `test/services/capture_service_test.dart`)

## Widget Previews

Use the VSCode Flutter Widget Preview extension to preview widgets during development.

Create preview files alongside widget files with a `_preview.dart` suffix:
- `lib/widgets/magnifier_loupe.dart` → `lib/widgets/magnifier_loupe_preview.dart`

Preview files should expose a top-level `@Preview`-annotated function that returns the widget with sample data, wrapped in any necessary scaffolding (e.g., `MaterialApp` + `Scaffold`). No `BuildContext` parameter is needed.

## Refactoring

Always consider best practices when touching code. If you encounter code that could be cleaner, safer, or better structured while working on a feature or fix — refactor it. Don't leave broken windows.

## Git Workflow

- Feature branches: `v0.1.x` naming for releases
- All changes merged via pull requests to `main`
- Commit messages: short imperative summary (e.g., "Add magnifier loupe to region selection")
