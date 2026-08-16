# GitSwitcher — Design

**Date:** 2026-08-15
**Status:** Approved

## Purpose

A macOS menu bar app for switching between GitHub accounts (personal, work, etc.). Selecting an
account switches the active `gh` CLI account, the global git commit identity, and the SSH identity
used for `github.com`, in one click.

## User-facing behavior

The app runs with no Dock icon and no visible window. Its only persistent surface is a menu bar
icon. Clicking the icon opens a native macOS dropdown containing:

- One item per configured account, with a checkmark on the currently active one. The item text is
  the account's `label` when set, falling back to its `ghUsername`.
- A separator
- `Settings…`
- `Quit`

Selecting an account performs the switch and posts a native notification reporting the result.
Accounts whose configuration is incomplete are shown disabled with a hint to open Settings.

`Settings…` opens a Flutter window listing all known accounts with editable fields.

## Sandbox

Flutter macOS apps are generated with `com.apple.security.app-sandbox` enabled. A sandboxed app
cannot execute `gh`, read `~/.config/gh/hosts.yml`, or write `~/.ssh/config` — all three are
required by this app's core function. The sandbox is therefore disabled in both
`macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`.

Consequence: the app cannot be distributed via the Mac App Store. Accepted; this is a personal
tool distributed as a local build.

## The switch operation

Switching to an account runs three independent steps. Each reports success or failure separately;
one failing step does not abort the others, and the result reports per-step outcomes so a partial
switch is visible rather than silent.

### Step 1 — gh CLI active account

```
gh auth switch --hostname github.com --user <ghUsername>
```

Failure modes: `gh` binary not found, account not logged in, non-zero exit. The stderr text is
carried into the result.

### Step 2 — global git identity

```
git config --global user.name  <gitName>
git config --global user.email <gitEmail>
```

If either value is empty in the account config, the step is skipped and reported as skipped, not
failed.

### Step 3 — SSH identity for github.com

The app owns a marked region of `~/.ssh/config`:

```
# >>> GitSwitcher (managed — do not edit)
Host github.com
    HostName github.com
    User git
    IdentityFile <sshKeyPath>
    IdentitiesOnly yes
# <<< GitSwitcher
```

Rules:

- Only text between the markers is ever rewritten. Content outside is preserved byte-for-byte,
  including the user's existing `Host *` keepalive block.
- If the markers are absent, the block is appended to the end of the file.
- If `~/.ssh/config` does not exist, it is created with mode `0600`.
- A timestamped backup (`~/.ssh/config.gitswitcher-backup-<epoch>`) is written before each
  modification.
- If an opening marker exists without a matching closing marker, the file is treated as
  malformed: no write occurs and the step fails with an explanatory message.
- If `sshKeyPath` is empty in the account config, the step is skipped, not failed.

## Binary resolution

GUI applications launched from Finder do not inherit the login shell's `PATH`, so
`Process.run('gh', …)` fails inside a bundled `.app` even when `gh` works in the terminal.

`BinaryLocator` resolves an executable by probing, in order:

1. `/opt/homebrew/bin/<name>`
2. `/usr/local/bin/<name>`
3. `/usr/bin/<name>`
4. `zsh -lc 'which <name>'` as a fallback

Resolved paths are cached for the process lifetime. A failed resolution surfaces as a specific
"gh CLI not found" error rather than a generic exec failure.

## Account discovery and storage

### Discovery

Accounts are discovered by reading `~/.config/gh/hosts.yml`, which lists the logged-in users and
the active user in a structured format:

```yaml
github.com:
    users:
        octocat:
        hubot:
    git_protocol: https
    user: octocat
```

This is preferred over parsing `gh auth status` output, which is human-formatted and unstable.
If `hosts.yml` is missing or unparseable, the app falls back to parsing `gh auth status`.

Only the `github.com` host is read. Other hosts (GitHub Enterprise) are ignored in v1.

### Storage

The app's own configuration lives at:

```
~/Library/Application Support/GitSwitcher/accounts.json
```

Schema:

```json
{
  "version": 1,
  "accounts": [
    {
      "ghUsername": "octocat",
      "label": "Work",
      "gitName": "octocat",
      "gitEmail": "you@work.example.com",
      "sshKeyPath": "/Users/me/.ssh/id_ed25519_work"
    }
  ]
}
```

`ghUsername` is the primary key and is the value discovered from `hosts.yml`. The remaining fields
are user-supplied via Settings. An account with an empty `gitEmail` and empty `sshKeyPath` is
"incomplete" — it appears in the menu but disabled.

