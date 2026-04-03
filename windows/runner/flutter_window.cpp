#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>
#include <dwmapi.h>
#include <windows.h>
#include <windowsx.h>

#include <algorithm>
#include <cstdint>
#include <cmath>
#include <cstdio>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "flutter/generated_plugin_registrant.h"

namespace {

#ifndef DWMWA_CLOAKED
#define DWMWA_CLOAKED 14
#endif
#ifndef DWMWA_CLOAK
#define DWMWA_CLOAK 13
#endif
#ifndef DWMWA_WINDOW_CORNER_PREFERENCE
#define DWMWA_WINDOW_CORNER_PREFERENCE 33
#endif
#ifndef DWMWA_BORDER_COLOR
#define DWMWA_BORDER_COLOR 34
#endif

#ifndef WDA_EXCLUDEFROMCAPTURE
#define WDA_EXCLUDEFROMCAPTURE 0x00000011
#endif

constexpr int kEscHotkeyId = 0xA51A;
constexpr int kScrollStopButtonId = 0xA51B;
constexpr UINT kOverlayPassthroughClickMessage = WM_APP + 101;
constexpr double kMonitorMatchEpsilon = 2.0;
constexpr int kWindowCompositionAccentPolicy = 19;
constexpr wchar_t kToolbarWindowClassName[] = L"ASnapToolbarWindow";
constexpr wchar_t kScrollStopWindowClassName[] = L"ASnapScrollStopWindow";
constexpr int kToolbarCornerRadius = 14;
constexpr int kScrollStopCornerRadius = 12;
constexpr COLORREF kDwmColorDefault = 0xFFFFFFFF;
constexpr COLORREF kDwmColorNone = 0xFFFFFFFE;

enum WindowCornerPreference {
  kWindowCornerPreferenceDefault = 0,
  kWindowCornerPreferenceDoNotRound = 1,
};

enum AccentState {
  kAccentDisabled = 0,
  kAccentEnableTransparentGradient = 2,
};

struct AccentPolicy {
  int accent_state = kAccentDisabled;
  int accent_flags = 0;
  int gradient_color = 0;
  int animation_id = 0;
};

struct WindowCompositionAttributeData {
  int attribute = 0;
  PVOID data = nullptr;
  ULONG data_size = 0;
};

using SetWindowCompositionAttributeFn =
    BOOL(WINAPI*)(HWND, WindowCompositionAttributeData*);

struct MonitorDetails {
  HMONITOR handle = nullptr;
  RECT physical_bounds{};
  RECT logical_bounds{};
  double scale = 1.0;
};

struct CaptureResult {
  std::vector<uint8_t> bytes;
  int width = 0;
  int height = 0;
  int bytes_per_row = 0;
};

FlutterWindow* g_overlay_dismiss_target = nullptr;

const flutter::EncodableMap* AsEncodableMap(
    const flutter::EncodableValue* value) {
  if (value == nullptr) {
    return nullptr;
  }
  return std::get_if<flutter::EncodableMap>(value);
}

std::optional<double> GetDouble(const flutter::EncodableMap& map,
                                const char* key) {
  const auto iterator = map.find(flutter::EncodableValue(key));
  if (iterator == map.end()) {
    return std::nullopt;
  }

  if (const auto* number = std::get_if<double>(&iterator->second)) {
    return *number;
  }
  if (const auto* number = std::get_if<int>(&iterator->second)) {
    return static_cast<double>(*number);
  }
  if (const auto* number = std::get_if<int64_t>(&iterator->second)) {
    return static_cast<double>(*number);
  }
  return std::nullopt;
}

bool GetBool(const flutter::EncodableMap& map, const char* key,
             bool default_value = false) {
  const auto iterator = map.find(flutter::EncodableValue(key));
  if (iterator == map.end()) {
    return default_value;
  }

  if (const auto* value = std::get_if<bool>(&iterator->second)) {
    return *value;
  }
  return default_value;
}

std::optional<int> GetInt(const flutter::EncodableMap& map, const char* key) {
  const auto iterator = map.find(flutter::EncodableValue(key));
  if (iterator == map.end()) {
    return std::nullopt;
  }

  if (const auto* number = std::get_if<int>(&iterator->second)) {
    return *number;
  }
  if (const auto* number = std::get_if<int64_t>(&iterator->second)) {
    return static_cast<int>(*number);
  }
  if (const auto* number = std::get_if<double>(&iterator->second)) {
    return static_cast<int>(*number);
  }
  return std::nullopt;
}

std::optional<int64_t> GetInt64(const flutter::EncodableMap& map,
                                const char* key) {
  const auto iterator = map.find(flutter::EncodableValue(key));
  if (iterator == map.end()) {
    return std::nullopt;
  }

  if (const auto* number = std::get_if<int64_t>(&iterator->second)) {
    return *number;
  }
  if (const auto* number = std::get_if<int>(&iterator->second)) {
    return static_cast<int64_t>(*number);
  }
  if (const auto* number = std::get_if<double>(&iterator->second)) {
    return static_cast<int64_t>(*number);
  }
  return std::nullopt;
}

std::optional<std::string> GetString(const flutter::EncodableMap& map,
                                     const char* key) {
  const auto iterator = map.find(flutter::EncodableValue(key));
  if (iterator == map.end()) {
    return std::nullopt;
  }

  if (const auto* value = std::get_if<std::string>(&iterator->second)) {
    return *value;
  }
  return std::nullopt;
}

const flutter::EncodableMap* GetMapValue(const flutter::EncodableMap& map,
                                         const char* key) {
  const auto iterator = map.find(flutter::EncodableValue(key));
  if (iterator == map.end()) {
    return nullptr;
  }
  return std::get_if<flutter::EncodableMap>(&iterator->second);
}

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }

  const int length = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1,
                                         nullptr, 0);
  if (length <= 0) {
    return std::wstring(value.begin(), value.end());
  }

  std::wstring wide(static_cast<size_t>(length), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, wide.data(), length);
  wide.pop_back();
  return wide;
}

std::wstring CodepointToWide(uint32_t codepoint) {
  if (codepoint <= 0xFFFF) {
    return std::wstring(1, static_cast<wchar_t>(codepoint));
  }

  codepoint -= 0x10000;
  const wchar_t high =
      static_cast<wchar_t>(0xD800 + ((codepoint >> 10) & 0x3FF));
  const wchar_t low = static_cast<wchar_t>(0xDC00 + (codepoint & 0x3FF));
  return std::wstring({high, low});
}

int RoundToInt(double value) {
  return static_cast<int>(std::lround(value));
}

double MonitorScale(HMONITOR monitor) {
  const UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  return dpi == 0 ? 1.0 : static_cast<double>(dpi) / 96.0;
}

RECT LogicalRectFromPhysical(const RECT& rect, double scale) {
  return RECT{
      RoundToInt(static_cast<double>(rect.left) / scale),
      RoundToInt(static_cast<double>(rect.top) / scale),
      RoundToInt(static_cast<double>(rect.right) / scale),
      RoundToInt(static_cast<double>(rect.bottom) / scale),
  };
}

std::vector<MonitorDetails> GetMonitorDetailsList() {
  struct MonitorContext {
    std::vector<MonitorDetails> monitors;
  } context;

  EnumDisplayMonitors(
      nullptr, nullptr,
      [](HMONITOR monitor, HDC, LPRECT, LPARAM data) -> BOOL {
        auto* context = reinterpret_cast<MonitorContext*>(data);
        MONITORINFO info{};
        info.cbSize = sizeof(MONITORINFO);
        if (!GetMonitorInfo(monitor, &info)) {
          return TRUE;
        }

        const double scale = MonitorScale(monitor);
        context->monitors.push_back(MonitorDetails{
            monitor,
            info.rcMonitor,
            LogicalRectFromPhysical(info.rcMonitor, scale),
            scale,
        });
        return TRUE;
      },
      reinterpret_cast<LPARAM>(&context));

  return context.monitors;
}

bool RectContainsPoint(const RECT& rect, double x, double y) {
  return x >= rect.left && x < rect.right && y >= rect.top && y < rect.bottom;
}

double DistanceSquaredToRect(const RECT& rect, double x, double y) {
  const double clamped_x = std::clamp(
      x, static_cast<double>(rect.left), static_cast<double>(rect.right));
  const double clamped_y = std::clamp(
      y, static_cast<double>(rect.top), static_cast<double>(rect.bottom));
  const double dx = x - clamped_x;
  const double dy = y - clamped_y;
  return dx * dx + dy * dy;
}

std::optional<MonitorDetails> FindMonitorByHandle(HMONITOR handle) {
  const auto monitors = GetMonitorDetailsList();
  for (const auto& monitor : monitors) {
    if (monitor.handle == handle) {
      return monitor;
    }
  }
  return std::nullopt;
}

std::optional<MonitorDetails> FindMonitorByLogicalOrigin(double x, double y) {
  const auto monitors = GetMonitorDetailsList();
  for (const auto& monitor : monitors) {
    if (std::abs(static_cast<double>(monitor.logical_bounds.left) - x) <
            kMonitorMatchEpsilon &&
        std::abs(static_cast<double>(monitor.logical_bounds.top) - y) <
            kMonitorMatchEpsilon) {
      return monitor;
    }
  }
  return std::nullopt;
}

std::optional<MonitorDetails> FindMonitorForLogicalPoint(double x, double y) {
  const auto monitors = GetMonitorDetailsList();
  if (monitors.empty()) {
    return std::nullopt;
  }

  for (const auto& monitor : monitors) {
    if (RectContainsPoint(monitor.logical_bounds, x, y)) {
      return monitor;
    }
  }

  const auto* nearest_monitor = &monitors.front();
  double nearest_distance =
      DistanceSquaredToRect(nearest_monitor->logical_bounds, x, y);
  for (const auto& monitor : monitors) {
    const double distance = DistanceSquaredToRect(monitor.logical_bounds, x, y);
    if (distance < nearest_distance) {
      nearest_distance = distance;
      nearest_monitor = &monitor;
    }
  }
  return *nearest_monitor;
}

std::optional<MonitorDetails> FindMonitorForPhysicalPoint(const POINT& point) {
  return FindMonitorByHandle(MonitorFromPoint(point, MONITOR_DEFAULTTONEAREST));
}

