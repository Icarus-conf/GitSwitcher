import 'dart:io';

class CommandResult {
  const CommandResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get ok => exitCode == 0;

  /// The most useful error text available, for surfacing to the user.
  String get errorText =>
      stderr.isNotEmpty ? stderr : 'exited with code $exitCode';

  @override
  String toString() => 'CommandResult($exitCode, $stdout, $stderr)';
}

/// Indirection over process execution so every consumer is unit-testable.
abstract class ProcessRunner {
  /// [environment] is added to this app's own environment.
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
  });
}

class RealProcessRunner implements ProcessRunner {
  const RealProcessRunner();

  @override
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
  }) async {
    final result =
        await Process.run(executable, arguments, environment: environment);
    return CommandResult(
      result.exitCode,
      (result.stdout as String).trim(),
      (result.stderr as String).trim(),
    );
  }
}
