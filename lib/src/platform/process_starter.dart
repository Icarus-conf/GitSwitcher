import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A long-running process whose output is consumed while it runs.
class StartedProcess {
  StartedProcess({
    required this.lines,
    required this.exitCode,
    required this.kill,
  });

  /// stdout and stderr interleaved, one event per line.
  final Stream<String> lines;

  final Future<int> exitCode;
  final void Function() kill;
}

/// Starts processes whose output must be read before they finish.
///
/// Separate from [ProcessRunner] on purpose: `Process.run` buffers everything
/// until exit, which is useless for a login flow that prints a code and then
/// waits for the user.
abstract class ProcessStarter {
  Future<StartedProcess> start(String executable, List<String> arguments);
}

class RealProcessStarter implements ProcessStarter {
  const RealProcessStarter();

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments,
  ) async {
    final process = await Process.start(executable, arguments);
    final controller = StreamController<String>.broadcast();

    var openStreams = 2;
    void closeOne() {
      if (--openStreams == 0 && !controller.isClosed) controller.close();
    }

    for (final stream in [process.stdout, process.stderr]) {
      stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(controller.add, onDone: closeOne, onError: (_) => closeOne());
    }

    return StartedProcess(
      lines: controller.stream,
      exitCode: process.exitCode,
      kill: () => process.kill(),
    );
  }
}