std::optional<POINT> LogicalToPhysicalPoint(double x, double y) {
  const auto monitor = FindMonitorForLogicalPoint(x, y);
  if (!monitor.has_value()) {
    return std::nullopt;
  }

  return POINT{
      RoundToInt(x * monitor->scale),
      RoundToInt(y * monitor->scale),
  };
}

std::optional<RECT> LogicalToPhysicalRect(double x, double y, double width,
                                          double height) {
  if (width <= 0 || height <= 0) {
    return std::nullopt;
  }

  const auto monitor =
      FindMonitorForLogicalPoint(x + width / 2.0, y + height / 2.0);
  if (!monitor.has_value()) {
    return std::nullopt;
  }

  return RECT{
      RoundToInt(x * monitor->scale),
      RoundToInt(y * monitor->scale),
      RoundToInt((x + width) * monitor->scale),
      RoundToInt((y + height) * monitor->scale),
  };
}

flutter::EncodableMap RectToEncodableMap(const RECT& physical_rect) {
  const HMONITOR monitor =
      MonitorFromRect(&physical_rect, MONITOR_DEFAULTTONEAREST);
  const auto details = FindMonitorByHandle(monitor);
  const double scale = details.has_value() ? details->scale : 1.0;
  const RECT logical_rect = LogicalRectFromPhysical(physical_rect, scale);

  flutter::EncodableMap map;
  map[flutter::EncodableValue("x")] =
      flutter::EncodableValue(static_cast<double>(logical_rect.left));
  map[flutter::EncodableValue("y")] =
      flutter::EncodableValue(static_cast<double>(logical_rect.top));
  map[flutter::EncodableValue("width")] = flutter::EncodableValue(
      static_cast<double>(logical_rect.right - logical_rect.left));
  map[flutter::EncodableValue("height")] = flutter::EncodableValue(
      static_cast<double>(logical_rect.bottom - logical_rect.top));
  return map;
}

std::optional<CaptureResult> CaptureScreenRect(const RECT& rect,
                                              bool include_layered_windows =
                                                  true) {
  const int width = rect.right - rect.left;
  const int height = rect.bottom - rect.top;
  if (width <= 0 || height <= 0) {
    return std::nullopt;
  }

  HDC screen_dc = GetDC(nullptr);
  if (screen_dc == nullptr) {
    return std::nullopt;
  }

  HDC memory_dc = CreateCompatibleDC(screen_dc);
  if (memory_dc == nullptr) {
    ReleaseDC(nullptr, screen_dc);
    return std::nullopt;
  }

  BITMAPINFO bitmap_info{};
  bitmap_info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bitmap_info.bmiHeader.biWidth = width;
  bitmap_info.bmiHeader.biHeight = -height;
  bitmap_info.bmiHeader.biPlanes = 1;
  bitmap_info.bmiHeader.biBitCount = 32;
  bitmap_info.bmiHeader.biCompression = BI_RGB;

  void* raw_pixels = nullptr;
  HBITMAP bitmap =
      CreateDIBSection(screen_dc, &bitmap_info, DIB_RGB_COLORS, &raw_pixels,
                       nullptr, 0);
  if (bitmap == nullptr || raw_pixels == nullptr) {
    DeleteDC(memory_dc);
    ReleaseDC(nullptr, screen_dc);
    return std::nullopt;
  }

  HGDIOBJ previous_bitmap = SelectObject(memory_dc, bitmap);
  DWORD raster_operation = SRCCOPY;
  if (include_layered_windows) {
    raster_operation |= CAPTUREBLT;
  }
  const BOOL copied =
      BitBlt(memory_dc, 0, 0, width, height, screen_dc, rect.left, rect.top,
             raster_operation);
  GdiFlush();

  CaptureResult result;
  if (copied != FALSE) {
    const size_t byte_count = static_cast<size_t>(width) * height * 4;
    result.bytes.assign(static_cast<uint8_t*>(raw_pixels),
                        static_cast<uint8_t*>(raw_pixels) + byte_count);
    for (size_t index = 3; index < result.bytes.size(); index += 4) {
      result.bytes[index] = 255;
    }
    result.width = width;
    result.height = height;
    result.bytes_per_row = width * 4;
  }

  SelectObject(memory_dc, previous_bitmap);
  DeleteObject(bitmap);
  DeleteDC(memory_dc);
  ReleaseDC(nullptr, screen_dc);

  if (copied == FALSE) {
    return std::nullopt;
  }
  return result;
}

flutter::EncodableMap CapturePayload(const CaptureResult& capture,
                                     double logical_width,
                                     double logical_height,
                                     double logical_x,
                                     double logical_y) {
  flutter::EncodableMap payload;
  payload[flutter::EncodableValue("bytes")] =
      flutter::EncodableValue(capture.bytes);
  payload[flutter::EncodableValue("pixelWidth")] =
      flutter::EncodableValue(capture.width);
  payload[flutter::EncodableValue("pixelHeight")] =
      flutter::EncodableValue(capture.height);
  payload[flutter::EncodableValue("bytesPerRow")] =
      flutter::EncodableValue(capture.bytes_per_row);
  payload[flutter::EncodableValue("screenWidth")] =
      flutter::EncodableValue(logical_width);
  payload[flutter::EncodableValue("screenHeight")] =
      flutter::EncodableValue(logical_height);
  payload[flutter::EncodableValue("screenOriginX")] =
      flutter::EncodableValue(logical_x);
  payload[flutter::EncodableValue("screenOriginY")] =
      flutter::EncodableValue(logical_y);
  return payload;
}

bool IsWindowCloaked(HWND window) {
  DWORD cloaked = 0;
  return SUCCEEDED(DwmGetWindowAttribute(window, DWMWA_CLOAKED, &cloaked,
                                         sizeof(cloaked))) &&
         cloaked != 0;
}

bool ShouldIncludeWindow(HWND window, HWND owner) {
  if (window == nullptr || window == owner) {
    return false;
  }
  if (!IsWindowVisible(window) || IsIconic(window) || IsWindowCloaked(window)) {
    return false;
  }

  const LONG_PTR ex_style = GetWindowLongPtr(window, GWL_EXSTYLE);
  if ((ex_style & WS_EX_TOOLWINDOW) != 0) {
    return false;
  }

  RECT rect{};
  if (!GetWindowRect(window, &rect)) {
    return false;
  }
  return rect.right > rect.left && rect.bottom > rect.top;
}

struct WindowListContext {
  HWND owner = nullptr;
  flutter::EncodableList* windows = nullptr;
};

BOOL CALLBACK EnumWindowsProc(HWND window, LPARAM data) {
  auto* context = reinterpret_cast<WindowListContext*>(data);
  if (context == nullptr || context->windows == nullptr) {
    return FALSE;
  }

  if (ShouldIncludeWindow(window, context->owner)) {
    RECT rect{};
    if (GetWindowRect(window, &rect)) {
      context->windows->emplace_back(RectToEncodableMap(rect));
    }
  }
  return TRUE;
}

std::optional<RECT> GetWindowRectForPoint(const POINT& point, HWND owner) {
  HWND window = WindowFromPoint(point);
  if (window == nullptr) {
    return std::nullopt;
  }

  HWND root = GetAncestor(window, GA_ROOT);
  if (root != nullptr) {
    window = root;
  }

  if (!ShouldIncludeWindow(window, owner)) {
    return std::nullopt;
  }

  RECT rect{};
  if (!GetWindowRect(window, &rect)) {
    return std::nullopt;
  }
  return rect;
}

void ApplyTransparentAccent(HWND window, bool enabled) {
  if (window == nullptr) {
    return;
  }

  const HMODULE user32 = LoadLibraryW(L"user32.dll");
  if (user32 == nullptr) {
    return;
  }

  const auto set_window_composition_attribute =
      reinterpret_cast<SetWindowCompositionAttributeFn>(
          GetProcAddress(user32, "SetWindowCompositionAttribute"));
  if (set_window_composition_attribute != nullptr) {
    AccentPolicy policy;
    if (enabled) {
      // This matches window_manager's Windows transparent background mode and
      // lets Flutter's transparent widgets reveal the real desktop.
      policy.accent_state = kAccentEnableTransparentGradient;
      policy.accent_flags = 2;
    }
    WindowCompositionAttributeData data{
        kWindowCompositionAccentPolicy,
        &policy,
        sizeof(policy),
    };
    set_window_composition_attribute(window, &data);
  }

  FreeLibrary(user32);
}

void ApplyRoundedWindowRegion(HWND window, int width, int height,
                              int radius) {
  if (window == nullptr || width <= 0 || height <= 0) {
    return;
  }

  HRGN region =
      CreateRoundRectRgn(0, 0, width + 1, height + 1, radius * 2, radius * 2);
  if (region == nullptr) {
    return;
  }

  SetWindowRgn(window, region, TRUE);
}

void SetWindowCloak(HWND window, bool cloaked) {
  if (window == nullptr) {
    return;
  }
  const BOOL cloak = cloaked ? TRUE : FALSE;
  DwmSetWindowAttribute(window, DWMWA_CLOAK, &cloak, sizeof(cloak));
}

void ExtendFrameIntoClientArea(HWND window, bool enabled) {
  if (window == nullptr) {
    return;
  }

  const MARGINS margins =
      enabled ? MARGINS{-1, -1, -1, -1} : MARGINS{0, 0, 0, 0};
  DwmExtendFrameIntoClientArea(window, &margins);
}

void SetOverlayWindowChrome(HWND window, bool enabled) {
  if (window == nullptr) {
    return;
  }

  const DWMNCRENDERINGPOLICY rendering_policy =
      enabled ? DWMNCRP_DISABLED : DWMNCRP_USEWINDOWSTYLE;
  DwmSetWindowAttribute(window, DWMWA_NCRENDERING_POLICY, &rendering_policy,
                        sizeof(rendering_policy));

  const COLORREF border_color = enabled ? kDwmColorNone : kDwmColorDefault;
  DwmSetWindowAttribute(window, DWMWA_BORDER_COLOR, &border_color,
                        sizeof(border_color));

  const WindowCornerPreference corner_preference =
      enabled ? kWindowCornerPreferenceDoNotRound
              : kWindowCornerPreferenceDefault;
  DwmSetWindowAttribute(window, DWMWA_WINDOW_CORNER_PREFERENCE,
                        &corner_preference, sizeof(corner_preference));
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  InitializeMethodChannel();

  return true;
}

