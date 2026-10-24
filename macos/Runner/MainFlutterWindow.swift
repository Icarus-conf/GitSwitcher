import Cocoa
import FlutterMacOS
import ServiceManagement

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerLaunchAtLogin(flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
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
