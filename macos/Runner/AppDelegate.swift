import Cocoa
import FlutterMacOS
import UserNotifications

@main
class AppDelegate: FlutterAppDelegate, UNUserNotificationCenterDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    UNUserNotificationCenter.current().delegate = self
    super.applicationDidFinishLaunching(notification)
  }

  /// Show banners even while GitSwitcher counts as the active app — it is, the
  /// moment you pick an account from its menu, which is exactly when the
  /// switch notification fires.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
      @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // .banner and .list arrived in macOS 11; the app still runs on 10.15,
    // where .alert is the same thing.
    if #available(macOS 11.0, *) {
      completionHandler([.banner, .list])
    } else {
      completionHandler([.alert])
    }
  }

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