void FlutterWindow::OnDestroy() {
  StopEscMonitor();
  StopOverlayDismissOnNextClickMonitor();
  HideToolbarPanel();
  HideScrollStopButton();
  RestoreWindowState();
  if (material_icons_font_loaded_ && !material_icons_font_path_.empty()) {
    RemoveFontResourceExW(material_icons_font_path_.c_str(), FR_PRIVATE,
                          nullptr);
    material_icons_font_loaded_ = false;
    material_icons_font_path_.clear();
  }
  window_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::InitializeMethodChannel() {
  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "com.asnap/window",
          &flutter::StandardMethodCodec::GetInstance());

  window_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleWindowMethodCall(call, std::move(result));
  });
}

void FlutterWindow::HandleWindowMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args = AsEncodableMap(call.arguments());
  const std::string& method = call.method_name();

  if (method == "captureScreen") {
    const bool all_displays = args != nullptr && GetBool(*args, "allDisplays");

    if (all_displays) {
      const auto monitors = GetMonitorDetailsList();
      if (monitors.empty()) {
        result->Success(flutter::EncodableValue());
        return;
      }

      RECT physical_bounds = monitors.front().physical_bounds;
      double logical_left = static_cast<double>(physical_bounds.left) /
                            monitors.front().scale;
      double logical_top = static_cast<double>(physical_bounds.top) /
                           monitors.front().scale;
      double logical_right = static_cast<double>(physical_bounds.right) /
                             monitors.front().scale;
      double logical_bottom = static_cast<double>(physical_bounds.bottom) /
                              monitors.front().scale;
      for (size_t index = 1; index < monitors.size(); ++index) {
        const auto& monitor = monitors[index];
        physical_bounds.left =
            std::min(physical_bounds.left, monitor.physical_bounds.left);
        physical_bounds.top =
            std::min(physical_bounds.top, monitor.physical_bounds.top);
        physical_bounds.right =
            std::max(physical_bounds.right, monitor.physical_bounds.right);
        physical_bounds.bottom =
            std::max(physical_bounds.bottom, monitor.physical_bounds.bottom);

        const double monitor_left =
            static_cast<double>(monitor.physical_bounds.left) /
            monitor.scale;
        const double monitor_top =
            static_cast<double>(monitor.physical_bounds.top) /
            monitor.scale;
        const double monitor_right =
            static_cast<double>(monitor.physical_bounds.right) /
            monitor.scale;
        const double monitor_bottom =
            static_cast<double>(monitor.physical_bounds.bottom) /
            monitor.scale;

        logical_left = std::min(logical_left, monitor_left);
        logical_top = std::min(logical_top, monitor_top);
        logical_right = std::max(logical_right, monitor_right);
        logical_bottom = std::max(logical_bottom, monitor_bottom);
      }

      const auto capture = CaptureScreenRect(physical_bounds);
      if (!capture.has_value()) {
        result->Success(flutter::EncodableValue());
        return;
      }

      result->Success(flutter::EncodableValue(CapturePayload(
          *capture,
          logical_right - logical_left,
          logical_bottom - logical_top,
          logical_left,
          logical_top)));
      return;
    }

    POINT cursor{};
    GetCursorPos(&cursor);
    const auto monitor = FindMonitorForPhysicalPoint(cursor);
    if (!monitor.has_value()) {
      result->Success(flutter::EncodableValue());
      return;
    }

    const auto capture = CaptureScreenRect(monitor->physical_bounds);
    if (!capture.has_value()) {
      result->Success(flutter::EncodableValue());
      return;
    }

    result->Success(flutter::EncodableValue(CapturePayload(
        *capture,
        static_cast<double>(monitor->physical_bounds.right -
                            monitor->physical_bounds.left) /
            monitor->scale,
        static_cast<double>(monitor->physical_bounds.bottom -
                            monitor->physical_bounds.top) /
            monitor->scale,
        static_cast<double>(monitor->physical_bounds.left) / monitor->scale,
        static_cast<double>(monitor->physical_bounds.top) / monitor->scale)));
    return;
  }

  if (method == "captureRegion") {
    if (args == nullptr) {
      result->Error("INVALID_ARGS",
                    "captureRegion requires x, y, width, and height.");
      return;
    }

    const auto x = GetDouble(*args, "x");
    const auto y = GetDouble(*args, "y");
    const auto width = GetDouble(*args, "width");
    const auto height = GetDouble(*args, "height");
    const bool include_layered_windows =
        GetBool(*args, "includeLayeredWindows", true);
    if (!x.has_value() || !y.has_value() || !width.has_value() ||
        !height.has_value() || *width <= 0 || *height <= 0) {
      result->Error("INVALID_ARGS",
                    "captureRegion requires positive x, y, width, and height.");
      return;
    }

    const auto physical_rect =
        LogicalToPhysicalRect(*x, *y, *width, *height);
    if (!physical_rect.has_value()) {
      result->Success(flutter::EncodableValue());
      return;
    }

    const auto capture =
        CaptureScreenRect(*physical_rect, include_layered_windows);
    if (!capture.has_value()) {
      result->Success(flutter::EncodableValue());
      return;
    }

    result->Success(flutter::EncodableValue(
        CapturePayload(*capture, *width, *height, *x, *y)));
    return;
  }

  if (method == "getScreenInfoForPoint") {
    if (args == nullptr) {
      result->Error("INVALID_ARGS",
                    "getScreenInfoForPoint requires x and y.");
      return;
    }

    const auto x = GetDouble(*args, "x");
    const auto y = GetDouble(*args, "y");
    if (!x.has_value() || !y.has_value()) {
      result->Error("INVALID_ARGS",
                    "getScreenInfoForPoint requires x and y.");
      return;
    }

    const auto monitor = FindMonitorForLogicalPoint(*x, *y);
    if (!monitor.has_value()) {
      result->Success(flutter::EncodableValue());
      return;
    }

    flutter::EncodableMap payload;
    payload[flutter::EncodableValue("screenWidth")] = flutter::EncodableValue(
        static_cast<double>(monitor->logical_bounds.right -
                            monitor->logical_bounds.left));
    payload[flutter::EncodableValue("screenHeight")] = flutter::EncodableValue(
        static_cast<double>(monitor->logical_bounds.bottom -
                            monitor->logical_bounds.top));
    payload[flutter::EncodableValue("screenOriginX")] =
        flutter::EncodableValue(static_cast<double>(monitor->logical_bounds.left));
    payload[flutter::EncodableValue("screenOriginY")] =
        flutter::EncodableValue(static_cast<double>(monitor->logical_bounds.top));
    result->Success(flutter::EncodableValue(payload));
    return;
  }

  if (method == "getWindowList") {
    flutter::EncodableList windows;
    WindowListContext context{GetHandle(), &windows};
    EnumWindows(EnumWindowsProc, reinterpret_cast<LPARAM>(&context));
    result->Success(flutter::EncodableValue(windows));
    return;
  }

  if (method == "hitTestElement") {
    if (args == nullptr) {
      result->Error("INVALID_ARGS", "hitTestElement requires x and y.");
      return;
    }

    const auto x = GetDouble(*args, "x");
    const auto y = GetDouble(*args, "y");
    if (!x.has_value() || !y.has_value()) {
      result->Error("INVALID_ARGS", "hitTestElement requires x and y.");
      return;
    }

    const auto point = LogicalToPhysicalPoint(*x, *y);
    if (!point.has_value()) {
      result->Success(flutter::EncodableValue());
      return;
    }

    const auto rect = GetWindowRectForPoint(*point, GetHandle());
    if (!rect.has_value()) {
      result->Success(flutter::EncodableValue());
      return;
    }

    result->Success(flutter::EncodableValue(RectToEncodableMap(*rect)));
    return;
  }

  if (method == "enterOverlayMode") {
    std::optional<MonitorDetails> monitor;
    if (args != nullptr) {
      const auto x = GetDouble(*args, "screenOriginX");
      const auto y = GetDouble(*args, "screenOriginY");
      if (x.has_value() && y.has_value()) {
        monitor = FindMonitorByLogicalOrigin(*x, *y);
      }
    }

    if (!monitor.has_value()) {
      POINT cursor{};
      GetCursorPos(&cursor);
      monitor = FindMonitorForPhysicalPoint(cursor);
    }

    if (monitor.has_value()) {
      ConfigureOverlayWindow(monitor->physical_bounds, false, 0);
    }
    result->Success(flutter::EncodableValue());
    return;
  }

  if (method == "enterInkOverlayMode") {
    std::optional<MonitorDetails> monitor;
    if (args != nullptr) {
      const auto x = GetDouble(*args, "screenOriginX");
      const auto y = GetDouble(*args, "screenOriginY");
      if (x.has_value() && y.has_value()) {
        monitor = FindMonitorByLogicalOrigin(*x, *y);
      }
    }

    if (!monitor.has_value()) {
      POINT cursor{};
      GetCursorPos(&cursor);
      monitor = FindMonitorForPhysicalPoint(cursor);
    }

    if (monitor.has_value()) {
      ConfigureInkOverlayWindow(monitor->physical_bounds);
    }
    result->Success(flutter::EncodableValue());
    return;
  }

  if (method == "cleanupOverlayMode" || method == "exitOverlayMode") {
    RestoreWindowState();
    result->Success(flutter::EncodableValue());
    return;
  }

  if (method == "dismissAppWindow") {
    DismissAppWindow();
    result->Success(flutter::EncodableValue());
    return;
  }

  if (method == "suspendOverlay") {
    SetWindowOpacity(0);
    result->Success(flutter::EncodableValue());
    return;
  }

  if (method == "repositionOverlay") {
    if (args == nullptr) {
      result->Error("INVALID_ARGS",
                    "repositionOverlay requires screenOriginX and screenOriginY.");
      return;
    }

    const auto x = GetDouble(*args, "screenOriginX");
    const auto y = GetDouble(*args, "screenOriginY");
    if (!x.has_value() || !y.has_value()) {
      result->Error("INVALID_ARGS",
                    "repositionOverlay requires screenOriginX and screenOriginY.");
      return;
    }

    const auto monitor = FindMonitorByLogicalOrigin(*x, *y);
    if (monitor.has_value()) {
      const RECT& bounds = monitor->physical_bounds;
      SetWindowPos(GetHandle(), HWND_TOPMOST, bounds.left, bounds.top,
                   bounds.right - bounds.left, bounds.bottom - bounds.top,
                   SWP_FRAMECHANGED | SWP_NOACTIVATE | SWP_NOOWNERZORDER);
      if (flutter_controller_) {
        flutter_controller_->ForceRedraw();
      }
    }
    result->Success(flutter::EncodableValue());
    return;
  }

  if (method == "revealOverlay") {
    SetMousePassthrough(false);
    SetWindowOpacity(255);
    ActivateAppWindow();
    DisableLayeredWindowIfTransparent();
    SyncFlutterWindowMetrics();
    if (flutter_controller_) {
      flutter_controller_->ForceRedraw();
    }
    result->Success(flutter::EncodableValue());
    return;
  }

  if (method == "revealInkOverlay") {
    SetMousePassthrough(false);
    SetWindowCloak(GetHandle(), false);
    ActivateAppWindow();
    SyncFlutterWindowMetrics();
    if (flutter_controller_) {
      flutter_controller_->ForceRedraw();
    }
    result->Success(flutter::EncodableValue());
    return;
  }

  if (method == "setOverlayMousePassthrough") {
    const bool passthrough =
        args != nullptr && GetBool(*args, "passthrough", false);
    SetMousePassthrough(passthrough);
    result->Success(flutter::EncodableValue());
    return;
  }

  if (method == "setOverlayDismissOnNextClick") {
    const bool enabled = args != nullptr && GetBool(*args, "enabled", false);
    SetOverlayDismissOnNextClick(enabled);
    result->Success(flutter::EncodableValue());
    return;
  }

  if (method == "activateApp") {
    ActivateAppWindow();
    result->Success(flutter::EncodableValue());
    return;
  }

  if (method == "startEscMonitor") {
    if (!esc_hotkey_registered_) {
      esc_hotkey_registered_ =
          RegisterHotKey(GetHandle(), kEscHotkeyId, MOD_NOREPEAT,
                         VK_ESCAPE) != FALSE;
      if (!esc_hotkey_registered_) {
        esc_hotkey_registered_ =
            RegisterHotKey(GetHandle(), kEscHotkeyId, 0, VK_ESCAPE) != FALSE;
      }
    }
    result->Success(flutter::EncodableValue());
    return;
  }

  if (method == "stopEscMonitor") {
    StopEscMonitor();
    result->Success(flutter::EncodableValue());
    return;
  }

  if (method == "showScrollStopButton") {
    if (args == nullptr) {
      result->Error("INVALID_ARGS",
                    "showScrollStopButton requires x, y, width, and height.");
      return;
    }

    const auto x = GetDouble(*args, "x");
    const auto y = GetDouble(*args, "y");
    const auto width = GetDouble(*args, "width");
    const auto height = GetDouble(*args, "height");
    if (!x.has_value() || !y.has_value() || !width.has_value() ||
        !height.has_value() || *width <= 0 || *height <= 0) {
      result->Error("INVALID_ARGS",
                    "showScrollStopButton requires positive x, y, width, "
                    "and height.");
      return;
    }

    const auto physical_rect =
        LogicalToPhysicalRect(*x, *y, *width, *height);
    if (physical_rect.has_value()) {
      ShowScrollStopButton(*physical_rect);
    }
    result->Success(flutter::EncodableValue());
    return;
  }

  if (method == "hideScrollStopButton") {
    HideScrollStopButton();
    result->Success(flutter::EncodableValue());
    return;
  }

  if (method == "showToolbarPanel") {
    if (args == nullptr) {
      result->Error("INVALID_ARGS",
                    "showToolbarPanel requires a request payload.");
      return;
    }
    ShowOrUpdateToolbarPanel(*args);
    result->Success(flutter::EncodableValue());
    return;
  }

  if (method == "hideToolbarPanel") {
    HideToolbarPanel();
    result->Success(flutter::EncodableValue());
    return;
  }

  if (method == "resetToolbarPanelState") {
    ResetToolbarPanelState();
    result->Success(flutter::EncodableValue());
    return;
  }

  if (method == "flushPendingToolbarPanel") {
    FlushPendingToolbarPanel();
    result->Success(flutter::EncodableValue());
    return;
  }

  if (method == "startRectPolling" || method == "stopRectPolling" ||
      method == "registerTrayShortcuts" || method == "closePinnedImage") {
    result->Success(flutter::EncodableValue());
    return;
  }

  if (method == "preparePreviewWindow") {
    const bool use_native_shadow =
        args != nullptr && GetBool(*args, "useNativeShadow", true);
    PreparePreviewWindow(use_native_shadow);
    result->Success(flutter::EncodableValue());
    return;
  }

  if (method == "enterScrollCaptureMode") {
    EnsureSavedWindowState();
    SetMousePassthrough(true);
    SetWindowOpacity(255);
    result->Success(flutter::EncodableValue());
    return;
  }

  if (method == "exitScrollCaptureMode") {
    SetMousePassthrough(false);
    result->Success(flutter::EncodableValue());
    return;
  }

  if (method == "revealPreviewWindow") {
    SetMousePassthrough(false);
    SetWindowOpacity(255);
    ActivateAppWindow();
    result->Success(flutter::EncodableValue());
    return;
  }

  if (method == "pinImage" || method == "getPinnedPanelFrame") {
    result->Success(flutter::EncodableValue());
    return;
  }

  if (method == "checkAccessibility" ||
      method == "checkScreenCapturePermission" ||
      method == "requestScreenCapturePermission") {
    result->Success(flutter::EncodableValue(true));
    return;
  }

  result->NotImplemented();
}

