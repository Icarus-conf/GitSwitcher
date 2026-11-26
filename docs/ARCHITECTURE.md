# How GitSwitcher works

A tour for contributors. It's a small app: about 30 Dart files plus a little
native code per platform.

## The one job

Picking an account changes four things at once, each a separate step in
`AccountSwitcher` (`lib/src/services/account_switcher.dart`):

| Step | Service | What it changes |
|---|---|---|
| `gh` | `GhClient` | the GitHub CLI's active account (`gh auth switch`) |
| `git identity` | `GitIdentityWriter` | global `user.name` and `user.email` |
| `ssh` | `SshConfigWriter` | the `IdentityFile` for `github.com` in `~/.ssh/config` |
| `git config` | `GitConfigWriter` | the managed block in `~/.gitconfig` (signing, rules) |

Steps run independently. One failing does not stop the others, and the
notification lists exactly what ran, was skipped, or failed (`SwitchResult`).

## Where state lives

- **The app's own settings:** `accounts.json` in the app support folder
  (`AccountStore`, `AppConfig`): accounts, folder rules, organization rules.
- **Which accounts exist and which is active:** gh, not us.
  `GhClient.discover()` reads gh's `hosts.yml`. The app never stores tokens.
- **User files we edit:** only inside marked blocks (`ManagedBlock`), each
  with a backup first (`BackupWriter`, which keeps the newest five).

The SSH block goes at the **top** of `~/.ssh/config`, because ssh uses the
first `IdentityFile` it finds. The git block goes at the **end** of
`~/.gitconfig`, because git lets the last value win. Both are moved back into
place on every write.

## Folder and organization rules

These don't switch anything. They lean on git's own conditional includes, so
they work in every terminal and editor at once:

```ini
# The managed block at the end of ~/.gitconfig
[includeIf "gitdir:/Users/me/work/"]
    path = ".../git/accounts/work-login.gitconfig"
[includeIf "hasconfig:remote.*.url:git@github.com:acme/**"]
    path = ".../git/accounts/work-login.gitconfig"
```

Each account has its own include file (`GitConfigWriter.folderLines`) with:

- `user.name` / `user.email`
- `core.sshCommand` using that account's key
- a credential helper that asks `gh auth token --user <login>`, so HTTPS
  remotes use the right account too
- commit signing settings, if the account signs

Organization rules come after folder rules, so an organization beats a
folder. **Clone as…** (`RepoCloner`) points a single repo at the same file
with `include.path`.

## macOS and Windows

`lib/src/platform/host.dart` holds every difference between the two
(paths, commands, `.exe` names, how to open a URL), and nothing else checks
the OS. Native code is small:

| Feature | macOS | Windows |
|---|---|---|
| Notifications | `MainFlutterWindow.swift` (UNUserNotificationCenter) | tray balloon, via the patched `third_party/tray_manager` |
| Global shortcut | Carbon `RegisterEventHotKey` | `RegisterHotKey` in `windows/runner/flutter_window.cpp` |
| Open at login | SMAppService | the per-user `Run` registry key (`launch_at_login.dart`) |

## The menu and Settings

- `TrayController` owns the menu bar/tray icon and menu. It rebuilds the
  menu every time it opens, so it's right even after `gh auth switch` in a
  terminal.
- `SettingsScreen` is the window: account cards (`AccountSlab`), rules
  (`AutoSwitchSection`), setup, and the background account checks.
- `AppServices` wires the real implementations together. Tests build the
  pieces they need with fakes (`test/support/fake_process_runner.dart`).

## Tests

- **Fake commands** for logic: `FakeProcessRunner` records command lines and
  returns canned output. `test/flutter_test_config.dart` pins these tests to
  macOS behaviour, so they mean the same thing on Windows CI.
- **Real tools** where correctness depends on them: git config, cloning, the
  repo check, the installer's unzip, ssh-keygen. These run on whichever system
  runs the suite.
- `test/tool/publish_release_test.dart` runs the release script against a
  fake `gh` that fails the way GitHub's API does.

## Releases

A `vX.Y.Z` tag runs `.github/workflows/release.yml`:

1. macOS and Windows build in parallel and keep their zips as artifacts.
2. A publish job runs `tool/publish_release.sh`. It retries GitHub's API
   errors and confirms each upload by its SHA-256.
