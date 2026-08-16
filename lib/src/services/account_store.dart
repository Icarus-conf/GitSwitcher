import 'dart:convert';
import 'dart:io';

import '../models/account.dart';
import '../models/app_config.dart';

/// Reads and writes the app's own account configuration.
///
/// A corrupt config must never block startup, so [load] quarantines an
/// unreadable file and returns an empty list rather than throwing.
class AccountStore {
  AccountStore(this._file);

  final File _file;

  String get path => _file.path;

  /// Callers append to the returned list before saving it back, so this must
  /// hand out a growable copy. [AppConfig] defaults to a `const []`, which
  /// would throw on the first save the app ever performs.
  Future<List<Account>> load() async =>
      List<Account>.of((await loadConfig()).accounts);

  Future<void> save(List<Account> accounts) async {
    final config = await loadConfig();
    await saveConfig(config.copyWith(accounts: accounts));
  }

  /// Reads the whole config. A version 1 file (accounts only) is migrated by
  /// [AppConfig.fromJson] defaulting the fields it does not contain.
  Future<AppConfig> loadConfig() async {
    if (!await _file.exists()) return const AppConfig();

    try {
      final data = jsonDecode(await _file.readAsString());
      return AppConfig.fromJson(data as Map<String, dynamic>);
    } catch (_) {
      await _quarantine();
      return const AppConfig();
    }
  }

  Future<void> saveConfig(AppConfig config) async {
    await _file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await _file.writeAsString(encoder.convert(config.toJson()));
  }

  Future<void> _quarantine() async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    await _file.rename('${_file.path}.corrupt-$stamp');
  }
}