void FlutterWindow::EnsureSavedWindowState() {
  if (saved_window_state_) {
    return;
  }

  const HWND window = GetHandle();
  if (window == nullptr) {
    return;
  }

  saved_window_style_ = GetWindowLongPtr(window, GWL_STYLE);
  saved_window_ex_style_ = GetWindowLongPtr(window, GWL_EXSTYLE);
  GetWindowRect(window, &saved_window_rect_);
  saved_window_state_ = true;
}

void FlutterWindow::RestoreWindowState() {
  if (!saved_window_state_) {
    return;
  }

  const HWND window = GetHandle();
  if (window == nullptr) {
    return;
  }

  // Hide the hosted Flutter child first so DWM drops the last composited
  // capture frame instead of leaving it visible until the next input event.
  SetHostedFlutterViewVisible(false);
  SetWindowLongPtr(window, GWL_STYLE, saved_window_style_);
  SetWindowLongPtr(window, GWL_EXSTYLE, saved_window_ex_style_);
  custom_frame_active_ = false;
  SetOverlayWindowChrome(window, false);
  SetWindowCloak(window, true);
  SetWindowPos(window, HWND_NOTOPMOST, saved_window_rect_.left,
               saved_window_rect_.top,
               saved_window_rect_.right - saved_window_rect_.left,
               saved_window_rect_.bottom - saved_window_rect_.top,
               SWP_FRAMECHANGED | SWP_NOACTIVATE | SWP_NOOWNERZORDER |
                   SWP_HIDEWINDOW);
  LayoutHostedFlutterView();
  ShowWindow(window, SW_HIDE);
  HideToolbarPanel();
  HideScrollStopButton();
  SetWindowExcludedFromCapture(false);
  SetTransparentBackground(false);
  StopOverlayDismissOnNextClickMonitor();
  SetMousePassthrough(false);
  RedrawWindow(window, nullptr, nullptr,
               RDW_ERASE | RDW_FRAME | RDW_INVALIDATE | RDW_ALLCHILDREN |
                   RDW_UPDATENOW);
  RedrawWindow(GetDesktopWindow(), nullptr, nullptr,
               RDW_INVALIDATE | RDW_ALLCHILDREN | RDW_UPDATENOW);
  DwmFlush();
  if (flutter_controller_) {
    flutter_controller_->ForceRedraw();
  }
  saved_window_state_ = false;
}

void FlutterWindow::DismissAppWindow() {
  const HWND window = GetHandle();
  if (window == nullptr) {
    return;
  }

  if (saved_window_state_) {
    RestoreWindowState();
    return;
  }

  HideToolbarPanel();
  HideScrollStopButton();
  SetWindowExcludedFromCapture(false);
  SetTransparentBackground(false);
  StopOverlayDismissOnNextClickMonitor();
  SetMousePassthrough(false);
  SetHostedFlutterViewVisible(false);
  custom_frame_active_ = false;
  SetOverlayWindowChrome(window, false);
  SetWindowCloak(window, true);
  SetWindowPos(window, HWND_NOTOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE |
                   SWP_NOOWNERZORDER | SWP_HIDEWINDOW);
  ShowWindow(window, SW_HIDE);
  RedrawWindow(window, nullptr, nullptr,
               RDW_ERASE | RDW_FRAME | RDW_INVALIDATE | RDW_ALLCHILDREN |
                   RDW_UPDATENOW);
  RedrawWindow(GetDesktopWindow(), nullptr, nullptr,
               RDW_INVALIDATE | RDW_ALLCHILDREN | RDW_UPDATENOW);
  DwmFlush();
}

