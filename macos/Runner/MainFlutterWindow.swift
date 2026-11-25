import Carbon.HIToolbox
import Cocoa
import FlutterMacOS
import ServiceManagement

// File-level, because a Carbon event handler is a C function pointer and cannot
// capture anything.
private var hotKeyChannel: FlutterMethodChannel?
private var hotKeyRef: EventHotKeyRef?

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerLaunchAtLogin(flutterViewController.engine.binaryMessenger)
    registerMenuHotKey(flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  /// ⌃⌥⌘G opens the menu from anywhere. Carbon's RegisterEventHotKey is the
  /// one global-shortcut API that needs no Accessibility permission.
  private func registerMenuHotKey(_ messenger: FlutterBinaryMessenger) {
    hotKeyChannel = FlutterMethodChannel(
      name: "gitswitcher/hotkey", binaryMessenger: messenger)

    var pressed = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, _ in
        hotKeyChannel?.invokeMethod("pressed", arguments: nil)
        return noErr
      },
      1, &pressed, nil, nil)

    let id = EventHotKeyID(signature: OSType(0x4753_5754), id: 1)  // 'GSWT'
    RegisterEventHotKey(
      UInt32(kVK_ANSI_G), UInt32(cmdKey | optionKey | controlKey), id,
      GetApplicationEventTarget(), 0, &hotKeyRef)
  }

  /// Open at login through macOS's own Login Items (SMAppService), so the
  /// user sees and controls it in System Settings like any other app.
  private func registerLaunchAtLogin(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "gitswitcher/launch_at_login", binaryMessenger: messenger)

    channel.setMethodCallHandler { call, result in
      guard #available(macOS 13.0, *) else {
        result(FlutterError(
          code: "unsupported", message: "Requires macOS 13 or later", details: nil))
        return
      }
      let service = SMAppService.mainApp

      switch call.method {
      case "isEnabled":
        result(service.status == .enabled)
      case "setEnabled":
        do {
          if call.arguments as? Bool == true {
            try service.register()
          } else {
            try service.unregister()
          }
          result(service.status == .enabled)
        } catch {
          result(FlutterError(
            code: "failed", message: error.localizedDescription, details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
