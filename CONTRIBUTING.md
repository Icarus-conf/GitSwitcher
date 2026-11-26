# Contributing to GitSwitcher

Thanks for helping. GitSwitcher is small on purpose: it does one job, switching
which GitHub account you are, and it edits files people care about
(`~/.gitconfig`, `~/.ssh/config`). So the bar is "does exactly what it says,
and never surprises anyone", more than "has lots of features".

## Ways to help

- **Try it on Windows** and report what looks or behaves wrong. It's the least
  tested platform.
- **Pick up an issue** labelled
  [`good first issue`](../../issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22).
- **Report a bug** with the bug template. The app version, OS, and `gh` and
  `git` versions save a lot of back and forth.
- **Suggest a feature** with the feature template. Say what problem you hit
  first; the fix is easier to agree on after that.

For anything bigger than a bug fix, open an issue before writing code, so we
can agree on the approach first.

## Getting set up

You need [Flutter](https://docs.flutter.dev/get-started/install) (stable;
CI uses the version pinned in `.github/workflows/test.yml`), `git`, and the
[GitHub CLI](https://cli.github.com).

```bash
git clone https://github.com/Icarus-conf/GitSwitcher.git
cd GitSwitcher
flutter pub get
flutter test
```

Run the app:

```bash
flutter run -d macos     # on a Mac (needs Xcode)
flutter run -d windows   # on Windows (needs Visual Studio with C++)
```

**Use a throwaway home folder while you work.** The app edits real config
files on start-up. To keep yours safe, start a built app with `HOME` pointing
somewhere else (macOS):

```bash
flutter build macos --debug
HOME=/tmp/gs-home build/macos/Build/Products/Debug/GitSwitcher.app/Contents/MacOS/GitSwitcher
```

## Before you open a pull request

```bash
flutter analyze     # must report no issues
flutter test        # must pass
```

CI runs both on macOS and Windows, and builds the app on each. The pull
request template has a short checklist.

## How the code is laid out

[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) explains it in a few minutes.
The short version:

| Folder | What lives there |
|---|---|
| `lib/src/models/` | Plain data: accounts, rules, settings |
| `lib/src/services/` | Everything that does something: switching, writing config, gh, installers |
| `lib/src/platform/` | `host.dart` holds **every** macOS/Windows difference; nothing else checks the OS |
| `lib/src/ui/` | Settings window and the menu bar/tray menu |
| `macos/`, `windows/` | Native code: notifications, shortcut, start at login |
| `third_party/tray_manager/` | A patched copy of a plugin (see its README) |
| `tool/` | Scripts for icons, vendoring and publishing releases |

## Rules the code already follows

Please keep to these. Reviews will check for them.

1. **Only touch what's between our markers.** In a user's `~/.gitconfig`,
   `~/.ssh/config` or `~/.zshrc`, GitSwitcher only ever edits the block
   between `# >>> GitSwitcher` and `# <<< GitSwitcher`. Use `ManagedBlock` for
   this; don't write those files any other way.
2. **Back up before changing a user's file**, with `BackupWriter`.
3. **Refuse rather than guess.** If markers are damaged or a file looks
   unexpected, fail with a clear message and write nothing.
4. **One failing step never hides the others.** A switch reports every step's
   result (`SwitchResult`), so the user knows exactly what happened.
5. **Never handle tokens yourself.** Go through `gh`, which keeps them in the
   system keychain. Never log or print one.
6. **OS differences go in `host.dart`.** If you need a path, a command or a
   behaviour that differs between macOS and Windows, add it there.
7. **Test against the real thing where it matters.** Code that writes git
   config is tested by running real `git` and checking what it actually does
   (see `test/services/git_config_writer_test.dart`). Fakes are for slow or
   risky things, like the network.
8. **Comments explain why, not what.** Most files have one or two notes on why
   something is done a non-obvious way. Keep them true when you change the
   code.

## Commit messages

Short and in the imperative, with a prefix:

```
feat: clone a repository as one of your accounts
fix: prune backups on Windows
ci: make releases survive GitHub's bad moments
docs: explain how folder rules work
```

Use the body to say *why*, especially for fixes.

## Releases

Maintainers tag `vX.Y.Z` on `main`. GitHub Actions builds macOS and Windows and
publishes the release, with notes from `.github/release-notes/vX.Y.Z.md` if
that file exists. See `.github/release-notes/README.md`.

## Code of conduct

Be kind and assume good faith. See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE).