void FlutterWindow::PreparePreviewWindow(bool use_native_shadow) {
  const HWND window = GetHandle();
  if (window == nullptr) {
    return;
  }

  EnsureSavedWindowState();
  SetWindowCloak(window, false);
  custom_frame_active_ = true;

  LONG_PTR ex_style = saved_window_ex_style_ | WS_EX_LAYERED | WS_EX_TOOLWINDOW;
  ex_style &= ~WS_EX_APPWINDOW;
  ex_style &= ~WS_EX_TRANSPARENT;

  SetWindowLongPtr(window, GWL_STYLE,
                   WS_POPUP | WS_CLIPCHILDREN | WS_CLIPSIBLINGS);
  SetWindowLongPtr(window, GWL_EXSTYLE, ex_style);
  SetOverlayWindowChrome(window, false);
  SetWindowPos(window, nullptr, 0, 0, 0, 0,
               SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                   SWP_NOACTIVATE);
  LayoutHostedFlutterView();
  SetWindowExcludedFromCapture(false);
  SetTransparentBackground(true);
  SetMousePassthrough(false);
  if (!use_native_shadow) {
    SetWindowRgn(window, nullptr, TRUE);
  }
  if (flutter_controller_) {
    flutter_controller_->ForceRedraw();
  }
}

void FlutterWindow::ConfigureInkOverlayWindow(const RECT& bounds) {
  const HWND window = GetHandle();
  if (window == nullptr) {
    return;
  }

  EnsureSavedWindowState();
  custom_frame_active_ = true;
  SetWindowCloak(window, true);

  LONG_PTR ex_style = saved_window_ex_style_ | WS_EX_TOOLWINDOW;
  ex_style &= ~WS_EX_APPWINDOW;
  ex_style &= ~WS_EX_LAYERED;
  ex_style &= ~WS_EX_TRANSPARENT;

  SetWindowLongPtr(window, GWL_STYLE,
                   WS_POPUP | WS_CLIPCHILDREN | WS_CLIPSIBLINGS);
  SetWindowLongPtr(window, GWL_EXSTYLE, ex_style);
  SetOverlayWindowChrome(window, true);
  SetWindowPos(window, HWND_TOPMOST, bounds.left, bounds.top,
               bounds.right - bounds.left, bounds.bottom - bounds.top,
               SWP_FRAMECHANGED | SWP_SHOWWINDOW | SWP_NOOWNERZORDER |
                   SWP_NOACTIVATE);
  LayoutHostedFlutterView();
  SetWindowExcludedFromCapture(true);
  SetTransparentBackground(true);
  SetHostedFlutterViewVisible(true);
  SyncFlutterWindowMetrics();
  if (flutter_controller_) {
    flutter_controller_->ForceRedraw();
  }
}

void FlutterWindow::ConfigureOverlayWindow(const RECT& bounds,
                                           bool click_through, BYTE alpha) {
  const HWND window = GetHandle();
  if (window == nullptr) {
    return;
  }

  EnsureSavedWindowState();
  SetWindowCloak(window, false);
  custom_frame_active_ = true;

  LONG_PTR ex_style = saved_window_ex_style_ | WS_EX_LAYERED | WS_EX_TOOLWINDOW;
  ex_style &= ~WS_EX_APPWINDOW;
  if (click_through) {
    ex_style |= WS_EX_TRANSPARENT;
  } else {
    ex_style &= ~WS_EX_TRANSPARENT;
  }

  SetWindowLongPtr(window, GWL_STYLE,
                   WS_POPUP | WS_CLIPCHILDREN | WS_CLIPSIBLINGS);
  SetWindowLongPtr(window, GWL_EXSTYLE, ex_style);
  SetOverlayWindowChrome(window, true);
  SetWindowPos(window, HWND_TOPMOST, bounds.left, bounds.top,
               bounds.right - bounds.left, bounds.bottom - bounds.top,
               SWP_FRAMECHANGED | SWP_SHOWWINDOW | SWP_NOOWNERZORDER);
  LayoutHostedFlutterView();
  SetWindowExcludedFromCapture(true);
  SetTransparentBackground(true);
  SetWindowOpacity(alpha);
  ShowWindow(window, SW_SHOWNOACTIVATE);
  // Match macOS overlay behavior: keep Flutter rendering while the host window
  // is transparent (alpha=0). Hiding the hosted view here can leave the first
  // revealed frame at a stale size, which skews pointer mapping.
  SetHostedFlutterViewVisible(true);
  SyncFlutterWindowMetrics();
  if (flutter_controller_) {
    flutter_controller_->ForceRedraw();
  }
}

void FlutterWindow::LayoutHostedFlutterView() {
  if (!flutter_controller_ || !flutter_controller_->view()) {
    return;
  }

  const HWND flutter_view = flutter_controller_->view()->GetNativeWindow();
  const HWND window = GetHandle();
  if (flutter_view == nullptr || window == nullptr) {
    return;
  }

  RECT client_rect{};
  if (!GetClientRect(window, &client_rect)) {
    return;
  }

  MoveWindow(flutter_view, client_rect.left, client_rect.top,
             client_rect.right - client_rect.left,
             client_rect.bottom - client_rect.top, TRUE);
}

void FlutterWindow::SyncFlutterWindowMetrics() {
  const HWND window = GetHandle();
  if (window == nullptr) {
    return;
  }

  RECT client_rect{};
  if (!GetClientRect(window, &client_rect)) {
    return;
  }

  const int width = client_rect.right - client_rect.left;
  const int height = client_rect.bottom - client_rect.top;
  if (width <= 0 || height <= 0) {
    return;
  }

  LayoutHostedFlutterView();
  SendMessage(window, WM_SIZE, SIZE_RESTORED, MAKELPARAM(width, height));
}

