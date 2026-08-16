import 'dart:io';

import 'package:yaml/yaml.dart';

import '../models/switch_result.dart';
import '../platform/binary_locator.dart';
import '../platform/process_runner.dart';

/// The accounts the gh CLI knows about, and which one is active.
class GhAccounts {
  const GhAccounts(this.usernames, this.activeUsername);

  const GhAccounts.empty()
      : usernames = const [],
        activeUsername = null;

  final List<String> usernames;
  final String? activeUsername;
}

/// Reads gh's account state and switches the active account.
///
/// Discovery prefers `hosts.yml` because it is structured and stable;
/// `gh auth status` output is human-formatted and changes between releases,
/// so it is only a fallback.
class GhClient {
  GhClient({
    required ProcessRunner runner,
    required BinaryLocator locator,
    required File hostsFile,
  })  : _runner = runner,
        _locator = locator,
        _hostsFile = hostsFile;

  final ProcessRunner _runner;
  final BinaryLocator _locator;
  final File _hostsFile;

  static const String stepName = 'gh';
  static const String host = 'github.com';

  /// Whether the gh CLI can be found at all.
  ///
  /// The menu needs to tell "gh is missing" apart from "gh has no accounts" —
  /// they need very different advice.
  Future<bool> isInstalled() async {
    try {
      await _locator.locate('gh');
      return true;
    } on BinaryNotFoundException {
      return false;
    }
  }

  Future<GhAccounts> discover() async {
    if (await _hostsFile.exists()) {
      try {
        return _parseHostsYaml(await _hostsFile.readAsString());
      } catch (_) {
        // Fall through to the gh auth status fallback.
      }
    }
    return _discoverViaStatus();
  }

  GhAccounts _parseHostsYaml(String text) {
    final document = loadYaml(text);
    if (document is! YamlMap) return const GhAccounts.empty();

    final entry = document[host];
    if (entry is! YamlMap) return const GhAccounts.empty();

    final users = entry['users'];
    final usernames = users is YamlMap
        ? users.keys.map((key) => key.toString()).toList()
        : <String>[];

    return GhAccounts(usernames, entry['user']?.toString());
  }

  Future<GhAccounts> _discoverViaStatus() async {
    final String gh;
    try {
      gh = await _locator.locate('gh');
    } on BinaryNotFoundException {
      return const GhAccounts.empty();
    }

    final result = await _runner.run(gh, ['auth', 'status']);
    return parseAuthStatus('${result.stdout}\n${result.stderr}');
  }

  /// Parses `gh auth status` output.
  ///
  /// Each account is announced by a `Logged in to <host> account <name>` line
  /// and followed by an `Active account: true|false` line.
  static GhAccounts parseAuthStatus(String output) {
    final accountLine = RegExp(r'Logged in to \S+ account (\S+)');
    final usernames = <String>[];
    String? activeUsername;
    String? current;

    for (final line in output.split('\n')) {
      final match = accountLine.firstMatch(line);
      if (match != null) {
        current = match.group(1)!;
        usernames.add(current);
        continue;
      }
      if (current != null && line.contains('Active account: true')) {
        activeUsername = current;
      }
    }

    return GhAccounts(usernames, activeUsername);
  }

  Future<StepResult> switchTo(String username) async {
    final String gh;
    try {
      gh = await _locator.locate('gh');
    } on BinaryNotFoundException catch (error) {
      return StepResult.failed(stepName, error.toString());
    }

    final result = await _runner.run(
      gh,
      ['auth', 'switch', '--hostname', host, '--user', username],
    );

    return result.ok
        ? const StepResult.ok(stepName)
        : StepResult.failed(stepName, result.errorText);
  }
}
