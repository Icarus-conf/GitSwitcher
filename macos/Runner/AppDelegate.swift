import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// GitSwitcher lives in the menu bar, not in a window. The settings window is
  /// hidden at launch and whenever the user closes it, so terminating with the
  /// last window would quit the app the moment it starts.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