void FlutterWindow::ShowOrUpdateToolbarPanel(
    const flutter::EncodableMap& args) {
  const auto placement = GetString(args, "placement");
  const auto request_id = GetInt(args, "requestId");
  const auto session_id = GetInt64(args, "sessionId");
  if (!placement.has_value() || !request_id.has_value() ||
      !session_id.has_value()) {
    return;
  }

  if (latest_toolbar_session_id_ != 0 &&
      latest_toolbar_session_id_ != *session_id) {
    ResetToolbarPanelState();
  }
  if (*request_id < latest_toolbar_request_id_) {
    return;
  }

  latest_toolbar_session_id_ = *session_id;
  latest_toolbar_request_id_ = *request_id;
  last_toolbar_args_ = args;

  const HWND owner = GetHandle();
  if (owner == nullptr || !IsWindowVisible(owner) || IsIconic(owner)) {
    pending_toolbar_args_ = args;
    HideToolbarPanel(false, false);
    return;
  }
  pending_toolbar_args_.reset();

  const bool show_pin = GetBool(args, "showPin");
  const bool show_history_controls = GetBool(args, "showHistoryControls");
  const bool can_undo = GetBool(args, "canUndo");
  const bool can_redo = GetBool(args, "canRedo");
  const bool show_ocr = GetBool(args, "showOcr");
  const auto active_tool = GetString(args, "activeTool");
  const bool use_material_icons = EnsureMaterialIconsFont();

  toolbar_buttons_.clear();
  auto add_button = [&](const char* action, const wchar_t* label,
                        uint32_t icon_codepoint, bool enabled = true,
                        bool selected = false, bool destructive = false) {
    ToolbarButtonState button;
    button.action = action;
    button.label = label;
    button.icon_codepoint = icon_codepoint;
    button.enabled = enabled;
    button.selected = selected;
    button.destructive = destructive;
    toolbar_buttons_.push_back(std::move(button));
  };
  auto add_separator = [&]() {
    ToolbarButtonState separator;
    separator.separator = true;
    toolbar_buttons_.push_back(std::move(separator));
  };

  add_button("rectangle", L"Rect", 0xF68A, true,
             active_tool.has_value() && *active_tool == "rectangle");
  add_button("ellipse", L"Oval", 0xEF53, true,
             active_tool.has_value() && *active_tool == "ellipse");
  add_button("arrow", L"Arrow", 0xF57C, true,
             active_tool.has_value() && *active_tool == "arrow");
  add_button("line", L"Line", 0xF7F8, true,
             active_tool.has_value() && *active_tool == "line");
  add_button("pencil", L"Pen", 0xF6FB, true,
             active_tool.has_value() && *active_tool == "pencil");
  add_button("marker", L"Mark", 0xF5EF, true,
             active_tool.has_value() && *active_tool == "marker");
  add_button("mosaic", L"Mosaic", 0xF5C9, true,
             active_tool.has_value() && *active_tool == "mosaic");
  add_button("number", L"Num", 0xF890, true,
             active_tool.has_value() && *active_tool == "number");
  add_button("text", L"Text", 0xF023D, true,
             active_tool.has_value() && *active_tool == "text");

  if (show_ocr) {
    add_button("ocr", L"OCR", 0xF434);
  }
  if (show_history_controls) {
    add_separator();
    add_button("undo", L"Undo", 0xF0261, can_undo);
    add_button("redo", L"Redo", 0xF00E7, can_redo);
  }

  add_separator();
  add_button("copy", L"Copy", 0xF66C);
  add_button("save", L"Save", 0xF6DF);
  if (show_pin) {
    add_button("pin", L"Pin", 0xF2D7);
  }
  add_button("close", L"Close", 0xF647, true, false, true);

  const HINSTANCE instance = GetModuleHandle(nullptr);
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = FlutterWindow::ToolbarWindowProc;
  window_class.hInstance = instance;
  window_class.lpszClassName = kToolbarWindowClassName;
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  RegisterClassW(&window_class);

  if (toolbar_window_ == nullptr || !IsWindow(toolbar_window_)) {
    toolbar_window_ = CreateWindowExW(
        WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
        kToolbarWindowClassName, L"",
        WS_POPUP | WS_CLIPSIBLINGS | WS_CLIPCHILDREN, 0, 0, 0, 0, owner,
        nullptr, instance, this);
    if (toolbar_window_ == nullptr) {
      return;
    }
  }

  const auto owner_monitor =
      FindMonitorByHandle(MonitorFromWindow(owner, MONITOR_DEFAULTTONEAREST));
  const double scale = owner_monitor.has_value() ? owner_monitor->scale : 1.0;

  const int panel_padding_x = std::max(1, RoundToInt(8 * scale));
  const int panel_height = std::max(1, RoundToInt(44 * scale));
  const int button_visual_size = std::max(1, RoundToInt(32 * scale));
  const int button_gap = std::max(1, RoundToInt(2 * scale));
  const int separator_gap = std::max(1, RoundToInt(6 * scale));
  const int separator_height = std::max(1, RoundToInt(20 * scale));
  const int button_top = (panel_height - button_visual_size) / 2;
  const int separator_top = (panel_height - separator_height) / 2;
  const int panel_corner_radius =
      std::max(1, RoundToInt(kToolbarCornerRadius * scale));
  const int button_corner_radius = std::max(1, RoundToInt(10 * scale));
  const int icon_font_size = std::max(1, RoundToInt(18 * scale));
  const int min_text_button_width = std::max(1, RoundToInt(34 * scale));
  toolbar_panel_corner_radius_ = panel_corner_radius;
  toolbar_button_corner_radius_ = button_corner_radius;
  toolbar_icon_font_size_ = icon_font_size;

  int panel_width = panel_padding_x;
  int cursor_x = panel_padding_x;
  for (auto& button : toolbar_buttons_) {
    if (button.separator) {
      cursor_x += separator_gap;
      button.rect =
          RECT{cursor_x, separator_top, cursor_x + 1, separator_top + separator_height};
      cursor_x += 1 + separator_gap;
      panel_width = cursor_x;
      continue;
    }

    if (use_material_icons) {
      button.rect =
          RECT{cursor_x, button_top, cursor_x + button_visual_size,
               button_top + button_visual_size};
      cursor_x += button_visual_size + button_gap;
    } else {
      HDC dc = GetDC(toolbar_window_);
      HFONT font = static_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
      HGDIOBJ old_font = SelectObject(dc, font);
      SIZE text_size{};
      GetTextExtentPoint32W(dc, button.label.c_str(),
                            static_cast<int>(button.label.size()), &text_size);
      SelectObject(dc, old_font);
      ReleaseDC(toolbar_window_, dc);

      const int button_width =
          std::max<int>(min_text_button_width,
                        static_cast<int>(text_size.cx) + 24);
      button.rect =
          RECT{cursor_x, button_top, cursor_x + button_width,
               button_top + button_visual_size};
      cursor_x += button_width + button_gap;
    }
    panel_width = cursor_x;
  }

  if (!toolbar_buttons_.empty()) {
    panel_width =
        std::max(panel_padding_x * 2, panel_width - button_gap + panel_padding_x);
  }

  RECT owner_rect{};
  GetWindowRect(owner, &owner_rect);
  RECT anchor_rect = owner_rect;
  if (*placement == "belowAnchor") {
    if (const auto* anchor = GetMapValue(args, "anchorRect")) {
      const auto x = GetDouble(*anchor, "x");
      const auto y = GetDouble(*anchor, "y");
      const auto width = GetDouble(*anchor, "width");
      const auto height = GetDouble(*anchor, "height");
      if (x.has_value() && y.has_value() && width.has_value() &&
          height.has_value()) {
        anchor_rect.left = owner_rect.left + RoundToInt(*x * scale);
        anchor_rect.top = owner_rect.top + RoundToInt(*y * scale);
        anchor_rect.right = anchor_rect.left + RoundToInt(*width * scale);
        anchor_rect.bottom = anchor_rect.top + RoundToInt(*height * scale);
      }
    }
  }

  const HMONITOR monitor =
      MonitorFromRect(&anchor_rect, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(MONITORINFO);
  GetMonitorInfo(monitor, &monitor_info);
  const RECT work_area = monitor_info.rcWork;
  const int screen_padding = 8;
  const int toolbar_gap = 8;

  int x = ((anchor_rect.left + anchor_rect.right) / 2) - (panel_width / 2);
  const int min_x = work_area.left + screen_padding;
  const int max_x = work_area.right - screen_padding - panel_width;
  if (max_x <= min_x) {
    x = min_x;
  } else {
    x = std::clamp(x, min_x, max_x);
  }

  int y = anchor_rect.bottom + toolbar_gap;
  const int max_y = work_area.bottom - screen_padding - panel_height;
  if (y > max_y) {
    const int above_y = anchor_rect.top - toolbar_gap - panel_height;
    if (above_y >= work_area.top + screen_padding) {
      y = above_y;
    } else if (max_y <= work_area.top + screen_padding) {
      y = work_area.top + screen_padding;
    } else {
      y = std::clamp<int>(y, static_cast<int>(work_area.top + screen_padding),
                          static_cast<int>(max_y));
    }
  }

  const RECT panel_rect = RECT{x, y, x + panel_width, y + panel_height};
  hovered_toolbar_button_index_ = -1;
  pressed_toolbar_button_index_ = -1;
  SetWindowPos(toolbar_window_, HWND_TOPMOST, panel_rect.left, panel_rect.top,
               panel_width, panel_height,
               SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_SHOWWINDOW);
  ApplyRoundedWindowRegion(toolbar_window_, panel_width, panel_height,
                           panel_corner_radius);
  SetWindowDisplayAffinity(toolbar_window_, WDA_EXCLUDEFROMCAPTURE);
  ShowWindow(toolbar_window_, SW_SHOWNOACTIVATE);
  InvalidateRect(toolbar_window_, nullptr, TRUE);
  UpdateWindow(toolbar_window_);
  EmitToolbarFrameChanged(panel_rect, *request_id, *session_id);
}

void FlutterWindow::FlushPendingToolbarPanel() {
  if (pending_toolbar_args_.has_value()) {
    const auto args = *pending_toolbar_args_;
    pending_toolbar_args_.reset();
    ShowOrUpdateToolbarPanel(args);
    return;
  }

  if (last_toolbar_args_.has_value()) {
    ShowOrUpdateToolbarPanel(*last_toolbar_args_);
  }
}

void FlutterWindow::RefreshToolbarPanelIfNeeded() {
  if (pending_toolbar_args_.has_value() || !last_toolbar_args_.has_value()) {
    return;
  }

  const HWND owner = GetHandle();
  if (owner == nullptr || !IsWindowVisible(owner) || IsIconic(owner)) {
    HideToolbarPanel(false, false);
    return;
  }

  ShowOrUpdateToolbarPanel(*last_toolbar_args_);
}

void FlutterWindow::HideToolbarPanel(bool clear_pending, bool clear_last) {
  if (clear_pending) {
    pending_toolbar_args_.reset();
  }
  if (clear_last) {
    last_toolbar_args_.reset();
  }
  toolbar_buttons_.clear();
  hovered_toolbar_button_index_ = -1;
  pressed_toolbar_button_index_ = -1;
  if (toolbar_window_ != nullptr && IsWindow(toolbar_window_)) {
    DestroyWindow(toolbar_window_);
  }
  toolbar_window_ = nullptr;
}

void FlutterWindow::ResetToolbarPanelState() {
  latest_toolbar_request_id_ = 0;
  latest_toolbar_session_id_ = 0;
  HideToolbarPanel(true, true);
}

void FlutterWindow::HandleToolbarActionClick(const std::string& action) {
  if (window_channel_) {
    flutter::EncodableMap args;
    args[flutter::EncodableValue("action")] = flutter::EncodableValue(action);
    window_channel_->InvokeMethod(
        "onToolbarAction",
        std::make_unique<flutter::EncodableValue>(std::move(args)));
  }
  ActivateAppWindow();
}

void FlutterWindow::EmitToolbarFrameChanged(const RECT& physical_rect,
                                            int request_id,
                                            int64_t session_id) {
  if (!window_channel_) {
    return;
  }

  RECT owner_rect{};
  const HWND owner = GetHandle();
  if (owner == nullptr || !GetWindowRect(owner, &owner_rect)) {
    return;
  }

  const auto monitor =
      FindMonitorByHandle(MonitorFromRect(&physical_rect, MONITOR_DEFAULTTONEAREST));
  const double scale = monitor.has_value() ? monitor->scale : 1.0;
  flutter::EncodableMap payload;
  payload[flutter::EncodableValue("x")] =
      flutter::EncodableValue(static_cast<double>(physical_rect.left -
                                                  owner_rect.left) /
                              scale);
  payload[flutter::EncodableValue("y")] =
      flutter::EncodableValue(static_cast<double>(physical_rect.top -
                                                  owner_rect.top) /
                              scale);
  payload[flutter::EncodableValue("width")] =
      flutter::EncodableValue(static_cast<double>(physical_rect.right -
                                                  physical_rect.left) /
                              scale);
  payload[flutter::EncodableValue("height")] =
      flutter::EncodableValue(static_cast<double>(physical_rect.bottom -
                                                  physical_rect.top) /
                              scale);
  payload[flutter::EncodableValue("requestId")] =
      flutter::EncodableValue(request_id);
  payload[flutter::EncodableValue("sessionId")] =
      flutter::EncodableValue(session_id);
  window_channel_->InvokeMethod(
      "onToolbarFrameChanged",
      std::make_unique<flutter::EncodableValue>(std::move(payload)));
}

bool FlutterWindow::EnsureMaterialIconsFont() {
  if (material_icons_font_loaded_) {
    return true;
  }

  wchar_t module_path[MAX_PATH];
  const DWORD length =
      GetModuleFileNameW(nullptr, module_path, std::size(module_path));
  if (length == 0 || length >= std::size(module_path)) {
    return false;
  }

  std::wstring font_path(module_path, length);
  const size_t separator = font_path.find_last_of(L"\\/");
  if (separator == std::wstring::npos) {
    return false;
  }
  font_path.resize(separator);
  font_path += L"\\data\\flutter_assets\\fonts\\MaterialIcons-Regular.otf";

  const DWORD added = AddFontResourceExW(font_path.c_str(), FR_PRIVATE, nullptr);
  if (added == 0) {
    return false;
  }

  material_icons_font_loaded_ = true;
  material_icons_font_path_ = std::move(font_path);
  return true;
}

int FlutterWindow::HitTestToolbarButton(POINT point) const {
  for (size_t index = 0; index < toolbar_buttons_.size(); ++index) {
    const auto& button = toolbar_buttons_[index];
    if (button.separator || !button.enabled) {
      continue;
    }
    if (point.x >= button.rect.left && point.x < button.rect.right &&
        point.y >= button.rect.top && point.y < button.rect.bottom) {
      return static_cast<int>(index);
    }
  }
  return -1;
}

void FlutterWindow::UpdateToolbarHoverState(POINT point) {
  const int hovered = HitTestToolbarButton(point);
  if (hovered == hovered_toolbar_button_index_) {
    return;
  }
  hovered_toolbar_button_index_ = hovered;
  if (toolbar_window_ != nullptr && IsWindow(toolbar_window_)) {
    InvalidateRect(toolbar_window_, nullptr, TRUE);
  }
}

LRESULT CALLBACK FlutterWindow::ToolbarWindowProc(HWND hwnd, UINT message,
                                                  WPARAM wparam,
                                                  LPARAM lparam) noexcept {
  FlutterWindow* window = nullptr;
  if (message == WM_NCCREATE) {
    auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    window = static_cast<FlutterWindow*>(create->lpCreateParams);
    SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(window));
  } else {
    window =
        reinterpret_cast<FlutterWindow*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));
  }

  switch (message) {
    case WM_MOUSEACTIVATE:
      return MA_NOACTIVATE;
    case WM_SETCURSOR: {
      if (window != nullptr) {
        POINT cursor{};
        GetCursorPos(&cursor);
        ScreenToClient(hwnd, &cursor);
        if (window->HitTestToolbarButton(cursor) >= 0) {
          SetCursor(LoadCursor(nullptr, IDC_HAND));
          return TRUE;
        }
      }
      SetCursor(LoadCursor(nullptr, IDC_ARROW));
      return TRUE;
    }
    case WM_MOUSEMOVE:
      if (window != nullptr) {
        POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
        window->UpdateToolbarHoverState(point);
        TRACKMOUSEEVENT track_event{};
        track_event.cbSize = sizeof(track_event);
        track_event.dwFlags = TME_LEAVE;
        track_event.hwndTrack = hwnd;
        TrackMouseEvent(&track_event);
      }
      return 0;
    case WM_MOUSELEAVE:
      if (window != nullptr) {
        window->hovered_toolbar_button_index_ = -1;
        InvalidateRect(hwnd, nullptr, TRUE);
      }
      return 0;
    case WM_LBUTTONDOWN:
      if (window != nullptr) {
        POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
        window->pressed_toolbar_button_index_ = window->HitTestToolbarButton(point);
        SetCapture(hwnd);
        InvalidateRect(hwnd, nullptr, TRUE);
      }
      return 0;
    case WM_LBUTTONUP:
      if (window != nullptr) {
        POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
        const int hit = window->HitTestToolbarButton(point);
        const int pressed = window->pressed_toolbar_button_index_;
        window->pressed_toolbar_button_index_ = -1;
        ReleaseCapture();
        InvalidateRect(hwnd, nullptr, TRUE);
        if (hit >= 0 && hit == pressed) {
          window->HandleToolbarActionClick(
              window->toolbar_buttons_[static_cast<size_t>(hit)].action);
        }
      }
      return 0;
    case WM_PAINT: {
      if (window == nullptr) {
        break;
      }
      PAINTSTRUCT paint{};
      HDC dc = BeginPaint(hwnd, &paint);
      RECT client_rect{};
      GetClientRect(hwnd, &client_rect);

      const COLORREF panel_fill = RGB(30, 30, 30);
      const COLORREF panel_border = RGB(56, 56, 56);
      HBRUSH panel_brush = CreateSolidBrush(panel_fill);
      HPEN panel_pen = CreatePen(PS_SOLID, 1, panel_border);
      HGDIOBJ old_brush = SelectObject(dc, panel_brush);
      HGDIOBJ old_pen = SelectObject(dc, panel_pen);
      RoundRect(dc, client_rect.left, client_rect.top, client_rect.right,
                client_rect.bottom, window->toolbar_panel_corner_radius_ * 2,
                window->toolbar_panel_corner_radius_ * 2);
      SelectObject(dc, old_brush);
      SelectObject(dc, old_pen);
      DeleteObject(panel_brush);
      DeleteObject(panel_pen);

      SetBkMode(dc, TRANSPARENT);
      const bool use_material_icons = window->EnsureMaterialIconsFont();
      HFONT label_font = static_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
      HFONT icon_font = nullptr;
      if (use_material_icons) {
        icon_font = CreateFontW(-window->toolbar_icon_font_size_, 0, 0, 0,
                                FW_NORMAL, FALSE,
                                FALSE, FALSE, DEFAULT_CHARSET,
                                OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                                CLEARTYPE_QUALITY, DEFAULT_PITCH,
                                L"Material Icons");
      }
      HGDIOBJ old_font = SelectObject(dc, label_font);

      for (size_t index = 0; index < window->toolbar_buttons_.size(); ++index) {
        const auto& button = window->toolbar_buttons_[index];
        if (button.separator) {
          HPEN separator_pen = CreatePen(PS_SOLID, 1, RGB(70, 70, 70));
          HGDIOBJ old_separator_pen = SelectObject(dc, separator_pen);
          MoveToEx(dc, button.rect.left, button.rect.top, nullptr);
          LineTo(dc, button.rect.left, button.rect.bottom);
          SelectObject(dc, old_separator_pen);
          DeleteObject(separator_pen);
          continue;
        }

        const bool hovered =
            static_cast<int>(index) == window->hovered_toolbar_button_index_;
        const bool pressed =
            static_cast<int>(index) == window->pressed_toolbar_button_index_;
        COLORREF fill_color = RGB(30, 30, 30);
        COLORREF border_color = RGB(30, 30, 30);
        COLORREF text_color = RGB(255, 255, 255);

        if (!button.enabled) {
          text_color = RGB(120, 120, 120);
        } else if (button.selected) {
          fill_color = RGB(41, 132, 255);
          border_color = RGB(41, 132, 255);
        } else if (button.destructive && hovered) {
          fill_color = RGB(122, 50, 50);
          border_color = RGB(170, 80, 80);
        } else if (pressed) {
          fill_color = RGB(74, 74, 74);
          border_color = RGB(108, 108, 108);
        } else if (hovered) {
          fill_color = RGB(58, 58, 58);
          border_color = RGB(92, 92, 92);
        }

        HBRUSH button_brush = CreateSolidBrush(fill_color);
        HPEN button_pen = CreatePen(PS_SOLID, 1, border_color);
        HGDIOBJ old_button_brush = SelectObject(dc, button_brush);
        HGDIOBJ old_button_pen = SelectObject(dc, button_pen);
        RoundRect(dc, button.rect.left, button.rect.top, button.rect.right,
                  button.rect.bottom, window->toolbar_button_corner_radius_,
                  window->toolbar_button_corner_radius_);
        SelectObject(dc, old_button_brush);
        SelectObject(dc, old_button_pen);
        DeleteObject(button_brush);
        DeleteObject(button_pen);

        SetTextColor(dc, text_color);
        RECT text_rect = button.rect;
        if (use_material_icons && icon_font != nullptr &&
            button.icon_codepoint != 0) {
          const std::wstring glyph = CodepointToWide(button.icon_codepoint);
          SelectObject(dc, icon_font);
          DrawTextW(dc, glyph.c_str(), static_cast<int>(glyph.size()),
                    &text_rect, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
          SelectObject(dc, label_font);
        } else {
          DrawTextW(dc, button.label.c_str(),
                    static_cast<int>(button.label.size()), &text_rect,
                    DT_CENTER | DT_VCENTER | DT_SINGLELINE);
        }
      }

      SelectObject(dc, old_font);
      if (icon_font != nullptr) {
        DeleteObject(icon_font);
      }
      EndPaint(hwnd, &paint);
      return 0;
    }
    case WM_DESTROY:
      if (window != nullptr && window->toolbar_window_ == hwnd) {
        window->toolbar_window_ = nullptr;
        window->hovered_toolbar_button_index_ = -1;
        window->pressed_toolbar_button_index_ = -1;
      }
      return 0;
  }

  return DefWindowProc(hwnd, message, wparam, lparam);
}

