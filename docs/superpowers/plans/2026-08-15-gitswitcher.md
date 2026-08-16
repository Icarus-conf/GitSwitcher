# GitSwitcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu bar app that switches the active `gh` CLI account, the global git commit identity, and the `github.com` SSH identity in one click.

**Architecture:** All decision logic lives in plain Dart classes that take injected file paths and an injected `ProcessRunner`, so every rule is unit-testable without a real `gh`, a real `git`, or a real `~/.ssh/config`. The menu bar layer (`tray_manager`) and the settings window are thin shells over those classes. The app runs as a macOS accessory (`LSUIElement`) with the sandbox disabled, because reading `~/.config/gh/hosts.yml`, writing `~/.ssh/config`, and executing `gh` are all impossible inside the sandbox.

**Tech Stack:** Flutter 3.41.2 / Dart 3.11.0, `tray_manager` 0.5.3, `window_manager` 0.5.2, `path_provider` 2.1.6, `yaml` 3.1.3.

**Spec:** `docs/superpowers/specs/2026-08-15-gitswitcher-design.md`

## Global Constraints

- Dart package name is `git_switcher`; macOS product name is `GitSwitcher`; bundle id is `io.github.icarusconf.gitswitcher`.
- Flutter project lives at the repo root (`~/GitSwitcher`), which already contains `.git` and `docs/`.
- macOS is the only platform. Do not add iOS, Android, web, Linux, or Windows targets.
- `com.apple.security.app-sandbox` MUST be `false` in **both** `macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`. Every process-execution and file-write feature fails silently otherwise.
- Only the `github.com` host is supported. Ignore all other hosts in `hosts.yml`.
- The SSH managed-block markers are exactly `# >>> GitSwitcher (managed — do not edit)` and `# <<< GitSwitcher`. Note the em dash (—) in the opening marker.
- Never write outside the SSH managed block. Content before and after the markers is preserved byte-for-byte.
- Tests run with `flutter test`. All test files import `package:flutter_test/flutter_test.dart`.
- Every step that touches the filesystem in a test uses a temp directory created in `setUp` and deleted in `tearDown`. No test ever touches the real `~/.ssh` or `~/.config/gh`.
- Commit after every task.

---

### Task 1: Project scaffold and macOS accessory configuration

**Files:**
- Create: entire Flutter scaffold at repo root (via `flutter create`)
- Modify: `pubspec.yaml`
- Modify: `macos/Runner/DebugProfile.entitlements`
- Modify: `macos/Runner/Release.entitlements`
- Modify: `macos/Runner/Info.plist`
- Modify: `macos/Runner/Configs/AppInfo.xcconfig`
- Create: `assets/tray_icon.png`
- Create: `tool/generate_tray_icon.py`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: nothing.
- Produces: a buildable Flutter macOS app named `GitSwitcher.app` with no Dock icon, sandbox disabled, and `assets/tray_icon.png` bundled as a Flutter asset.

- [ ] **Step 1: Create the Flutter project in place**

The repo root is not empty (it has `.git` and `docs/`), so `flutter create` must target `.` with an explicit project name — the directory name `GitSwitcher` is not a valid Dart package identifier.

```bash
cd ~/GitSwitcher
flutter create --platforms=macos --org io.github.icarusconf --project-name git_switcher .
```

- [ ] **Step 2: Verify the untouched scaffold builds**

```bash
flutter build macos --debug
```

Expected: build succeeds, producing `build/macos/Build/Products/Debug/git_switcher.app`.

- [ ] **Step 3: Add dependencies**

```bash
flutter pub add tray_manager:^0.5.3 window_manager:^0.5.2 path_provider:^2.1.6 yaml:^3.1.3
```

Do not add `menu_base` — `tray_manager` re-exports it.

- [ ] **Step 4: Disable the sandbox in both entitlements files**

In `macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`, change the `com.apple.security.app-sandbox` value from `<true/>` to `<false/>`. Leave every other key alone (`DebugProfile.entitlements` also needs `com.apple.security.cs.allow-jit` and `com.apple.security.network.server` for the Dart VM to attach).

`macos/Runner/Release.entitlements` should end up as:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<false/>
</dict>
</plist>
```

- [ ] **Step 5: Make the app an accessory (no Dock icon)**

Add this key/value pair inside the top-level `<dict>` of `macos/Runner/Info.plist`:

```xml
	<key>LSUIElement</key>
	<true/>
```

- [ ] **Step 6: Set the product name**

In `macos/Runner/Configs/AppInfo.xcconfig`, change the product name line to:

```
PRODUCT_NAME = GitSwitcher
```

Leave `PRODUCT_BUNDLE_IDENTIFIER` as generated (`io.github.icarusconf.gitswitcher`).

- [ ] **Step 7: Write the tray icon generator**

The menu bar icon must be a macOS *template* image: pure black pixels plus an alpha channel, so macOS recolors it automatically for light and dark menu bars. Create `tool/generate_tray_icon.py`:

```python
"""Generates assets/tray_icon.png — a black-on-alpha macOS template image.

The glyph is two opposing horizontal arrows, reading as "switch".
Rendered at 4x then downsampled so the edges are smooth.
"""

from PIL import Image, ImageDraw

SIZE = 36  # 2x of the 18pt menu bar icon size
SCALE = 4
W = SIZE * SCALE

img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

bar = 3 * SCALE          # shaft thickness
head = 7 * SCALE         # arrowhead half-height
left = 5 * SCALE
right = W - 5 * SCALE
top_y = 12 * SCALE       # upper arrow centre
bot_y = 24 * SCALE       # lower arrow centre

