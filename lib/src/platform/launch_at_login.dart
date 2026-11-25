import 'dart:io';

import 'package:flutter/services.dart';

import 'host.dart';
import 'process_runner.dart';

/// Opens the app at login.
///
/// macOS: Login Items through SMAppService (MainFlutterWindow.swift), so the
/// user sees and controls it in System Settings.
/// Windows: the per-user Run registry key, which is what Task Manager's
/// Startup apps tab lists and lets the user turn off.
class LaunchAtLogin {
  const LaunchAtLogin._();

  static const _channel = MethodChannel('gitswitcher/launch_at_login');

  static const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _valueName = 'GitSwitcher';
  static const ProcessRunner _runner = RealProcessRunner();

  static Future<bool> isEnabled() async {
    if (Host.current.isWindows) {
      return (await _runner.run('reg', ['query', _runKey, '/v', _valueName]))
          .ok;
    }
    return await _channel.invokeMethod<bool>('isEnabled') ?? false;
  }

  /// Returns the resulting state; throws [PlatformException] if the system
  /// refuses.
  static Future<bool> setEnabled(bool enabled) async {
    if (!Host.current.isWindows) {
      return await _channel.invokeMethod<bool>('setEnabled', enabled) ?? false;
    }

    final result = enabled
        ? await _runner.run('reg', [
            'add', _runKey, '/v', _valueName, '/t', 'REG_SZ',
            // Quoted, because the install folder may contain spaces.
            '/d', '"${Platform.resolvedExecutable}"', '/f',
          ])
        : await _runner.run('reg', ['delete', _runKey, '/v', _valueName, '/f']);
    if (!result.ok) {
      throw PlatformException(code: 'failed', message: result.errorText);
    }
    return isEnabled();
  }
}