void FlutterWindow::SetWindowExcludedFromCapture(bool enabled) {
  const HWND window = GetHandle();
  if (window == nullptr) {
    return;
  }

  SetWindowDisplayAffinity(window,
                           enabled ? WDA_EXCLUDEFROMCAPTURE : WDA_NONE);
}

void FlutterWindow::ShowScrollStopButton(const RECT& bounds) {
  const HWND owner = GetHandle();
  if (owner == nullptr) {
    return;
  }

  const int width = std::max(static_cast<int>(bounds.right - bounds.left), 1);
  const int height =
      std::max(static_cast<int>(bounds.bottom - bounds.top), 1);
  const HINSTANCE instance = GetModuleHandle(nullptr);

  WNDCLASSW window_class{};
  window_class.lpfnWndProc = FlutterWindow::ScrollStopWindowProc;
  window_class.hInstance = instance;
  window_class.lpszClassName = kScrollStopWindowClassName;
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  RegisterClassW(&window_class);

  if (scroll_stop_window_ == nullptr || !IsWindow(scroll_stop_window_)) {
    scroll_stop_window_ = CreateWindowExW(
        WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
        kScrollStopWindowClassName, L"",
        WS_POPUP | WS_CLIPSIBLINGS | WS_CLIPCHILDREN, bounds.left, bounds.top,
        width, height, owner, nullptr, instance, this);
    if (scroll_stop_window_ == nullptr) {
      return;
    }
  } else {
    SetWindowPos(scroll_stop_window_, HWND_TOPMOST, bounds.left, bounds.top,
                 width, height,
                 SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_SHOWWINDOW);
  }

  scroll_stop_hovered_ = false;
  ApplyRoundedWindowRegion(scroll_stop_window_, width, height,
                           kScrollStopCornerRadius);
  SetWindowDisplayAffinity(scroll_stop_window_, WDA_EXCLUDEFROMCAPTURE);
  ShowWindow(scroll_stop_window_, SW_SHOWNOACTIVATE);
  InvalidateRect(scroll_stop_window_, nullptr, TRUE);
  UpdateWindow(scroll_stop_window_);
}

void FlutterWindow::HideScrollStopButton() {
  if (scroll_stop_window_ != nullptr && IsWindow(scroll_stop_window_)) {
    DestroyWindow(scroll_stop_window_);
  }
  scroll_stop_window_ = nullptr;
  scroll_stop_hovered_ = false;
}

void FlutterWindow::HandleScrollStopButtonClick() {
  if (window_channel_) {
    window_channel_->InvokeMethod(
        "onScrollCaptureDone", std::make_unique<flutter::EncodableValue>());
  }
}

