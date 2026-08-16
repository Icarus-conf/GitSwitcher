import 'package:window_manager/window_manager.dart';

/// Shows and hides the single Flutter window.
///
/// The app is an LSUIElement accessory, so it has no Dock icon to click and
/// must explicitly raise itself above whatever the user is working in.
class SettingsWindow {
  const SettingsWindow._();

  static Future<void> open() async {
    await windowManager.show();
    await windowManager.focus();
  }

  static Future<void> close() => windowManager.hide();
}