### Merge behavior

On launch, and on each menu open, discovered usernames are merged with stored accounts:

- Discovered username with no stored entry → a new incomplete entry is created in memory and shown
  disabled. It is persisted once the user edits it in Settings.
- Stored entry whose username is no longer discovered → shown disabled with a "not logged in to gh"
  hint. It is never auto-deleted; the user removes it explicitly.

### Active account

The active account is read fresh from `hosts.yml` every time the menu is opened, so the checkmark
remains correct even when `gh auth switch` is run directly in a terminal.

## Components

| Unit | Responsibility | Depends on |
|---|---|---|
| `ProcessRunner` | Interface over process execution; real and fake implementations | — |
| `BinaryLocator` | Resolves absolute paths to `gh` and `git` | `ProcessRunner` |
| `AccountStore` | Loads and saves `accounts.json` | injected file path |
| `GhClient` | Parses `hosts.yml`, reports active user, runs `gh auth switch` | `ProcessRunner`, `BinaryLocator`, injected path |
| `GitIdentityWriter` | Reads and writes global git `user.name` / `user.email` | `ProcessRunner`, `BinaryLocator` |
| `SshConfigWriter` | Managed-block read/rewrite with backup | injected file path |
| `AccountSwitcher` | Orchestrates the three steps, returns `SwitchResult` | the three writers above |
| `TrayController` | Builds the NSMenu from accounts + active state, handles selection | `AccountSwitcher`, `GhClient`, `AccountStore` |
| `SettingsScreen` | Flutter UI for editing account fields | `AccountStore` |

Every unit except `TrayController` and `SettingsScreen` is plain Dart with injected paths and an
injected `ProcessRunner`, so it is testable without touching the real filesystem or a real `gh`.

### Result type

```dart
enum StepStatus { ok, skipped, failed }

class StepResult {
  final String name;          // "gh", "git identity", "ssh"
  final StepStatus status;
  final String? message;      // failure detail, shown to the user
}

class SwitchResult {
  final String ghUsername;
  final List<StepResult> steps;
  bool get allOk;
  bool get anyFailed;
}
```

## Packages

- `tray_manager` — menu bar icon and native `NSMenu`
- `window_manager` — keeps the main window hidden until Settings is opened
- `path_provider` — resolves Application Support directory
- `yaml` — parses `hosts.yml`

`Info.plist` sets `LSUIElement` to `true` so no Dock icon appears. Opening Settings calls
`NSApp.activate(ignoringOtherApps:)` via `window_manager` so the window comes to the front despite
being an accessory app.

## Error handling

- **`gh` not installed** — menu shows a single disabled item, "GitHub CLI not found", plus Settings
  and Quit. Settings shows install guidance.
- **`hosts.yml` unreadable** — falls back to `gh auth status` parsing; if that also fails, the menu
  shows "No accounts found".
- **A switch step fails** — the other steps still run. A notification reports which steps failed
  and why.
- **Malformed SSH managed block** — the SSH step fails without writing; the file is left untouched.
- **`accounts.json` corrupt** — the file is renamed to `accounts.json.corrupt-<epoch>` and a fresh
  config is created, so a bad file never blocks startup.

## Testing

Test-driven, with tests written before implementation for each unit.

Unit tests, using a fake `ProcessRunner` and temp directories:

- `AccountStore` — round-trip, missing file, corrupt file recovery, schema version handling
- `GhClient` — `hosts.yml` parsing (multiple users, single user, missing `user` key, malformed
  YAML), `gh auth status` fallback parsing, switch command construction, non-zero exit handling
- `GitIdentityWriter` — command construction, empty-value skip, non-zero exit handling
- `SshConfigWriter` — the largest suite: block absent (append), block present (replace in place),
  content outside markers preserved, file missing (create with `0600`), opening marker without
  closing marker (fail without writing), idempotent repeat writes, backup file created
- `BinaryLocator` — probe order, fallback to `zsh -lc`, not-found error
- `AccountSwitcher` — all steps ok, one step failed with the others still running, skipped steps,
  result aggregation

`TrayController` and `SettingsScreen` are kept thin and verified by running the app.

## Out of scope for v1

- Avatars or any GitHub API calls
- Per-repository identity (`git config --local`)
- GitHub Enterprise / multiple hosts
- Automatic switching based on the current directory or repository
- Adding or removing `gh` logins from within the app (use `gh auth login`)
- Code signing, notarization, and distribution
