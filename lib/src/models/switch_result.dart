/// The outcome of one step of a switch.
enum StepStatus {
  /// The step ran and changed (or already matched) the desired state.
  ok,

  /// The step had nothing to do because the account did not configure it.
  skipped,

  /// The step could not complete. [StepResult.message] explains why.
  failed,
}

class StepResult {
  const StepResult(this.name, this.status, {this.message});

  const StepResult.ok(String name) : this(name, StepStatus.ok);

  const StepResult.skipped(String name, String message)
      : this(name, StepStatus.skipped, message: message);

  const StepResult.failed(String name, String message)
      : this(name, StepStatus.failed, message: message);

  /// Human-readable step label, e.g. `gh`, `git identity`, `ssh`.
  final String name;
  final StepStatus status;
  final String? message;

  @override
  String toString() => 'StepResult($name, $status, $message)';
}

/// The aggregate outcome of switching to one account.
///
/// Steps run independently: a failure in one does not prevent the others from
/// running, so a partial switch is always visible rather than silent.
class SwitchResult {
  const SwitchResult(this.ghUsername, this.steps);

  final String ghUsername;
  final List<StepResult> steps;

  List<StepResult> get failedSteps =>
      steps.where((s) => s.status == StepStatus.failed).toList();

  bool get anyFailed => failedSteps.isNotEmpty;

  bool get allOk => !anyFailed;
}
