#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  struct ToolbarButtonState {
    std::string action;
    std::wstring label;
    uint32_t icon_codepoint = 0;
    RECT rect{};
    bool enabled = true;
    bool selected = false;
    bool destructive = false;
    bool separator = false;
  };

  void InitializeMethodChannel();
  void HandleWindowMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void EnsureSavedWindowState();
  void RestoreWindowState();
  void DismissAppWindow();
  void PreparePreviewWindow(bool use_native_shadow);
  void ConfigureInkOverlayWindow(const RECT& bounds);
  void ConfigureOverlayWindow(const RECT& bounds, bool click_through,
                              BYTE alpha);
  void LayoutHostedFlutterView();
  void SyncFlutterWindowMetrics();
  void ShowOrUpdateToolbarPanel(const flutter::EncodableMap& args);
  void FlushPendingToolbarPanel();
  void RefreshToolbarPanelIfNeeded();
  void HideToolbarPanel(bool clear_pending = true, bool clear_last = true);
  void ResetToolbarPanelState();
  void HandleToolbarActionClick(const std::string& action);
  void EmitToolbarFrameChanged(const RECT& physical_rect, int request_id,
                               int64_t session_id);
  bool EnsureMaterialIconsFont();
  int HitTestToolbarButton(POINT point) const;
  void UpdateToolbarHoverState(POINT point);
  static LRESULT CALLBACK ToolbarWindowProc(HWND hwnd, UINT message,
                                            WPARAM wparam,
                                            LPARAM lparam) noexcept;
  void SetWindowExcludedFromCapture(bool enabled);
  void ShowScrollStopButton(const RECT& bounds);
  void HideScrollStopButton();
  void HandleScrollStopButtonClick();
  static LRESULT CALLBACK ScrollStopWindowProc(HWND hwnd, UINT message,
                                               WPARAM wparam,
                                               LPARAM lparam) noexcept;
  void SetTransparentBackground(bool enabled);
  void SetWindowOpacity(BYTE alpha);
  void DisableLayeredWindowIfTransparent();
  void SetOverlayDismissOnNextClick(bool enabled);
  void StopOverlayDismissOnNextClickMonitor();
  void HandleOverlayPassthroughClick();
  static LRESULT CALLBACK OverlayDismissMouseProc(int nCode, WPARAM wparam,
                                                  LPARAM lparam) noexcept;
  void SetMousePassthrough(bool enabled);
  void SetHostedFlutterViewVisible(bool visible);
  void ActivateAppWindow();
  void StopEscMonitor();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_channel_;

  bool saved_window_state_ = false;
  LONG_PTR saved_window_style_ = 0;
  LONG_PTR saved_window_ex_style_ = 0;
  RECT saved_window_rect_{};
  bool esc_hotkey_registered_ = false;
  bool transparent_background_enabled_ = false;
  bool mouse_passthrough_enabled_ = false;
  HHOOK overlay_dismiss_click_hook_ = nullptr;
  bool overlay_dismiss_on_next_click_ = false;
  HWND toolbar_window_ = nullptr;
  std::vector<ToolbarButtonState> toolbar_buttons_;
  std::optional<flutter::EncodableMap> pending_toolbar_args_;
  std::optional<flutter::EncodableMap> last_toolbar_args_;
  int hovered_toolbar_button_index_ = -1;
  int pressed_toolbar_button_index_ = -1;
  int toolbar_panel_corner_radius_ = 14;
  int toolbar_button_corner_radius_ = 10;
  int toolbar_icon_font_size_ = 18;
  int latest_toolbar_request_id_ = 0;
  int64_t latest_toolbar_session_id_ = 0;
  bool material_icons_font_loaded_ = false;
  std::wstring material_icons_font_path_;
  HWND scroll_stop_window_ = nullptr;
  bool scroll_stop_hovered_ = false;
  bool custom_frame_active_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
