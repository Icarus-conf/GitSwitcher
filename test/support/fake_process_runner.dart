import 'package:git_switcher/src/platform/process_runner.dart';

/// Records every command and replies from a canned map.
///
/// Keys are the full command line joined with single spaces, e.g.
/// `/opt/homebrew/bin/gh auth switch --hostname github.com --user octocat`.
class FakeProcessRunner implements ProcessRunner {
  FakeProcessRunner({
    Map<String, CommandResult>? responses,
    this.fallback = const CommandResult(0, '', ''),
  }) : responses = responses ?? {};

  final Map<String, CommandResult> responses;
  final CommandResult fallback;

  /// Every command line this runner was asked to execute, in order.
  final List<String> calls = [];

  @override
  Future<CommandResult> run(String executable, List<String> arguments) async {
    final commandLine = [executable, ...arguments].join(' ');
    calls.add(commandLine);
    return responses[commandLine] ?? fallback;
  }
}
