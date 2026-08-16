# GitSwitcher v2 Implementation Plan

**Goal:** Add avatars, per-repo identity, directory-based auto-switching, and in-app `gh auth login`.

**Decisions already made:** auto-switching uses a zsh `chpwd` hook; multi-host / GitHub Enterprise is out of scope.

**Executed inline** in the same session that wrote it, so tasks record interfaces and decisions rather than full code listings.

## Global Constraints

- Everything stays local. No backend, no stored credentials — `gh` holds the tokens and we shell out to it.
- Every new rule lives in plain Dart behind injected paths and the injected `ProcessRunner`, and is unit-tested.
- Managed blocks in user-owned files (`~/.ssh/config`, `~/.zshrc`) use the same marker + backup contract.
- Commit after every task. `flutter analyze` and `flutter test` must be clean before each commit.

---

### Task 1: Vendor a patched tray_manager

`tray_manager` 0.5.3's `TrayMenu.swift` reads only `id`, `type`, `label`, `toolTip`, `checked`, `disabled`. It ignores `icon` and `sublabel`, so menu avatars are impossible and the setup hint never renders.

- Copy the package to `third_party/tray_manager`, add a `dependency_overrides` entry.
- Patch `TrayMenu.swift`: load `icon` into `menuItem.image` (sized 16x16, `isTemplate = false` so avatars keep their colour) and map `sublabel` onto an attributed title.
- Record the patch in `third_party/README.md` so the change is not mistaken for upstream.
- Verify: menu shows an image and a secondary line.

### Task 2: GitHub profile fetch and avatar cache

- `GitHubProfile { login, name, avatarUrl }`.
- `ProfileClient.fetch(login)` → `gh api users/<login>`, parsed from JSON. Works for any account regardless of which is active (verified: `gh api users/hubot` returns the profile while `octocat` is active).
- `AvatarCache.pathFor(login)` → downloads `avatarUrl` + `&s=64` once into Application Support, returns the local file path. Cache hit skips the network entirely; a failed download returns null and the UI falls back to no image.
- Failure is never fatal: no network means no avatar, not a broken menu.

### Task 3: Show avatars in the menu and Settings

- `TrayController` passes the cached avatar path as `MenuItem.icon`, and the setup hint as `sublabel` (now that Task 1 makes both render).
- Settings cards show the avatar and the account's real name next to the username.
- Avatars refresh in the background on launch; the menu never blocks on the network.

### Task 4: Extract the managed-block helper

`SshConfigWriter`'s marker logic is about to be needed verbatim for `~/.zshrc`.

- Extract `ManagedBlock { begin, end, replace(existing, block), }` as a standalone tested unit.
- `SshConfigWriter` delegates to it; its existing tests must keep passing unchanged.
- Shared backup helper: timestamped copy before any write.

### Task 5: Per-repo identity

- `RepoIdentityWriter.apply(account, repoPath)` → `git -C <repo> config --local user.name/user.email`.
- Guards: the path must exist and contain a `.git` entry, otherwise a clear failure.
- Settings: each account card gets "Apply to a repo…", opening a folder picker (`file_selector`).
- This is the safest way to use the app day to day — a repo's local identity survives every global switch.

### Task 6: Directory rules and the zsh hook

- `DirectoryRule { pathPrefix, ghUsername }`, stored in `accounts.json` alongside accounts (schema version 2, migrated from 1).
- `RuleMatcher.match(path, rules)` → longest matching prefix wins, `~` expanded.
- `ShellHookInstaller` writes a managed block into `~/.zshrc` (reusing Task 4) containing a `chpwd` hook that writes `$PWD` to a known state file. Install and uninstall are both offered; a backup is written first.
- `CwdWatcher` watches that state file and reports directory changes.
- `AutoSwitcher` ties them together: on change, match a rule, and switch only when the target differs from the active account. Never switches when auto-switch is disabled.
- Settings: a toggle, install/remove hook buttons, and a rules editor.

### Task 7: In-app `gh auth login`

- `ProcessRunner` gains `start()` for streamed output; `Process.run` cannot surface the one-time code while the command is still running.
- `GhLoginSession` runs `gh auth login --hostname github.com --git-protocol https --web`, scrapes the one-time code from the stream, and exposes it plus completion.
- Settings shows the code with a copy button; `gh` opens the browser itself.
- On success, accounts reload so the new login appears immediately.

### Task 8: Verification and docs

- Full suite and analyzer clean; release build.
- Live checks: avatars present, a repo's local identity set, the zsh hook firing on `cd`, and `~/.zshrc` outside the markers untouched.
- README updated to cover the new features and the vendored plugin.
