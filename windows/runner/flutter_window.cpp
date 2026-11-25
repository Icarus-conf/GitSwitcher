#include "flutter_window.h"

#include <optional>

#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

namespace {
// Any id unique to this window; WM_HOTKEY reports it back.
constexpr int kMenuHotKeyId = 1;
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

  // Ctrl+Alt+G opens the tray menu from anywhere, like Ctrl+Option+Cmd+G on
  // macOS. WM_HOTKEY arrives at this window even while it is hidden. If
  // another app already owns the combination this fails quietly.
  hotkey_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "gitswitcher/hotkey",
          &flutter::StandardMethodCodec::GetInstance());
  ::RegisterHotKey(GetHandle(), kMenuHotKeyId,
                   MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, 'G');

  // GitSwitcher lives in the tray: the settings window stays hidden until it
  // is opened from the menu (window_manager shows it), so the template's
  // show-on-first-frame callback is deliberately not installed here.

  // Make sure a first frame is produced even though nothing is shown yet, so
  // window_manager's ready-to-show wait in main.dart completes.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  ::UnregisterHotKey(GetHandle(), kMenuHotKeyId);
  hotkey_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
    case WM_HOTKEY:
      if (wparam == kMenuHotKeyId && hotkey_channel_) {
        hotkey_channel_->InvokeMethod("pressed", nullptr);
        return 0;
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
