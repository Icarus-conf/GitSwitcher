import 'package:flutter/services.dart';

/// Opens the app at login via macOS Login Items. See MainFlutterWindow.swift.
class LaunchAtLogin {
  const LaunchAtLogin._();

  static const _channel = MethodChannel('gitswitcher/launch_at_login');

  static Future<bool> isEnabled() async =>
      await _channel.invokeMethod<bool>('isEnabled') ?? false;

  /// Returns the resulting state; throws [PlatformException] if macOS refuses.
  static Future<bool> setEnabled(bool enabled) async =>
      await _channel.invokeMethod<bool>('setEnabled', enabled) ?? false;
}