# Upper arrow: shaft pointing right, head on the right.
d.rectangle([left, top_y - bar // 2, right - head, top_y + bar // 2], fill=(0, 0, 0, 255))
d.polygon(
    [(right - head, top_y - head), (right, top_y), (right - head, top_y + head)],
    fill=(0, 0, 0, 255),
)

# Lower arrow: shaft pointing left, head on the left.
d.rectangle([left + head, bot_y - bar // 2, right, bot_y + bar // 2], fill=(0, 0, 0, 255))
d.polygon(
    [(left + head, bot_y - head), (left, bot_y), (left + head, bot_y + head)],
    fill=(0, 0, 0, 255),
)

img.resize((SIZE, SIZE), Image.LANCZOS).save("assets/tray_icon.png")
print("wrote assets/tray_icon.png")
```

- [ ] **Step 8: Generate the icon**

```bash
mkdir -p assets && python3 tool/generate_tray_icon.py
```

Expected: `wrote assets/tray_icon.png`. Confirm the file exists and is 36x36:

```bash
sips -g pixelWidth -g pixelHeight assets/tray_icon.png
```

- [ ] **Step 9: Register the asset**

In `pubspec.yaml`, under the `flutter:` section, replace the commented-out `assets:` block with:

```yaml
  assets:
    - assets/tray_icon.png
```

- [ ] **Step 10: Verify the configured app still builds**

```bash
flutter build macos --debug
```

Expected: build succeeds, producing `build/macos/Build/Products/Debug/GitSwitcher.app`.

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "chore: scaffold Flutter macOS app with accessory config and tray icon"
```

---

### Task 2: Domain models

**Files:**
- Create: `lib/src/models/account.dart`
- Create: `lib/src/models/switch_result.dart`
- Test: `test/models/account_test.dart`
- Test: `test/models/switch_result_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `class Account` with fields `String ghUsername, label, gitName, gitEmail, sshKeyPath` (all `String`, non-null, defaulting to `''` except `ghUsername` which is required); getters `String get displayName`, `bool get isComplete`; `Account copyWith({String? label, String? gitName, String? gitEmail, String? sshKeyPath})`; `factory Account.fromJson(Map<String, dynamic>)`; `Map<String, dynamic> toJson()`; value equality.
  - `enum StepStatus { ok, skipped, failed }`
  - `class StepResult` with `final String name`, `final StepStatus status`, `final String? message`; named constructors `StepResult.ok(String name)`, `StepResult.skipped(String name, String message)`, `StepResult.failed(String name, String message)`.
  - `class SwitchResult` with `final String ghUsername`, `final List<StepResult> steps`; getters `bool get anyFailed`, `bool get allOk`.

- [ ] **Step 1: Write the failing tests for `Account`**

Create `test/models/account_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/models/account.dart';

void main() {
  group('Account.displayName', () {
    test('uses the label when it is set', () {
      const account = Account(ghUsername: 'octocat', label: 'Work');
      expect(account.displayName, 'Work');
    });

    test('falls back to the gh username when the label is empty', () {
      const account = Account(ghUsername: 'octocat');
      expect(account.displayName, 'octocat');
    });
  });

  group('Account.isComplete', () {
    test('is false when both git email and ssh key are empty', () {
      const account = Account(ghUsername: 'octocat');
      expect(account.isComplete, isFalse);
    });

    test('is true when only the git email is set', () {
      const account = Account(ghUsername: 'octocat', gitEmail: 'a@b.com');
      expect(account.isComplete, isTrue);
    });

    test('is true when only the ssh key is set', () {
      const account = Account(ghUsername: 'octocat', sshKeyPath: '/k');
      expect(account.isComplete, isTrue);
    });
  });

  group('Account JSON', () {
    test('round-trips every field', () {
      const account = Account(
        ghUsername: 'octocat',
        label: 'Work',
        gitName: 'Octo Cat',
        gitEmail: 'octo@example.com',
        sshKeyPath: '/Users/me/.ssh/id_work',
      );
      expect(Account.fromJson(account.toJson()), account);
    });

    test('defaults missing optional fields to empty strings', () {
      final account = Account.fromJson({'ghUsername': 'octocat'});
      expect(account.ghUsername, 'octocat');
      expect(account.label, '');
      expect(account.gitName, '');
      expect(account.gitEmail, '');
      expect(account.sshKeyPath, '');
    });
  });

  test('copyWith replaces only the named fields', () {
    const account = Account(ghUsername: 'octocat', label: 'Work');
    final updated = account.copyWith(gitEmail: 'octo@example.com');
    expect(updated.ghUsername, 'octocat');
    expect(updated.label, 'Work');
    expect(updated.gitEmail, 'octo@example.com');
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
flutter test test/models/account_test.dart
```

Expected: FAIL — `Error: Couldn't resolve the package 'git_switcher'` or `account.dart` not found.

- [ ] **Step 3: Implement `Account`**

Create `lib/src/models/account.dart`:

```dart
/// A GitHub account the user can switch to.
///
/// [ghUsername] is the primary key and comes from the gh CLI. Every other
/// field is supplied by the user through Settings.
class Account {
  const Account({
    required this.ghUsername,
    this.label = '',
    this.gitName = '',
    this.gitEmail = '',
    this.sshKeyPath = '',
  });

  final String ghUsername;
  final String label;
  final String gitName;
  final String gitEmail;
  final String sshKeyPath;

  /// What the menu shows for this account.
  String get displayName => label.isEmpty ? ghUsername : label;

  /// An account is incomplete until it can change at least one thing beyond
  /// the gh CLI's own active account.
  bool get isComplete => gitEmail.isNotEmpty || sshKeyPath.isNotEmpty;

  Account copyWith({
    String? label,
    String? gitName,
    String? gitEmail,
    String? sshKeyPath,
  }) {
    return Account(
      ghUsername: ghUsername,
      label: label ?? this.label,
      gitName: gitName ?? this.gitName,
      gitEmail: gitEmail ?? this.gitEmail,
      sshKeyPath: sshKeyPath ?? this.sshKeyPath,
    );
  }

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      ghUsername: json['ghUsername'] as String,
      label: json['label'] as String? ?? '',
      gitName: json['gitName'] as String? ?? '',
      gitEmail: json['gitEmail'] as String? ?? '',
      sshKeyPath: json['sshKeyPath'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'ghUsername': ghUsername,
        'label': label,
        'gitName': gitName,
        'gitEmail': gitEmail,
        'sshKeyPath': sshKeyPath,
      };

  @override
  bool operator ==(Object other) =>
      other is Account &&
      other.ghUsername == ghUsername &&
      other.label == label &&
      other.gitName == gitName &&
      other.gitEmail == gitEmail &&
      other.sshKeyPath == sshKeyPath;

  @override
  int get hashCode =>
      Object.hash(ghUsername, label, gitName, gitEmail, sshKeyPath);

  @override
  String toString() => 'Account($ghUsername, label: $label)';
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
flutter test test/models/account_test.dart
```

Expected: PASS, 8 tests.

- [ ] **Step 5: Write the failing tests for the result types**

Create `test/models/switch_result_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/models/switch_result.dart';

void main() {
  test('StepResult.ok carries no message', () {
    final step = StepResult.ok('gh');
    expect(step.name, 'gh');
    expect(step.status, StepStatus.ok);
    expect(step.message, isNull);
  });

  test('StepResult.skipped carries its reason', () {
    final step = StepResult.skipped('ssh', 'no SSH key configured');
    expect(step.status, StepStatus.skipped);
    expect(step.message, 'no SSH key configured');
  });

  test('StepResult.failed carries its reason', () {
    final step = StepResult.failed('gh', 'gh not found');
    expect(step.status, StepStatus.failed);
    expect(step.message, 'gh not found');
  });

  test('SwitchResult is allOk when nothing failed', () {
    final result = SwitchResult('octocat', [
      StepResult.ok('gh'),
      StepResult.skipped('ssh', 'no SSH key configured'),
    ]);
    expect(result.allOk, isTrue);
    expect(result.anyFailed, isFalse);
  });

  test('SwitchResult reports failure when any step failed', () {
    final result = SwitchResult('octocat', [
      StepResult.ok('gh'),
      StepResult.failed('ssh', 'markers malformed'),
    ]);
    expect(result.allOk, isFalse);
    expect(result.anyFailed, isTrue);
    expect(result.failedSteps.single.name, 'ssh');
  });
}
```

- [ ] **Step 6: Run the tests to verify they fail**

```bash
flutter test test/models/switch_result_test.dart
```

Expected: FAIL — `switch_result.dart` not found.

- [ ] **Step 7: Implement the result types**

Create `lib/src/models/switch_result.dart`:

```dart
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
```

- [ ] **Step 8: Run the tests to verify they pass**

```bash
flutter test test/models/switch_result_test.dart
```

Expected: PASS, 5 tests.

- [ ] **Step 9: Commit**

```bash
git add lib/src/models test/models
git commit -m "feat: add Account and SwitchResult domain models"
```

---

### Task 3: Process execution and binary resolution

**Files:**
- Create: `lib/src/platform/process_runner.dart`
- Create: `lib/src/platform/binary_locator.dart`
- Create: `test/support/fake_process_runner.dart`
- Test: `test/platform/binary_locator_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `class CommandResult` with `final int exitCode`, `final String stdout`, `final String stderr`, getter `bool get ok`.
  - `abstract class ProcessRunner` with `Future<CommandResult> run(String executable, List<String> arguments)`.
  - `class RealProcessRunner implements ProcessRunner`.
  - `typedef PathExists = bool Function(String path)`.
  - `const List<String> kBinarySearchDirs`.
  - `class BinaryNotFoundException implements Exception` with `final String name`.
  - `class BinaryLocator({required ProcessRunner runner, List<String> searchDirs, PathExists exists})` with `Future<String> locate(String name)`.
  - Test helper `class FakeProcessRunner implements ProcessRunner` with `Map<String, CommandResult> responses` keyed by the full command line joined with spaces, `List<String> calls` recording each command line, and `CommandResult fallback`.

- [ ] **Step 1: Implement `ProcessRunner` (no test — it is a thin wrapper over `Process.run`)**

Create `lib/src/platform/process_runner.dart`:

```dart
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
  Future<CommandResult> run(String executable, List<String> arguments);
}

class RealProcessRunner implements ProcessRunner {
  const RealProcessRunner();

  @override
  Future<CommandResult> run(String executable, List<String> arguments) async {
    final result = await Process.run(executable, arguments);
    return CommandResult(
      result.exitCode,
      (result.stdout as String).trim(),
      (result.stderr as String).trim(),
    );
  }
}
```

- [ ] **Step 2: Write the test double**

Create `test/support/fake_process_runner.dart`:

```dart
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
```

- [ ] **Step 3: Write the failing tests for `BinaryLocator`**

Create `test/platform/binary_locator_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/platform/binary_locator.dart';
import 'package:git_switcher/src/platform/process_runner.dart';

import '../support/fake_process_runner.dart';

void main() {
  test('returns the first search directory that contains the binary', () async {
    final locator = BinaryLocator(
      runner: FakeProcessRunner(),
      searchDirs: const ['/opt/homebrew/bin', '/usr/local/bin'],
      exists: (path) => path == '/usr/local/bin/gh',
    );

    expect(await locator.locate('gh'), '/usr/local/bin/gh');
  });

  test('prefers an earlier search directory over a later one', () async {
    final locator = BinaryLocator(
      runner: FakeProcessRunner(),
      searchDirs: const ['/opt/homebrew/bin', '/usr/local/bin'],
      exists: (_) => true,
    );

    expect(await locator.locate('gh'), '/opt/homebrew/bin/gh');
  });

  test('falls back to a login shell when no search directory matches', () async {
    final runner = FakeProcessRunner(
      responses: {
        '/bin/zsh -lc which gh': const CommandResult(0, '/custom/bin/gh', ''),
      },
    );
    final locator = BinaryLocator(
      runner: runner,
      searchDirs: const ['/opt/homebrew/bin'],
      exists: (path) => path == '/custom/bin/gh',
    );

    expect(await locator.locate('gh'), '/custom/bin/gh');
    expect(runner.calls, ['/bin/zsh -lc which gh']);
  });

  test('throws when the binary is nowhere to be found', () async {
    final locator = BinaryLocator(
      runner: FakeProcessRunner(fallback: const CommandResult(1, '', '')),
      searchDirs: const ['/opt/homebrew/bin'],
      exists: (_) => false,
    );

    expect(
      () => locator.locate('gh'),
      throwsA(isA<BinaryNotFoundException>()),
    );
  });

  test('caches a resolved path instead of probing twice', () async {
    final runner = FakeProcessRunner(
      responses: {
        '/bin/zsh -lc which gh': const CommandResult(0, '/custom/bin/gh', ''),
      },
    );
    final locator = BinaryLocator(
      runner: runner,
      searchDirs: const [],
      exists: (path) => path == '/custom/bin/gh',
    );

    await locator.locate('gh');
    await locator.locate('gh');

    expect(runner.calls.length, 1);
  });

  test('the not-found message names the missing binary', () {
    expect(BinaryNotFoundException('gh').toString(), contains('gh'));
  });
}
```

- [ ] **Step 4: Run the tests to verify they fail**

```bash
flutter test test/platform/binary_locator_test.dart
```

Expected: FAIL — `binary_locator.dart` not found.

- [ ] **Step 5: Implement `BinaryLocator`**

Create `lib/src/platform/binary_locator.dart`:

```dart
import 'dart:io';

import 'process_runner.dart';

typedef PathExists = bool Function(String path);

/// Where CLI tools normally live on macOS, in probe order.
const List<String> kBinarySearchDirs = [
  '/opt/homebrew/bin',
  '/usr/local/bin',
  '/usr/bin',
];

class BinaryNotFoundException implements Exception {
  BinaryNotFoundException(this.name);

  final String name;

  @override
  String toString() =>
      '$name was not found. Install it, or make sure it is on your PATH.';
}

/// Resolves absolute paths to CLI tools.
///
/// A GUI app launched from Finder does not inherit the login shell's PATH, so
/// `Process.run('gh', ...)` fails inside a bundled `.app` even when `gh` works
/// perfectly in a terminal. Probing known directories first — and only then
/// paying for a login shell — keeps the common case fast.
class BinaryLocator {
  BinaryLocator({
    required ProcessRunner runner,
    List<String> searchDirs = kBinarySearchDirs,
    PathExists exists = _defaultExists,
  })  : _runner = runner,
        _searchDirs = searchDirs,
        _exists = exists;

  final ProcessRunner _runner;
  final List<String> _searchDirs;
  final PathExists _exists;
  final Map<String, String> _cache = {};

  static bool _defaultExists(String path) => File(path).existsSync();

  /// Throws [BinaryNotFoundException] if [name] cannot be resolved.
  Future<String> locate(String name) async {
    final cached = _cache[name];
    if (cached != null) return cached;

    for (final dir in _searchDirs) {
      final candidate = '$dir/$name';
      if (_exists(candidate)) {
        _cache[name] = candidate;
        return candidate;
      }
    }

    final result = await _runner.run('/bin/zsh', ['-lc', 'which $name']);
    final resolved = result.stdout.trim();
    if (result.ok && resolved.isNotEmpty && _exists(resolved)) {
      _cache[name] = resolved;
      return resolved;
    }

    throw BinaryNotFoundException(name);
  }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
flutter test test/platform/binary_locator_test.dart
```

Expected: PASS, 6 tests.

- [ ] **Step 7: Commit**

```bash
git add lib/src/platform test/platform test/support
git commit -m "feat: add ProcessRunner and PATH-independent BinaryLocator"
```

---

### Task 4: Account storage

**Files:**
- Create: `lib/src/services/account_store.dart`
- Test: `test/services/account_store_test.dart`

**Interfaces:**
- Consumes: `Account` (Task 2).
- Produces: `class AccountStore(File file)` with `Future<List<Account>> load()` and `Future<void> save(List<Account> accounts)`.

- [ ] **Step 1: Write the failing tests**

Create `test/services/account_store_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/models/account.dart';
import 'package:git_switcher/src/services/account_store.dart';

void main() {
  late Directory tempDir;
  late File file;
  late AccountStore store;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('gitswitcher_store_test');
    file = File('${tempDir.path}/config/accounts.json');
    store = AccountStore(file);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('returns an empty list when the file does not exist', () async {
    expect(await store.load(), isEmpty);
  });

  test('round-trips accounts through save and load', () async {
    const accounts = [
      Account(
        ghUsername: 'octocat',
        label: 'Work',
        gitName: 'Octo Cat',
        gitEmail: 'octo@example.com',
        sshKeyPath: '/Users/me/.ssh/id_work',
      ),
      Account(ghUsername: 'hubot', label: 'Personal'),
    ];

    await store.save(accounts);

    expect(await store.load(), accounts);
  });

  test('creates parent directories on save', () async {
    await store.save(const [Account(ghUsername: 'octocat')]);
    expect(file.existsSync(), isTrue);
  });

  test('writes a versioned envelope', () async {
    await store.save(const [Account(ghUsername: 'octocat')]);

    final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(data['version'], 1);
    expect(data['accounts'], hasLength(1));
  });

  test('quarantines a corrupt file and starts fresh', () async {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('this is not json {{{');

    expect(await store.load(), isEmpty);
    expect(file.existsSync(), isFalse);

    final quarantined = tempDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.contains('accounts.json.corrupt-'));
    expect(quarantined, hasLength(1));
  });

  test('quarantines valid JSON with the wrong shape', () async {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('{"version": 1, "accounts": "not a list"}');

    expect(await store.load(), isEmpty);
    expect(file.existsSync(), isFalse);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
flutter test test/services/account_store_test.dart
```

Expected: FAIL — `account_store.dart` not found.

- [ ] **Step 3: Implement `AccountStore`**

Create `lib/src/services/account_store.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import '../models/account.dart';

/// Reads and writes the app's own account configuration.
///
/// A corrupt config must never block startup, so [load] quarantines an
/// unreadable file and returns an empty list rather than throwing.
class AccountStore {
  AccountStore(this._file);

  final File _file;

  static const int _schemaVersion = 1;

  String get path => _file.path;

  Future<List<Account>> load() async {
    if (!await _file.exists()) return const [];

    try {
      final data = jsonDecode(await _file.readAsString());
      final accounts = (data as Map<String, dynamic>)['accounts'] as List;
      return accounts
          .map((e) => Account.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      await _quarantine();
      return const [];
    }
  }

  Future<void> save(List<Account> accounts) async {
    await _file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await _file.writeAsString(encoder.convert({
      'version': _schemaVersion,
      'accounts': accounts.map((a) => a.toJson()).toList(),
    }));
  }

  Future<void> _quarantine() async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    await _file.rename('${_file.path}.corrupt-$stamp');
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
flutter test test/services/account_store_test.dart
```

Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/src/services/account_store.dart test/services/account_store_test.dart
git commit -m "feat: add AccountStore with corrupt-config recovery"
```

---

### Task 5: gh CLI client

**Files:**
- Create: `lib/src/services/gh_client.dart`
- Test: `test/services/gh_client_test.dart`

**Interfaces:**
- Consumes: `ProcessRunner`, `CommandResult`, `BinaryLocator`, `BinaryNotFoundException` (Task 3); `StepResult` (Task 2).
- Produces:
  - `class GhAccounts` with `final List<String> usernames`, `final String? activeUsername`.
  - `class GhClient({required ProcessRunner runner, required BinaryLocator locator, required File hostsFile})` with `static const String stepName = 'gh'`, `static const String host = 'github.com'`, `Future<GhAccounts> discover()`, `Future<StepResult> switchTo(String username)`, and `static GhAccounts parseAuthStatus(String output)`.

**Reference — the real `hosts.yml` on this machine:**

```yaml
github.com:
    git_protocol: https
    users:
        octocat:
        hubot:
    user: octocat
```

Note that each entry under `users:` has a null value — the tokens live in the keychain, not this file.

- [ ] **Step 1: Write the failing tests**

Create `test/services/gh_client_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/models/switch_result.dart';
import 'package:git_switcher/src/platform/binary_locator.dart';
import 'package:git_switcher/src/platform/process_runner.dart';
import 'package:git_switcher/src/services/gh_client.dart';

import '../support/fake_process_runner.dart';

void main() {
  late Directory tempDir;
  late File hostsFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('gitswitcher_gh_test');
    hostsFile = File('${tempDir.path}/hosts.yml');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  GhClient buildClient(FakeProcessRunner runner) => GhClient(
        runner: runner,
        locator: BinaryLocator(
          runner: runner,
          searchDirs: const ['/opt/homebrew/bin'],
          exists: (path) => path == '/opt/homebrew/bin/gh',
        ),
        hostsFile: hostsFile,
      );

  group('discover from hosts.yml', () {
    test('reads every user and the active one', () async {
      hostsFile.writeAsStringSync('''
github.com:
    git_protocol: https
    users:
        octocat:
        hubot:
    user: octocat
''');

      final accounts = await buildClient(FakeProcessRunner()).discover();

      expect(accounts.usernames, ['octocat', 'hubot']);
      expect(accounts.activeUsername, 'octocat');
    });

    test('handles a single user', () async {
      hostsFile.writeAsStringSync('''
github.com:
    users:
        solo:
    user: solo
''');

      final accounts = await buildClient(FakeProcessRunner()).discover();

      expect(accounts.usernames, ['solo']);
      expect(accounts.activeUsername, 'solo');
    });

    test('tolerates a missing active user key', () async {
      hostsFile.writeAsStringSync('''
github.com:
    users:
        solo:
''');

      final accounts = await buildClient(FakeProcessRunner()).discover();

      expect(accounts.usernames, ['solo']);
      expect(accounts.activeUsername, isNull);
    });

    test('ignores hosts other than github.com', () async {
      hostsFile.writeAsStringSync('''
ghe.example.com:
    users:
        enterprise-user:
    user: enterprise-user
github.com:
    users:
        octocat:
    user: octocat
''');

      final accounts = await buildClient(FakeProcessRunner()).discover();

      expect(accounts.usernames, ['octocat']);
    });

    test('returns nothing when github.com is absent', () async {
      hostsFile.writeAsStringSync('ghe.example.com:\n    users:\n        x:\n');

      final accounts = await buildClient(FakeProcessRunner()).discover();

      expect(accounts.usernames, isEmpty);
      expect(accounts.activeUsername, isNull);
    });
  });

  group('discover falls back to gh auth status', () {
    const statusOutput = '''
github.com
  ✓ Logged in to github.com account octocat (keyring)
  - Active account: true
  - Git operations protocol: https

  ✓ Logged in to github.com account hubot (keyring)
  - Active account: false
  - Git operations protocol: https
''';

    test('parses usernames and the active account from status text', () {
      final accounts = GhClient.parseAuthStatus(statusOutput);

      expect(accounts.usernames, ['octocat', 'hubot']);
      expect(accounts.activeUsername, 'octocat');
    });

    test('is used when hosts.yml is missing', () async {
      final runner = FakeProcessRunner(
        responses: {
          '/opt/homebrew/bin/gh auth status':
              const CommandResult(0, statusOutput, ''),
        },
      );

      final accounts = await buildClient(runner).discover();

      expect(accounts.usernames, ['octocat', 'hubot']);
      expect(runner.calls, contains('/opt/homebrew/bin/gh auth status'));
    });

    test('is used when hosts.yml is malformed', () async {
      hostsFile.writeAsStringSync('\t: not: valid: yaml: [');
      final runner = FakeProcessRunner(
        responses: {
          '/opt/homebrew/bin/gh auth status':
              const CommandResult(0, statusOutput, ''),
        },
      );

      final accounts = await buildClient(runner).discover();

      expect(accounts.usernames, ['octocat', 'hubot']);
    });

    test('returns nothing when gh itself is missing', () async {
      final runner = FakeProcessRunner(fallback: const CommandResult(1, '', ''));
      final client = GhClient(
        runner: runner,
        locator: BinaryLocator(
          runner: runner,
          searchDirs: const [],
          exists: (_) => false,
        ),
        hostsFile: hostsFile,
      );

      final accounts = await client.discover();

      expect(accounts.usernames, isEmpty);
    });
  });

  group('isInstalled', () {
    test('is true when gh resolves', () async {
      expect(await buildClient(FakeProcessRunner()).isInstalled(), isTrue);
    });

    test('is false when gh cannot be found anywhere', () async {
      final runner = FakeProcessRunner(fallback: const CommandResult(1, '', ''));
      final client = GhClient(
        runner: runner,
        locator: BinaryLocator(
          runner: runner,
          searchDirs: const [],
          exists: (_) => false,
        ),
        hostsFile: hostsFile,
      );

      expect(await client.isInstalled(), isFalse);
    });
  });

  group('switchTo', () {
    test('runs gh auth switch with the host and user', () async {
      final runner = FakeProcessRunner();

      final step = await buildClient(runner).switchTo('octocat');

      expect(step.status, StepStatus.ok);
      expect(
        runner.calls,
        contains(
          '/opt/homebrew/bin/gh auth switch --hostname github.com --user octocat',
        ),
      );
    });

    test('fails with the stderr text when gh exits non-zero', () async {
      final runner = FakeProcessRunner(
        fallback: const CommandResult(1, '', 'no such account octocat'),
      );

      final step = await buildClient(runner).switchTo('octocat');

      expect(step.status, StepStatus.failed);
      expect(step.message, contains('no such account'));
    });

    test('fails with a clear message when gh is not installed', () async {
      final runner = FakeProcessRunner(fallback: const CommandResult(1, '', ''));
      final client = GhClient(
        runner: runner,
        locator: BinaryLocator(
          runner: runner,
          searchDirs: const [],
          exists: (_) => false,
        ),
        hostsFile: hostsFile,
      );

      final step = await client.switchTo('octocat');

      expect(step.status, StepStatus.failed);
      expect(step.message, contains('gh'));
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
flutter test test/services/gh_client_test.dart
```

Expected: FAIL — `gh_client.dart` not found.

- [ ] **Step 3: Implement `GhClient`**

Create `lib/src/services/gh_client.dart`:

```dart
import 'dart:io';

import 'package:yaml/yaml.dart';

import '../models/switch_result.dart';
import '../platform/binary_locator.dart';
import '../platform/process_runner.dart';

/// The accounts the gh CLI knows about, and which one is active.
class GhAccounts {
  const GhAccounts(this.usernames, this.activeUsername);

  const GhAccounts.empty() : usernames = const [], activeUsername = null;

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
  /// Each account is announced by a "Logged in to <host> account <name>" line
  /// and followed by an "Active account: true|false" line.
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
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
flutter test test/services/gh_client_test.dart
```

Expected: PASS, 14 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/src/services/gh_client.dart test/services/gh_client_test.dart
git commit -m "feat: add GhClient with hosts.yml discovery and status fallback"
```

---

### Task 6: Global git identity writer

**Files:**
- Create: `lib/src/services/git_identity_writer.dart`
- Test: `test/services/git_identity_writer_test.dart`

**Interfaces:**
- Consumes: `Account` (Task 2), `StepResult` (Task 2), `ProcessRunner`, `BinaryLocator` (Task 3).
- Produces: `class GitIdentityWriter({required ProcessRunner runner, required BinaryLocator locator})` with `static const String stepName = 'git identity'` and `Future<StepResult> apply(Account account)`.

**Behavior:** per the spec, the step is skipped unless **both** `gitName` and `gitEmail` are non-empty — half an identity is worse than leaving the previous one in place.

- [ ] **Step 1: Write the failing tests**

Create `test/services/git_identity_writer_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/models/account.dart';
import 'package:git_switcher/src/models/switch_result.dart';
import 'package:git_switcher/src/platform/binary_locator.dart';
import 'package:git_switcher/src/platform/process_runner.dart';
import 'package:git_switcher/src/services/git_identity_writer.dart';

import '../support/fake_process_runner.dart';

void main() {
  GitIdentityWriter buildWriter(
    FakeProcessRunner runner, {
    bool gitInstalled = true,
  }) {
    return GitIdentityWriter(
      runner: runner,
      locator: BinaryLocator(
        runner: runner,
        searchDirs: const ['/usr/bin'],
        exists: (path) => gitInstalled && path == '/usr/bin/git',
      ),
    );
  }

  const complete = Account(
    ghUsername: 'octocat',
    gitName: 'Octo Cat',
    gitEmail: 'octo@example.com',
  );

  test('sets both global name and email', () async {
    final runner = FakeProcessRunner();

    final step = await buildWriter(runner).apply(complete);

    expect(step.status, StepStatus.ok);
    expect(runner.calls, [
      '/usr/bin/git config --global user.name Octo Cat',
      '/usr/bin/git config --global user.email octo@example.com',
    ]);
  });

  test('skips when the git name is empty', () async {
    final runner = FakeProcessRunner();

    final step = await buildWriter(runner)
        .apply(const Account(ghUsername: 'octocat', gitEmail: 'a@b.com'));

    expect(step.status, StepStatus.skipped);
    expect(runner.calls, isEmpty);
  });

  test('skips when the git email is empty', () async {
    final runner = FakeProcessRunner();

    final step = await buildWriter(runner)
        .apply(const Account(ghUsername: 'octocat', gitName: 'Octo Cat'));

    expect(step.status, StepStatus.skipped);
    expect(runner.calls, isEmpty);
  });

  test('fails with the stderr text when git exits non-zero', () async {
    final runner = FakeProcessRunner(
      fallback: const CommandResult(1, '', 'could not lock config file'),
    );

    final step = await buildWriter(runner).apply(complete);

    expect(step.status, StepStatus.failed);
    expect(step.message, contains('could not lock'));
  });

  test('does not set the email if setting the name failed', () async {
    final runner = FakeProcessRunner(
      responses: {
        '/usr/bin/git config --global user.name Octo Cat':
            const CommandResult(1, '', 'permission denied'),
      },
    );

    await buildWriter(runner).apply(complete);

    expect(
      runner.calls,
      isNot(contains(
        '/usr/bin/git config --global user.email octo@example.com',
      )),
    );
  });

  test('fails with a clear message when git is not installed', () async {
    final step = await buildWriter(FakeProcessRunner(), gitInstalled: false)
        .apply(complete);

    expect(step.status, StepStatus.failed);
    expect(step.message, contains('git'));
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
flutter test test/services/git_identity_writer_test.dart
```

Expected: FAIL — `git_identity_writer.dart` not found.

- [ ] **Step 3: Implement `GitIdentityWriter`**

Create `lib/src/services/git_identity_writer.dart`:

```dart
import '../models/account.dart';
import '../models/switch_result.dart';
import '../platform/binary_locator.dart';
import '../platform/process_runner.dart';

/// Sets the global git commit identity.
///
/// Both name and email must be configured, otherwise the step is skipped:
/// writing half an identity would leave commits attributed to a mix of two
/// accounts, which is worse than leaving the previous identity in place.
class GitIdentityWriter {
  GitIdentityWriter({
    required ProcessRunner runner,
    required BinaryLocator locator,
  })  : _runner = runner,
        _locator = locator;

  final ProcessRunner _runner;
  final BinaryLocator _locator;

  static const String stepName = 'git identity';

  Future<StepResult> apply(Account account) async {
    if (account.gitName.isEmpty || account.gitEmail.isEmpty) {
      return const StepResult.skipped(
        stepName,
        'no git name and email configured',
      );
    }

    final String git;
    try {
      git = await _locator.locate('git');
    } on BinaryNotFoundException catch (error) {
      return StepResult.failed(stepName, error.toString());
    }

    for (final entry in {
      'user.name': account.gitName,
      'user.email': account.gitEmail,
    }.entries) {
      final result = await _runner.run(
        git,
        ['config', '--global', entry.key, entry.value],
      );
      if (!result.ok) {
        return StepResult.failed(
          stepName,
          'setting ${entry.key} failed: ${result.errorText}',
        );
      }
    }

    return const StepResult.ok(stepName);
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
flutter test test/services/git_identity_writer_test.dart
```

Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/src/services/git_identity_writer.dart test/services/git_identity_writer_test.dart
git commit -m "feat: add GitIdentityWriter for global commit identity"
```

---

### Task 7: SSH config managed-block writer

**Files:**
- Create: `lib/src/services/ssh_config_writer.dart`
- Test: `test/services/ssh_config_writer_test.dart`

**Interfaces:**
- Consumes: `Account` (Task 2), `StepResult` (Task 2), `ProcessRunner` (Task 3).
- Produces: `class SshConfigWriter({required File file, required ProcessRunner runner, DateTime Function() now})` with `static const String stepName = 'ssh'`, `static const String beginMarker`, `static const String endMarker`, `Future<StepResult> apply(Account account)`, and `static String replaceBlock(String existing, String block)` plus `static String renderBlock(String keyPath)`.

This is the most dangerous unit in the app — it edits a file the user owns and did not create. It gets the largest test suite.

- [ ] **Step 1: Write the failing tests**

Create `test/services/ssh_config_writer_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/models/account.dart';
import 'package:git_switcher/src/models/switch_result.dart';
import 'package:git_switcher/src/services/ssh_config_writer.dart';

import '../support/fake_process_runner.dart';

void main() {
  late Directory tempDir;
  late File configFile;
  late FakeProcessRunner runner;
  late SshConfigWriter writer;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('gitswitcher_ssh_test');
    configFile = File('${tempDir.path}/config');
    runner = FakeProcessRunner();
    writer = SshConfigWriter(
      file: configFile,
      runner: runner,
      now: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  const account = Account(
    ghUsername: 'octocat',
    sshKeyPath: '/Users/me/.ssh/id_work',
  );

  group('replaceBlock', () {
    const block = 'BEGIN\nbody\nEND';

    test('appends to content that has no markers', () {
      final result = SshConfigWriter.replaceBlock('Host *\n    TCPKeepAlive yes\n', block);

      expect(result, 'Host *\n    TCPKeepAlive yes\n\nBEGIN\nbody\nEND\n');
    });

    test('appends to empty content without leading blank lines', () {
      expect(SshConfigWriter.replaceBlock('', block), 'BEGIN\nbody\nEND\n');
    });

    test('replaces an existing block in place', () {
      const existing = 'before\n\n'
          '${SshConfigWriter.beginMarker}\nold body\n${SshConfigWriter.endMarker}'
          '\n\nafter\n';
      final newBlock =
          '${SshConfigWriter.beginMarker}\nnew body\n${SshConfigWriter.endMarker}';

      final result = SshConfigWriter.replaceBlock(existing, newBlock);

      expect(result, 'before\n\n$newBlock\n\nafter\n');
    });

    test('throws when the closing marker is missing', () {
      expect(
        () => SshConfigWriter.replaceBlock(
          '${SshConfigWriter.beginMarker}\nbody\n',
          block,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when the closing marker precedes the opening marker', () {
      expect(
        () => SshConfigWriter.replaceBlock(
          '${SshConfigWriter.endMarker}\n${SshConfigWriter.beginMarker}\n',
          block,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('apply', () {
    test('skips when no ssh key is configured', () async {
      final step = await writer.apply(const Account(ghUsername: 'octocat'));

      expect(step.status, StepStatus.skipped);
      expect(configFile.existsSync(), isFalse);
    });

    test('creates the file when it does not exist', () async {
      final step = await writer.apply(account);

      expect(step.status, StepStatus.ok);
      expect(configFile.readAsStringSync(), contains('IdentityFile /Users/me/.ssh/id_work'));
      expect(configFile.readAsStringSync(), contains('Host github.com'));
    });

    test('chmods a newly created file to 600', () async {
      await writer.apply(account);

      expect(runner.calls, ['/bin/chmod 600 ${configFile.path}']);
    });

    test('preserves content outside the markers byte-for-byte', () async {
      const original = 'Host *\n'
          '    ServerAliveInterval 60\n'
          '    TCPKeepAlive yes\n';
      configFile.writeAsStringSync(original);

      await writer.apply(account);

      expect(configFile.readAsStringSync(), startsWith(original));
    });

    test('replaces the key on a second switch without duplicating the block', () async {
      await writer.apply(account);
      await writer.apply(
        const Account(ghUsername: 'hubot', sshKeyPath: '/Users/me/.ssh/id_personal'),
      );

      final contents = configFile.readAsStringSync();
      expect(SshConfigWriter.beginMarker.allMatches(contents), hasLength(1));
      expect(contents, contains('/Users/me/.ssh/id_personal'));
      expect(contents, isNot(contains('/Users/me/.ssh/id_work')));
    });

    test('writes a backup before modifying an existing file', () async {
      configFile.writeAsStringSync('Host *\n    TCPKeepAlive yes\n');

      await writer.apply(account);

      final backup = File('${configFile.path}.gitswitcher-backup-1700000000000');
      expect(backup.existsSync(), isTrue);
      expect(backup.readAsStringSync(), 'Host *\n    TCPKeepAlive yes\n');
    });

    test('is idempotent: an unchanged rewrite makes no backup', () async {
      await writer.apply(account);
      final afterFirst = configFile.readAsStringSync();

      final step = await writer.apply(account);

      expect(step.status, StepStatus.ok);
      expect(configFile.readAsStringSync(), afterFirst);
      expect(
        File('${configFile.path}.gitswitcher-backup-1700000000000').existsSync(),
        isFalse,
      );
    });

    test('fails without writing when the markers are malformed', () async {
      const damaged = '${SshConfigWriter.beginMarker}\nHost github.com\n';
      configFile.writeAsStringSync(damaged);

      final step = await writer.apply(account);

      expect(step.status, StepStatus.failed);
      expect(step.message, contains('malformed'));
      expect(configFile.readAsStringSync(), damaged);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
flutter test test/services/ssh_config_writer_test.dart
```

Expected: FAIL — `ssh_config_writer.dart` not found.

- [ ] **Step 3: Implement `SshConfigWriter`**

Create `lib/src/services/ssh_config_writer.dart`:

```dart
import 'dart:io';

import '../models/account.dart';
import '../models/switch_result.dart';
import '../platform/process_runner.dart';

/// Rewrites the github.com SSH identity inside a marked region of the user's
/// `~/.ssh/config`.
///
/// The user owns this file and did not create it for us, so the contract is
/// strict: only bytes between the two markers are ever touched, a backup is
/// written before any modification, and anything unexpected between the
/// markers aborts the write rather than guessing.
class SshConfigWriter {
  SshConfigWriter({
    required File file,
    required ProcessRunner runner,
    DateTime Function() now = DateTime.now,
  })  : _file = file,
        _runner = runner,
        _now = now;

  final File _file;
  final ProcessRunner _runner;
  final DateTime Function() _now;

  static const String stepName = 'ssh';
  static const String beginMarker = '# >>> GitSwitcher (managed — do not edit)';
  static const String endMarker = '# <<< GitSwitcher';

  static String renderBlock(String keyPath) => [
        beginMarker,
        'Host github.com',
        '    HostName github.com',
        '    User git',
        '    IdentityFile $keyPath',
        '    IdentitiesOnly yes',
        endMarker,
      ].join('\n');

  /// Returns [existing] with the managed block set to [block].
  ///
  /// Throws [FormatException] if the markers are present but unusable.
  static String replaceBlock(String existing, String block) {
    final beginIndex = existing.indexOf(beginMarker);
    final endIndex = existing.indexOf(endMarker);

    if (beginIndex == -1 && endIndex == -1) {
      if (existing.isEmpty) return '$block\n';
      final separator = existing.endsWith('\n') ? '\n' : '\n\n';
      return '$existing$separator$block\n';
    }

    if (beginIndex == -1 || endIndex == -1 || endIndex < beginIndex) {
      throw const FormatException(
        'The GitSwitcher markers in your SSH config are malformed. '
        'Nothing was written — please repair the file by hand.',
      );
    }

    final before = existing.substring(0, beginIndex);
    final after = existing.substring(endIndex + endMarker.length);
    return '$before$block$after';
  }

  Future<StepResult> apply(Account account) async {
    if (account.sshKeyPath.isEmpty) {
      return const StepResult.skipped(stepName, 'no SSH key configured');
    }

    final fileExisted = await _file.exists();
    final existing = fileExisted ? await _file.readAsString() : '';

    final String updated;
    try {
      updated = replaceBlock(existing, renderBlock(account.sshKeyPath));
    } on FormatException catch (error) {
      return StepResult.failed(stepName, error.message);
    }

    // Already correct — do not churn the file or pile up backups.
    if (updated == existing) return const StepResult.ok(stepName);

    try {
      if (fileExisted) {
        final stamp = _now().millisecondsSinceEpoch;
        await File('${_file.path}.gitswitcher-backup-$stamp')
            .writeAsString(existing);
      }

      await _file.parent.create(recursive: true);
      await _file.writeAsString(updated);

      if (!fileExisted) {
        // Dart cannot set file modes directly, and ssh refuses to read a
        // world-readable config.
        await _runner.run('/bin/chmod', ['600', _file.path]);
      }
    } on FileSystemException catch (error) {
      return StepResult.failed(stepName, error.message);
    }

    return const StepResult.ok(stepName);
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
flutter test test/services/ssh_config_writer_test.dart
```

Expected: PASS, 14 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/src/services/ssh_config_writer.dart test/services/ssh_config_writer_test.dart
git commit -m "feat: add SshConfigWriter with managed block and backups"
```

---

### Task 8: Account resolution

**Files:**
- Create: `lib/src/services/account_resolver.dart`
- Test: `test/services/account_resolver_test.dart`

**Interfaces:**
- Consumes: `Account` (Task 2), `GhAccounts` (Task 5).
- Produces:
  - `class ResolvedAccount` with `final Account account`, `final bool isActive`, `final bool isLoggedIn`; getters `bool get isSelectable`, `String? get disabledReason`.
  - `class AccountResolver` with `static List<ResolvedAccount> merge({required List<Account> stored, required GhAccounts discovered})`.

- [ ] **Step 1: Write the failing tests**

Create `test/services/account_resolver_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/models/account.dart';
import 'package:git_switcher/src/services/account_resolver.dart';
import 'package:git_switcher/src/services/gh_client.dart';

void main() {
  const work = Account(
    ghUsername: 'octocat',
    label: 'Work',
    gitName: 'Muhammad',
    gitEmail: 'work@example.com',
  );

  test('marks the gh active account as active', () {
    final resolved = AccountResolver.merge(
      stored: const [work],
      discovered: const GhAccounts(['octocat'], 'octocat'),
    );

    expect(resolved.single.isActive, isTrue);
    expect(resolved.single.isSelectable, isTrue);
    expect(resolved.single.disabledReason, isNull);
  });

  test('adds discovered accounts that have no stored entry', () {
    final resolved = AccountResolver.merge(
      stored: const [work],
      discovered: const GhAccounts(['octocat', 'hubot'], 'octocat'),
    );

    expect(resolved.map((r) => r.account.ghUsername),
        ['octocat', 'hubot']);
  });

  test('a newly discovered account is not selectable until configured', () {
    final resolved = AccountResolver.merge(
      stored: const [],
      discovered: const GhAccounts(['hubot'], null),
    );

    expect(resolved.single.isLoggedIn, isTrue);
    expect(resolved.single.isSelectable, isFalse);
    expect(resolved.single.disabledReason, contains('Settings'));
  });

  test('keeps a stored account that gh no longer knows about', () {
    final resolved = AccountResolver.merge(
      stored: const [work],
      discovered: const GhAccounts(['hubot'], 'hubot'),
    );

    final stale = resolved.firstWhere(
      (r) => r.account.ghUsername == 'octocat',
    );
    expect(stale.isLoggedIn, isFalse);
    expect(stale.isSelectable, isFalse);
    expect(stale.disabledReason, contains('not logged in'));
  });

  test('never lists the same username twice', () {
    final resolved = AccountResolver.merge(
      stored: const [work],
      discovered: const GhAccounts(['octocat'], 'octocat'),
    );

    expect(resolved, hasLength(1));
  });

  test('stored accounts keep their order and come before new discoveries', () {
    final resolved = AccountResolver.merge(
      stored: const [
        Account(ghUsername: 'b', gitEmail: 'b@x.com'),
        Account(ghUsername: 'a', gitEmail: 'a@x.com'),
      ],
      discovered: const GhAccounts(['a', 'b', 'c'], 'a'),
    );

    expect(resolved.map((r) => r.account.ghUsername), ['b', 'a', 'c']);
  });

  test('reports no accounts when gh knows none and nothing is stored', () {
    final resolved = AccountResolver.merge(
      stored: const [],
      discovered: const GhAccounts.empty(),
    );

    expect(resolved, isEmpty);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
flutter test test/services/account_resolver_test.dart
```

Expected: FAIL — `account_resolver.dart` not found.

- [ ] **Step 3: Implement `AccountResolver`**

Create `lib/src/services/account_resolver.dart`:

```dart
import '../models/account.dart';
import 'gh_client.dart';

/// A stored account joined with what gh currently reports about it.
class ResolvedAccount {
  const ResolvedAccount({
    required this.account,
    required this.isActive,
    required this.isLoggedIn,
  });

  final Account account;

  /// True when gh's active account is this one.
  final bool isActive;

  /// True when gh still has credentials for this account.
  final bool isLoggedIn;

  bool get isSelectable => isLoggedIn && account.isComplete;

  /// Why this account cannot be selected, or null if it can be.
  String? get disabledReason {
    if (!isLoggedIn) return 'not logged in to gh — run: gh auth login';
    if (!account.isComplete) return 'needs setup in Settings';
    return null;
  }
}

/// Joins the app's stored configuration with gh's live account list.
///
/// A stored account is never dropped just because gh forgot it — the user
/// typed its email and key path, and losing that silently would be worse than
/// showing a disabled row.
class AccountResolver {
  const AccountResolver._();

  static List<ResolvedAccount> merge({
    required List<Account> stored,
    required GhAccounts discovered,
  }) {
    final resolved = <ResolvedAccount>[];
    final seen = <String>{};

    for (final account in stored) {
      seen.add(account.ghUsername);
      resolved.add(ResolvedAccount(
        account: account,
        isActive: account.ghUsername == discovered.activeUsername,
        isLoggedIn: discovered.usernames.contains(account.ghUsername),
      ));
    }

    for (final username in discovered.usernames) {
      if (seen.contains(username)) continue;
      resolved.add(ResolvedAccount(
        account: Account(ghUsername: username),
        isActive: username == discovered.activeUsername,
        isLoggedIn: true,
      ));
    }

    return resolved;
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
flutter test test/services/account_resolver_test.dart
```

Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/src/services/account_resolver.dart test/services/account_resolver_test.dart
git commit -m "feat: add AccountResolver merging stored config with gh state"
```

---

### Task 9: Switch orchestration

**Files:**
- Create: `lib/src/services/account_switcher.dart`
- Test: `test/services/account_switcher_test.dart`

**Interfaces:**
- Consumes: `GhClient` (Task 5), `GitIdentityWriter` (Task 6), `SshConfigWriter` (Task 7), `Account`/`SwitchResult` (Task 2).
- Produces: `class AccountSwitcher({required GhClient gh, required GitIdentityWriter git, required SshConfigWriter ssh})` with `Future<SwitchResult> switchTo(Account account)`.

Steps run in order — gh, git identity, ssh — and one failing never prevents the others from running. Any unexpected exception thrown by a step is converted into a failed `StepResult` so one bug cannot take down the whole switch.

- [ ] **Step 1: Write the failing tests**

Create `test/services/account_switcher_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/models/account.dart';
import 'package:git_switcher/src/models/switch_result.dart';
import 'package:git_switcher/src/platform/binary_locator.dart';
import 'package:git_switcher/src/platform/process_runner.dart';
import 'package:git_switcher/src/services/account_switcher.dart';
import 'package:git_switcher/src/services/gh_client.dart';
import 'package:git_switcher/src/services/git_identity_writer.dart';
import 'package:git_switcher/src/services/ssh_config_writer.dart';

import '../support/fake_process_runner.dart';

void main() {
  late Directory tempDir;
  late File hostsFile;
  late File sshConfig;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('gitswitcher_switch_test');
    hostsFile = File('${tempDir.path}/hosts.yml');
    sshConfig = File('${tempDir.path}/ssh_config');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  AccountSwitcher buildSwitcher(FakeProcessRunner runner) {
    final locator = BinaryLocator(
      runner: runner,
      searchDirs: const ['/opt/homebrew/bin', '/usr/bin'],
      exists: (path) =>
          path == '/opt/homebrew/bin/gh' || path == '/usr/bin/git',
    );
    return AccountSwitcher(
      gh: GhClient(runner: runner, locator: locator, hostsFile: hostsFile),
      git: GitIdentityWriter(runner: runner, locator: locator),
      ssh: SshConfigWriter(file: sshConfig, runner: runner),
    );
  }

  const fullAccount = Account(
    ghUsername: 'octocat',
    label: 'Work',
    gitName: 'Octo Cat',
    gitEmail: 'octo@example.com',
    sshKeyPath: '/Users/me/.ssh/id_work',
  );

  test('runs all three steps and reports them in order', () async {
    final result = await buildSwitcher(FakeProcessRunner()).switchTo(fullAccount);

    expect(result.ghUsername, 'octocat');
    expect(result.steps.map((s) => s.name), ['gh', 'git identity', 'ssh']);
    expect(result.allOk, isTrue);
  });

  test('runs the remaining steps when gh fails', () async {
    final runner = FakeProcessRunner(
      responses: {
        '/opt/homebrew/bin/gh auth switch --hostname github.com --user octocat':
            const CommandResult(1, '', 'not logged in'),
      },
    );

    final result = await buildSwitcher(runner).switchTo(fullAccount);

    expect(result.anyFailed, isTrue);
    expect(result.failedSteps.single.name, 'gh');
    expect(sshConfig.existsSync(), isTrue);
    expect(
      runner.calls,
      contains('/usr/bin/git config --global user.name Octo Cat'),
    );
  });

  test('reports skipped steps without marking the switch failed', () async {
    final result = await buildSwitcher(FakeProcessRunner())
        .switchTo(const Account(ghUsername: 'octocat'));

    expect(result.allOk, isTrue);
    expect(
      result.steps.where((s) => s.status == StepStatus.skipped).map((s) => s.name),
      ['git identity', 'ssh'],
    );
  });

  test('reports an unwritable ssh config as a failed step only', () async {
    // A directory where the SSH config file should be makes writing throw.
    Directory(sshConfig.path).createSync(recursive: true);

    final result = await buildSwitcher(FakeProcessRunner()).switchTo(fullAccount);

    expect(result.anyFailed, isTrue);
    expect(result.failedSteps.single.name, 'ssh');
    expect(result.steps.first.status, StepStatus.ok);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
flutter test test/services/account_switcher_test.dart
```

Expected: FAIL — `account_switcher.dart` not found.

- [ ] **Step 3: Implement `AccountSwitcher`**

Create `lib/src/services/account_switcher.dart`:

```dart
import '../models/account.dart';
import '../models/switch_result.dart';
import 'gh_client.dart';
import 'git_identity_writer.dart';
import 'ssh_config_writer.dart';

/// Runs the three switch steps and collects their outcomes.
///
/// Steps are deliberately independent: a failure in one must not hide or
/// prevent the others, so the user always learns exactly how far the switch
/// got rather than being told only that "something failed".
class AccountSwitcher {
  AccountSwitcher({
    required GhClient gh,
    required GitIdentityWriter git,
    required SshConfigWriter ssh,
  })  : _gh = gh,
        _git = git,
        _ssh = ssh;

  final GhClient _gh;
  final GitIdentityWriter _git;
  final SshConfigWriter _ssh;

  Future<SwitchResult> switchTo(Account account) async {
    final steps = [
      await _guard(GhClient.stepName, () => _gh.switchTo(account.ghUsername)),
      await _guard(GitIdentityWriter.stepName, () => _git.apply(account)),
      await _guard(SshConfigWriter.stepName, () => _ssh.apply(account)),
    ];

    return SwitchResult(account.ghUsername, steps);
  }

  Future<StepResult> _guard(
    String stepName,
    Future<StepResult> Function() step,
  ) async {
    try {
      return await step();
    } catch (error) {
      return StepResult.failed(stepName, error.toString());
    }
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
flutter test test/services/account_switcher_test.dart
```

Expected: PASS, 4 tests.

- [ ] **Step 5: Run the whole suite**

```bash
flutter test
```

Expected: PASS, all tests from Tasks 2–9.

- [ ] **Step 6: Commit**

```bash
git add lib/src/services/account_switcher.dart test/services/account_switcher_test.dart
git commit -m "feat: add AccountSwitcher orchestrating the three switch steps"
```

---

### Task 10: Result notification

**Files:**
- Create: `lib/src/services/notifier.dart`
- Test: `test/services/notifier_test.dart`

**Interfaces:**
- Consumes: `SwitchResult`, `StepResult`, `StepStatus` (Task 2); `ProcessRunner` (Task 3).
- Produces: `class Notifier(ProcessRunner runner)` with `Future<void> show({required String title, required String body})` and `Future<void> showSwitchResult(SwitchResult result, String displayName)`; `static String describe(SwitchResult result)`.

Notifications go through `osascript` rather than a plugin: it needs no native code and no extra dependency, and it is trivially testable through the same `ProcessRunner` fake as everything else. If macOS suppresses these because notification permission was never granted for scripts, that is a known follow-up, not a blocker.

- [ ] **Step 1: Write the failing tests**

Create `test/services/notifier_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/models/switch_result.dart';
import 'package:git_switcher/src/services/notifier.dart';

import '../support/fake_process_runner.dart';

void main() {
  test('describes a fully successful switch', () {
    final result = SwitchResult('octocat', [
      StepResult.ok('gh'),
      StepResult.ok('git identity'),
      StepResult.ok('ssh'),
    ]);

    expect(Notifier.describe(result), 'gh, git identity and SSH updated.');
  });

  test('names the steps that were skipped', () {
    final result = SwitchResult('octocat', [
      StepResult.ok('gh'),
      StepResult.skipped('git identity', 'no git name and email configured'),
      StepResult.skipped('ssh', 'no SSH key configured'),
    ]);

    expect(Notifier.describe(result), contains('skipped: git identity, ssh'));
  });

  test('names the steps that failed and why', () {
    final result = SwitchResult('octocat', [
      StepResult.ok('gh'),
      StepResult.ok('git identity'),
      StepResult.failed('ssh', 'markers are malformed'),
    ]);

    expect(Notifier.describe(result), contains('ssh failed: markers are malformed'));
  });

  test('runs osascript with the title and body', () async {
    final runner = FakeProcessRunner();

    await Notifier(runner).show(title: 'GitSwitcher', body: 'Switched to Work');

    expect(runner.calls.single, contains('/usr/bin/osascript'));
    expect(runner.calls.single, contains('display notification "Switched to Work"'));
    expect(runner.calls.single, contains('with title "GitSwitcher"'));
  });

  test('escapes quotes and backslashes in notification text', () async {
    final runner = FakeProcessRunner();

    await Notifier(runner).show(title: 'GitSwitcher', body: r'say "hi" \ bye');

    expect(runner.calls.single, contains(r'say \"hi\" \\ bye'));
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
flutter test test/services/notifier_test.dart
```

Expected: FAIL — `notifier.dart` not found.

- [ ] **Step 3: Implement `Notifier`**

Create `lib/src/services/notifier.dart`:

```dart
import '../models/switch_result.dart';
import '../platform/process_runner.dart';

/// Posts macOS notifications through osascript.
///
/// Shelling out avoids a native plugin and keeps this unit testable with the
/// same fake process runner as the rest of the app.
class Notifier {
  const Notifier(this._runner);

  final ProcessRunner _runner;

  static const String appName = 'GitSwitcher';

  Future<void> show({required String title, required String body}) async {
    final script =
        'display notification "${_escape(body)}" with title "${_escape(title)}"';
    await _runner.run('/usr/bin/osascript', ['-e', script]);
  }

  Future<void> showSwitchResult(SwitchResult result, String displayName) {
    final prefix = result.allOk ? 'Switched to $displayName' : 'Switch to $displayName incomplete';
    return show(title: prefix, body: describe(result));
  }

  /// A one-line summary of what actually happened.
  static String describe(SwitchResult result) {
    final failed = result.failedSteps
        .map((s) => '${s.name} failed: ${s.message}')
        .join('; ');
    if (failed.isNotEmpty) return failed;

    final skipped = result.steps
        .where((s) => s.status == StepStatus.skipped)
        .map((s) => s.name)
        .join(', ');
    if (skipped.isNotEmpty) return 'Done — skipped: $skipped.';

    return 'gh, git identity and SSH updated.';
  }

  static String _escape(String text) =>
      text.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
flutter test test/services/notifier_test.dart
```

Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/src/services/notifier.dart test/services/notifier_test.dart
git commit -m "feat: add Notifier for switch result feedback"
```

---

### Task 11: Menu bar wiring

**Files:**
- Create: `lib/src/app_services.dart`
- Create: `lib/src/ui/tray_controller.dart`
- Modify: `lib/main.dart` (replace the `flutter create` counter app entirely)
- Create: `lib/src/ui/settings_window.dart`

**Interfaces:**
- Consumes: everything from Tasks 2–10.
- Produces:
  - `class AppServices` with `final AccountStore store`, `final GhClient gh`, `final AccountSwitcher switcher`, `final Notifier notifier`; `static Future<AppServices> create()`.
  - `class TrayController` with `Future<void> start()`, `Future<void> refreshMenu()`, `void dispose()`.
  - `class SettingsWindow` with `static Future<void> open()` and `static Future<void> close()`.
  - `lib/main.dart` `void main()`.

At the end of this task the app is functional: the menu bar icon lists accounts and switching works. Settings is a placeholder screen replaced in Task 12.

- [ ] **Step 1: Write the service locator**

Create `lib/src/app_services.dart`:

```dart
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'platform/binary_locator.dart';
import 'platform/process_runner.dart';
import 'services/account_store.dart';
import 'services/account_switcher.dart';
import 'services/gh_client.dart';
import 'services/git_identity_writer.dart';
import 'services/notifier.dart';
import 'services/ssh_config_writer.dart';

/// Wires the real implementations together at startup.
class AppServices {
  AppServices._({
    required this.store,
    required this.gh,
    required this.switcher,
    required this.notifier,
  });

  final AccountStore store;
  final GhClient gh;
  final AccountSwitcher switcher;
  final Notifier notifier;

  static Future<AppServices> create() async {
    const runner = RealProcessRunner();
    final locator = BinaryLocator(runner: runner);
    final home = Platform.environment['HOME']!;

    final supportDir = await getApplicationSupportDirectory();
    final store = AccountStore(File('${supportDir.path}/accounts.json'));

    final gh = GhClient(
      runner: runner,
      locator: locator,
      hostsFile: File('$home/.config/gh/hosts.yml'),
    );

    return AppServices._(
      store: store,
      gh: gh,
      notifier: const Notifier(runner),
      switcher: AccountSwitcher(
        gh: gh,
        git: GitIdentityWriter(runner: runner, locator: locator),
        ssh: SshConfigWriter(
          file: File('$home/.ssh/config'),
          runner: runner,
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Write the settings window helper**

Create `lib/src/ui/settings_window.dart`:

```dart
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
```

- [ ] **Step 3: Write the tray controller**

Create `lib/src/ui/tray_controller.dart`:

```dart
import 'dart:io';

import 'package:tray_manager/tray_manager.dart';

import '../app_services.dart';
import '../services/account_resolver.dart';
import 'settings_window.dart';

/// Owns the menu bar icon and its menu.
///
/// gh state is re-read every time the menu opens, so the checkmark stays
/// correct even when `gh auth switch` is run directly in a terminal.
class TrayController with TrayListener {
  TrayController(this._services);

  final AppServices _services;

  static const String _settingsKey = '__settings';
  static const String _quitKey = '__quit';

  Future<void> start() async {
    trayManager.addListener(this);
    await trayManager.setIcon('assets/tray_icon.png', isTemplate: true);
    await trayManager.setToolTip('GitSwitcher');
    await refreshMenu();
  }

  void dispose() {
    trayManager.removeListener(this);
  }

  @override
  void onTrayIconMouseDown() {
    // Rebuild before showing so the checkmark reflects gh's current state.
    refreshMenu().then((_) => trayManager.popUpContextMenu());
  }

  @override
  void onTrayIconRightMouseDown() => onTrayIconMouseDown();

  Future<void> refreshMenu() async {
    final resolved = AccountResolver.merge(
      stored: await _services.store.load(),
      discovered: await _services.gh.discover(),
    );

    final items = <MenuItem>[];

    if (resolved.isEmpty) {
      // "gh is missing" and "gh has no accounts" need different advice.
      final ghInstalled = await _services.gh.isInstalled();
      items.add(MenuItem(
        key: '__empty',
        label: ghInstalled ? 'No GitHub accounts found' : 'GitHub CLI not found',
        disabled: true,
      ));
      items.add(MenuItem(
        key: '__hint',
        label: ghInstalled
            ? 'Run: gh auth login'
            : 'Install it from cli.github.com',
        disabled: true,
      ));
    } else {
      for (final entry in resolved) {
        final reason = entry.disabledReason;
        items.add(MenuItem.checkbox(
          key: entry.account.ghUsername,
          label: entry.account.displayName,
          sublabel: reason,
          toolTip: reason,
          checked: entry.isActive,
          disabled: !entry.isSelectable,
        ));
      }
    }

    items.addAll([
      MenuItem.separator(),
      MenuItem(key: _settingsKey, label: 'Settings…'),
      MenuItem(key: _quitKey, label: 'Quit GitSwitcher'),
    ]);

    await trayManager.setContextMenu(Menu(items: items));
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _settingsKey:
        SettingsWindow.open();
      case _quitKey:
        trayManager.destroy().then((_) => exit(0));
      case final String username when username.startsWith('__'):
        break;
      case final String username:
        _switchTo(username);
      case null:
        break;
    }
  }

  Future<void> _switchTo(String username) async {
    final stored = await _services.store.load();
    final resolved = AccountResolver.merge(
      stored: stored,
      discovered: await _services.gh.discover(),
    );
    final entry =
        resolved.firstWhere((r) => r.account.ghUsername == username);

    final result = await _services.switcher.switchTo(entry.account);
    await _services.notifier
        .showSwitchResult(result, entry.account.displayName);
    await refreshMenu();
  }
}
```

- [ ] **Step 4: Rewrite `lib/main.dart`**

Replace the entire contents of `lib/main.dart` (the generated counter app) with:

```dart
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app_services.dart';
import 'src/ui/tray_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const options = WindowOptions(
    size: Size(620, 560),
    center: true,
    title: 'GitSwitcher Settings',
    titleBarStyle: TitleBarStyle.normal,
    skipTaskbar: true,
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    // The window is only ever shown on demand from the menu.
    await windowManager.setPreventClose(true);
    await windowManager.hide();
  });

  final services = await AppServices.create();
  final tray = TrayController(services);
  await tray.start();

  runApp(GitSwitcherApp(services: services, tray: tray));
}

class GitSwitcherApp extends StatelessWidget {
  const GitSwitcherApp({super.key, required this.services, required this.tray});

  final AppServices services;
  final TrayController tray;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GitSwitcher',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF24292F)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF24292F),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(child: Text('Settings — implemented in Task 12')),
      ),
    );
  }
}
```

Note: `setPreventClose(true)` means the red close button does nothing until a `WindowListener` handles it. That listener lives in the settings screen and arrives in Task 12; until then, closing the settings window is expected to do nothing.

- [ ] **Step 5: Analyze and build**

```bash
flutter analyze && flutter build macos --debug
```

Expected: no analyzer errors, build succeeds.

- [ ] **Step 6: Verify the menu manually**

```bash
open build/macos/Build/Products/Debug/GitSwitcher.app
```

Confirm, in order:
1. A switch-arrows icon appears in the menu bar and no Dock icon appears.
2. Clicking it shows `octocat` and `hubot`, both greyed out with "needs setup in Settings" (nothing is configured yet), plus `Settings…` and `Quit GitSwitcher`.
3. `Settings…` raises a window showing the placeholder text.
4. `Quit GitSwitcher` removes the icon and exits.

- [ ] **Step 7: Commit**

```bash
git add lib
git commit -m "feat: wire menu bar icon, account menu, and switch action"
```

---

### Task 12: Settings screen

**Files:**
- Create: `lib/src/ui/settings_screen.dart`
- Modify: `lib/main.dart` (use `SettingsScreen` as `home`, add close-to-hide handling)

**Interfaces:**
- Consumes: `AppServices`, `TrayController`, `AccountResolver`, `Account`.
- Produces: `class SettingsScreen extends StatefulWidget` taking `AppServices services` and `TrayController tray`.

The screen lists every resolved account and lets the user edit label, git name, git email, and SSH key path. Saving persists through `AccountStore` and refreshes the tray menu so the newly-completed account becomes selectable immediately.

- [ ] **Step 1: Write the settings screen**

Create `lib/src/ui/settings_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../app_services.dart';
import '../models/account.dart';
import '../services/account_resolver.dart';
import 'tray_controller.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.services,
    required this.tray,
  });

  final AppServices services;
  final TrayController tray;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WindowListener {
  List<ResolvedAccount> _accounts = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _reload();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  /// The app keeps running when the settings window is closed — the menu bar
  /// icon is the app's real home.
  @override
  void onWindowClose() {
    windowManager.hide();
  }

  Future<void> _reload() async {
    final resolved = AccountResolver.merge(
      stored: await widget.services.store.load(),
      discovered: await widget.services.gh.discover(),
    );
    if (!mounted) return;
    setState(() {
      _accounts = resolved;
      _loading = false;
    });
  }

  Future<void> _save(Account updated) async {
    final stored = await widget.services.store.load();
    final index =
        stored.indexWhere((a) => a.ghUsername == updated.ghUsername);
    if (index == -1) {
      stored.add(updated);
    } else {
      stored[index] = updated;
    }

    await widget.services.store.save(stored);
    await widget.tray.refreshMenu();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GitSwitcher'),
        actions: [
          IconButton(
            tooltip: 'Reload from gh',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _accounts.isEmpty
              ? const _EmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _accounts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => _AccountCard(
                    key: ValueKey(_accounts[index].account.ghUsername),
                    resolved: _accounts[index],
                    onSave: _save,
                  ),
                ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('No GitHub accounts found.'),
            const SizedBox(height: 8),
            Text(
              'Log in with the GitHub CLI first:\n\n'
              '    gh auth login\n\n'
              'Then press refresh.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountCard extends StatefulWidget {
  const _AccountCard({
    super.key,
    required this.resolved,
    required this.onSave,
  });

  final ResolvedAccount resolved;
  final Future<void> Function(Account) onSave;

  @override
  State<_AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<_AccountCard> {
  late final TextEditingController _label;
  late final TextEditingController _gitName;
  late final TextEditingController _gitEmail;
  late final TextEditingController _sshKeyPath;

  @override
  void initState() {
    super.initState();
    final account = widget.resolved.account;
    _label = TextEditingController(text: account.label);
    _gitName = TextEditingController(text: account.gitName);
    _gitEmail = TextEditingController(text: account.gitEmail);
    _sshKeyPath = TextEditingController(text: account.sshKeyPath);
  }

  @override
  void dispose() {
    _label.dispose();
    _gitName.dispose();
    _gitEmail.dispose();
    _sshKeyPath.dispose();
    super.dispose();
  }

  void _handleSave() {
    widget.onSave(widget.resolved.account.copyWith(
      label: _label.text.trim(),
      gitName: _gitName.text.trim(),
      gitEmail: _gitEmail.text.trim(),
      sshKeyPath: _sshKeyPath.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final resolved = widget.resolved;
    final reason = resolved.disabledReason;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  resolved.account.ghUsername,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(width: 8),
                if (resolved.isActive)
                  const Chip(
                    label: Text('Active'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            if (reason != null) ...[
              const SizedBox(height: 4),
              Text(
                reason,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
            ],
            const SizedBox(height: 12),
            _Field(controller: _label, label: 'Menu label', hint: 'Work'),
            _Field(
              controller: _gitName,
              label: 'Git user.name',
              hint: 'Muhammad Fathy',
            ),
            _Field(
              controller: _gitEmail,
              label: 'Git user.email',
              hint: 'you@example.com',
            ),
            _Field(
              controller: _sshKeyPath,
              label: 'SSH private key path',
              hint: '/Users/you/.ssh/id_ed25519_work',
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _handleSave,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
  });

  final TextEditingController controller;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Use the settings screen as the app's home**

In `lib/main.dart`, replace the `home:` argument of `MaterialApp` with:

```dart
      home: SettingsScreen(services: services, tray: tray),
```

and add the import:

```dart
import 'src/ui/settings_screen.dart';
```

- [ ] **Step 3: Analyze and build**

```bash
flutter analyze && flutter build macos --debug
```

Expected: no analyzer errors, build succeeds.

- [ ] **Step 4: Verify settings manually**

```bash
open build/macos/Build/Products/Debug/GitSwitcher.app
```

Confirm, in order:
1. Menu → `Settings…` shows a card per gh account.
2. Fill in `hubot`: label `Personal`, a git name, a git email, and leave the SSH key blank. Press Save.
3. The menu now shows `Personal` as selectable.
4. Closing the settings window with the red button leaves the menu bar icon running.

- [ ] **Step 5: Commit**

```bash
git add lib
git commit -m "feat: add settings screen for editing account details"
```

---

### Task 13: End-to-end verification and release build

**Files:**
- Create: `README.md`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: the finished app.
- Produces: a verified release build and setup documentation.

- [ ] **Step 1: Back up the real SSH config before testing against it**

```bash
cp ~/.ssh/config ~/.ssh/config.pre-gitswitcher
```

- [ ] **Step 2: Record the current state**

```bash
gh auth status 2>&1 | grep -E "account|Active"
git config --global user.name
git config --global user.email
```

Write down the output — Step 5 restores it.

- [ ] **Step 3: Run the full test suite and analyzer**

```bash
flutter analyze && flutter test
```

Expected: no analyzer issues; all tests pass.

- [ ] **Step 4: Build and run the release app**

```bash
flutter build macos --release
open build/macos/Build/Products/Release/GitSwitcher.app
```

- [ ] **Step 5: Perform a real switch and verify every step**

In Settings, configure both accounts with real values, including an SSH key path. Then select the non-active account from the menu and verify:

```bash
gh auth status 2>&1 | grep -B1 "Active account: true"
git config --global user.name
git config --global user.email
sed -n '/>>> GitSwitcher/,/<<< GitSwitcher/p' ~/.ssh/config
ls ~/.ssh/config.gitswitcher-backup-*
```

Expected: the active gh account, the global git identity, and the `IdentityFile` line all match the account you selected, and a backup file exists.

Then confirm the pre-existing config survived:

```bash
grep -A3 "^Host \*" ~/.ssh/config
```

Expected: the original `ServerAliveInterval` / `TCPKeepAlive` block is intact.

Switch back to the original account and confirm everything returns.

- [ ] **Step 6: Verify idempotency**

Select the already-active account again. Expected: the notification reports success, and no new backup file appears:

```bash
ls ~/.ssh/config.gitswitcher-backup-* | wc -l
```

Expected: the same count as after Step 5.

- [ ] **Step 7: Ignore build output**

Append to `.gitignore`:

```
build/
.dart_tool/
```

(`flutter create` may already have added these — check before appending, and do not duplicate lines.)

- [ ] **Step 8: Write the README**

Create `README.md` with exactly this content (the outer fence is four backticks because the content itself contains fenced blocks — do not copy the outer fence into the file):

````markdown
# GitSwitcher

A macOS menu bar app for switching between GitHub accounts. Selecting an account
switches three things at once:

- the active `gh` CLI account (`gh auth switch`)
- the global git commit identity (`git config --global user.name` / `user.email`)
- the `github.com` SSH identity, inside a managed block in `~/.ssh/config`

## Requirements

- macOS
- [GitHub CLI](https://cli.github.com) with each account already logged in:
  `gh auth login`

## Build

```bash
flutter build macos --release
open build/macos/Build/Products/Release/GitSwitcher.app
```

To keep it running across restarts, add the built app to
System Settings → General → Login Items.

## Setup

Open **Settings…** from the menu bar icon. Each account the GitHub CLI knows
about gets a card. Fill in a menu label, your git name and email, and the path
to that account's SSH private key, then press Save. Accounts stay greyed out in
the menu until they have a git email or an SSH key.

## What it writes

| Target | Notes |
|---|---|
| `~/Library/Application Support/.../accounts.json` | this app's own config |
| `~/.ssh/config` | only between the `# >>> GitSwitcher` and `# <<< GitSwitcher` markers; a timestamped backup is written first |
| global `.gitconfig` | `user.name` and `user.email` only |

## Notes

The app runs unsandboxed — it has to execute `gh` and write `~/.ssh/config`,
neither of which is possible inside the macOS app sandbox. It therefore cannot
be distributed through the Mac App Store.
````

- [ ] **Step 9: Restore the pre-test SSH config if anything looks wrong**

If Step 5 produced anything unexpected:

```bash
cp ~/.ssh/config.pre-gitswitcher ~/.ssh/config
```

Otherwise remove the safety copy:

```bash
rm ~/.ssh/config.pre-gitswitcher
```

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "docs: add README and finalize release build"
```