LRESULT CALLBACK FlutterWindow::ScrollStopWindowProc(HWND hwnd, UINT message,
                                                     WPARAM wparam,
                                                     LPARAM lparam) noexcept {
  FlutterWindow* window = nullptr;
  if (message == WM_NCCREATE) {
    auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    window = static_cast<FlutterWindow*>(create->lpCreateParams);
    SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(window));
  } else {
    window =
        reinterpret_cast<FlutterWindow*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));
  }

  switch (message) {
    case WM_MOUSEACTIVATE:
      return MA_NOACTIVATE;
    case WM_SETCURSOR:
      SetCursor(LoadCursor(nullptr, IDC_HAND));
      return TRUE;
    case WM_MOUSEMOVE:
      if (window != nullptr && !window->scroll_stop_hovered_) {
        window->scroll_stop_hovered_ = true;
        TRACKMOUSEEVENT track_event{};
        track_event.cbSize = sizeof(track_event);
        track_event.dwFlags = TME_LEAVE;
        track_event.hwndTrack = hwnd;
        TrackMouseEvent(&track_event);
        InvalidateRect(hwnd, nullptr, TRUE);
      }
      return 0;
    case WM_MOUSELEAVE:
      if (window != nullptr) {
        window->scroll_stop_hovered_ = false;
        InvalidateRect(hwnd, nullptr, TRUE);
      }
      return 0;
    case WM_LBUTTONUP:
      if (window != nullptr) {
        window->HandleScrollStopButtonClick();
        return 0;
      }
      return 0;
    case WM_PAINT: {
      PAINTSTRUCT paint{};
      HDC dc = BeginPaint(hwnd, &paint);
      RECT client_rect{};
      GetClientRect(hwnd, &client_rect);

      const COLORREF fill_color = window != nullptr && window->scroll_stop_hovered_
                                      ? RGB(86, 86, 86)
                                      : RGB(62, 62, 62);
      const COLORREF border_color = RGB(150, 150, 150);
      const COLORREF text_color = RGB(255, 255, 255);

      HBRUSH fill_brush = CreateSolidBrush(fill_color);
      HPEN border_pen = CreatePen(PS_SOLID, 1, border_color);
      HGDIOBJ old_brush = SelectObject(dc, fill_brush);
      HGDIOBJ old_pen = SelectObject(dc, border_pen);
      RoundRect(dc, client_rect.left, client_rect.top, client_rect.right,
                client_rect.bottom, kScrollStopCornerRadius * 2,
                kScrollStopCornerRadius * 2);
      SelectObject(dc, old_brush);
      SelectObject(dc, old_pen);
      DeleteObject(fill_brush);
      DeleteObject(border_pen);

      SetBkMode(dc, TRANSPARENT);
      SetTextColor(dc, text_color);
      HFONT font = static_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
      HGDIOBJ old_font = SelectObject(dc, font);
      DrawTextW(dc, L"Done", -1, &client_rect,
                DT_CENTER | DT_VCENTER | DT_SINGLELINE);
      SelectObject(dc, old_font);
      EndPaint(hwnd, &paint);
      return 0;
    }
    case WM_DESTROY:
      if (window != nullptr && window->scroll_stop_window_ == hwnd) {
        window->scroll_stop_window_ = nullptr;
        window->scroll_stop_hovered_ = false;
      }
      return 0;
  }

  return DefWindowProc(hwnd, message, wparam, lparam);
}

void FlutterWindow::SetTransparentBackground(bool enabled) {
  if (transparent_background_enabled_ == enabled) {
    return;
  }

  ExtendFrameIntoClientArea(GetHandle(), enabled);
  ApplyTransparentAccent(GetHandle(), enabled);
  transparent_background_enabled_ = enabled;
}

void FlutterWindow::SetWindowOpacity(BYTE alpha) {
  const HWND window = GetHandle();
  if (window == nullptr) {
    return;
  }

  LONG_PTR ex_style = GetWindowLongPtr(window, GWL_EXSTYLE);
  if ((ex_style & WS_EX_LAYERED) == 0) {
    ex_style |= WS_EX_LAYERED;
    SetWindowLongPtr(window, GWL_EXSTYLE, ex_style);
  }
  SetLayeredWindowAttributes(window, 0, alpha, LWA_ALPHA);
}

void FlutterWindow::DisableLayeredWindowIfTransparent() {
  const HWND window = GetHandle();
  if (window == nullptr || !transparent_background_enabled_) {
    return;
  }

  LONG_PTR ex_style = GetWindowLongPtr(window, GWL_EXSTYLE);
  if ((ex_style & WS_EX_LAYERED) == 0) {
    return;
  }

  ex_style &= ~WS_EX_LAYERED;
  SetWindowLongPtr(window, GWL_EXSTYLE, ex_style);
  SetWindowPos(window, nullptr, 0, 0, 0, 0,
               SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                   SWP_NOOWNERZORDER | SWP_NOACTIVATE);
}

LRESULT CALLBACK FlutterWindow::OverlayDismissMouseProc(int nCode,
                                                        WPARAM wparam,
                                                        LPARAM lparam) noexcept {
  FlutterWindow* window = g_overlay_dismiss_target;
  if (nCode == HC_ACTION && window != nullptr &&
      window->overlay_dismiss_on_next_click_) {
    switch (wparam) {
      case WM_LBUTTONDOWN:
      case WM_RBUTTONDOWN:
      case WM_MBUTTONDOWN:
      case WM_XBUTTONDOWN:
        window->overlay_dismiss_on_next_click_ = false;
        PostMessage(window->GetHandle(), kOverlayPassthroughClickMessage, 0, 0);
        break;
      default:
        break;
    }
  }

  return CallNextHookEx(window != nullptr ? window->overlay_dismiss_click_hook_
                                          : nullptr,
                        nCode, wparam, lparam);
}

void FlutterWindow::StopOverlayDismissOnNextClickMonitor() {
  overlay_dismiss_on_next_click_ = false;
  if (overlay_dismiss_click_hook_ != nullptr) {
    UnhookWindowsHookEx(overlay_dismiss_click_hook_);
    overlay_dismiss_click_hook_ = nullptr;
  }
  if (g_overlay_dismiss_target == this) {
    g_overlay_dismiss_target = nullptr;
  }
}

void FlutterWindow::SetOverlayDismissOnNextClick(bool enabled) {
  if (!enabled) {
    StopOverlayDismissOnNextClickMonitor();
    return;
  }

  overlay_dismiss_on_next_click_ = true;
  g_overlay_dismiss_target = this;
  if (overlay_dismiss_click_hook_ == nullptr) {
    overlay_dismiss_click_hook_ =
        SetWindowsHookExW(WH_MOUSE_LL, OverlayDismissMouseProc, nullptr, 0);
    if (overlay_dismiss_click_hook_ == nullptr) {
      overlay_dismiss_on_next_click_ = false;
      if (g_overlay_dismiss_target == this) {
        g_overlay_dismiss_target = nullptr;
      }
    }
  }
}

void FlutterWindow::HandleOverlayPassthroughClick() {
  StopOverlayDismissOnNextClickMonitor();
  if (window_channel_) {
    window_channel_->InvokeMethod(
        "onOverlayPassthroughClick",
        std::make_unique<flutter::EncodableValue>());
  }
}

void FlutterWindow::SetHostedFlutterViewVisible(bool visible) {
  if (!flutter_controller_ || !flutter_controller_->view()) {
    return;
  }

  const HWND flutter_view = flutter_controller_->view()->GetNativeWindow();
  if (flutter_view == nullptr) {
    return;
  }

  ShowWindow(flutter_view, visible ? SW_SHOWNA : SW_HIDE);
  SetWindowPos(flutter_view, nullptr, 0, 0, 0, 0,
               (visible ? SWP_SHOWWINDOW : SWP_HIDEWINDOW) | SWP_NOMOVE |
                   SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
}

void FlutterWindow::SetMousePassthrough(bool enabled) {
  const HWND window = GetHandle();
  if (window == nullptr) {
    return;
  }

  mouse_passthrough_enabled_ = enabled;
  if (!enabled) {
    StopOverlayDismissOnNextClickMonitor();
  }

  LONG_PTR ex_style = GetWindowLongPtr(window, GWL_EXSTYLE);
  if (enabled) {
    ex_style |= WS_EX_TRANSPARENT;
  } else {
    ex_style &= ~WS_EX_TRANSPARENT;
  }
  SetWindowLongPtr(window, GWL_EXSTYLE, ex_style);
  SetWindowPos(window, nullptr, 0, 0, 0, 0,
               SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                   SWP_NOOWNERZORDER | SWP_NOACTIVATE);
}

void FlutterWindow::ActivateAppWindow() {
  const HWND window = GetHandle();
  if (window == nullptr) {
    return;
  }

  SetWindowCloak(window, false);
  ShowWindow(window, SW_SHOW);
  SetHostedFlutterViewVisible(true);
  FlushPendingToolbarPanel();
  BringWindowToTop(window);
  SetForegroundWindow(window);
  SetActiveWindow(window);
  SetFocus(window);
}

void FlutterWindow::StopEscMonitor() {
  if (!esc_hotkey_registered_) {
    return;
  }

  UnregisterHotKey(GetHandle(), kEscHotkeyId);
  esc_hotkey_registered_ = false;
}

LRESULT FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == kOverlayPassthroughClickMessage) {
    HandleOverlayPassthroughClick();
    return 0;
  }

  if (message == WM_HOTKEY && wparam == kEscHotkeyId) {
    if (window_channel_) {
      window_channel_->InvokeMethod(
          "onEscPressed", std::make_unique<flutter::EncodableValue>());
    }
    return 0;
  }

  if (message == WM_NCCALCSIZE && custom_frame_active_) {
    return 0;
  }

  if (message == WM_NCHITTEST && mouse_passthrough_enabled_) {
    return HTTRANSPARENT;
  }

  if (message == WM_NCHITTEST && custom_frame_active_) {
    return HTCLIENT;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_MOVE:
    case WM_SIZE:
    case WM_WINDOWPOSCHANGED:
      RefreshToolbarPanelIfNeeded();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
