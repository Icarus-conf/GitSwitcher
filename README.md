# GitSwitcher

[![Test](https://github.com/Icarus-conf/GitSwitcher/actions/workflows/test.yml/badge.svg)](https://github.com/Icarus-conf/GitSwitcher/actions/workflows/test.yml)
[![Latest release](https://img.shields.io/github/v/release/Icarus-conf/GitSwitcher)](https://github.com/Icarus-conf/GitSwitcher/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A menu bar (macOS) and system tray (Windows) app for switching between GitHub
accounts.

Pick an account and it switches three things at once:

- the active `gh` CLI account
- your global git commit name and email
- the SSH key used for `github.com`

Anything you haven't set up is skipped, and the notification tells you exactly
what ran.

## Install

### macOS

1. Download the `-macos.zip` from [Releases](../../releases/latest) and unzip it.
2. Move `GitSwitcher.app` to `/Applications`.
3. **Right-click it and choose Open** the first time.

Step 3 is needed because the app isn't signed with an Apple Developer
certificate. Double-clicking shows a warning with no way past it; right-click →
Open gives you the choice. macOS only asks once.

### Windows

1. Download the `-windows.zip` from [Releases](../../releases/latest) and unzip
   it anywhere, for example into `%LOCALAPPDATA%\Programs`.
2. Run `GitSwitcher\GitSwitcher.exe`. It lives in the system tray.
3. If SmartScreen says "Windows protected your PC", choose **More info → Run
   anyway**. The build isn't code-signed, so Windows asks once.

On Windows the shortcut is **Ctrl+Alt+G**, git installs through `winget`, and
the tray menu shows names without avatars.

To start it automatically, turn on **Open at login** in Settings.

## Setup

GitSwitcher drives the [GitHub CLI](https://cli.github.com) and git. If
either is missing, **Settings…** shows **Finish setting up** with an Install
button for each:

- **gh** is downloaded from its official GitHub release into the app's own
  folder and checked against the SHA-256 GitHub publishes. No admin password
  or Homebrew needed, and it's updated when a new release is out. A gh you
  installed yourself is always preferred and never touched.
- **git** opens Apple's Command Line Tools installer.

Then press **+** in Settings to sign in to each account (or run
`gh auth login`). Every account `gh` knows about gets a card. **Fill from
GitHub** sets its commit name from the profile and its email to GitHub's
private `…@users.noreply.github.com` address, which always links commits to
that account. Or press **Edit** and type your own.

For the SSH key, press **Create SSH key**: it makes a key for that account
(`~/.ssh/gitswitcher_<login>`, no passphrase, so GUI git clients can use it)
and adds it to GitHub for pushing and for signing. Accounts signed in before
this version lack the permission to add keys; for those the key is copied
and GitHub's page opens for you to paste it. Or point the card at a key you
already have.

**⌃⌥⌘G** (Ctrl+Alt+G on Windows) opens the menu from anywhere.

You don't have to fill anything in. An empty account still switches your active
`gh` account, which is enough on its own if you use HTTPS remotes.

## Optional

**Set for a repo** pins one repository to an account. A repo's own identity
beats the global one and ignores later switches, so it's the safest way to keep
the right email on your commits.

**Identity by folder** gives every repo under a folder its own account —
`~/work` to your work account, say. Commits there use that account's name and
email (and signing key), and pushes use its SSH key — or, for HTTPS remotes,
its gh token — in every terminal, editor and git GUI at once. The menu lists
your folders. It uses git's own `includeIf`, so two terminals in
different folders never fight. The menu's account and `gh` don't change.

**Sign commits** (per account) signs with the account's SSH key. Add the same
key to GitHub as a *signing* key, or commits show as Unverified.

**Test SSH** asks GitHub which account a key really signs in as, and warns if
it's not the one you expect.

**Identity by organization** does the same for every repo from a GitHub
organization, wherever it's cloned — even `~/Downloads`. It matches the
repo's remote URL (git 2.36 or later), and beats a folder rule.

**Check repos** looks through your folders for repos that would commit as the
wrong account — their own settings override the rule, or recent commits used
another of your accounts' emails — and can remove such an override.

**Clone** (the download button in Settings) clones `owner/repo` or a URL as an
account you pick, into that account's folder. The clone uses that account
from its first fetch, wherever it lives.

**Account checks** run when Settings opens: a sign-in GitHub no longer
accepts, an SSH key it rejects, or a sign-in that can't add keys each show on
the card with a one-click fix.

**Undo**: right after a switch, the menu offers to go back, and Settings
lists this session's switches.

**Export / Import** moves accounts and rules to another computer, Mac or
Windows. Paths are saved relative to your home folder; SSH keys aren't
included. Importing adds and updates, and never removes anything.

**Updates**: when a newer release is out, the menu shows **Update to …**,
which downloads it.

**Add account** signs in to a new GitHub account without leaving the app.

## What it changes

| File | What |
|---|---|
| `~/.ssh/config` | only between its own `# >>> GitSwitcher` markers |
| global `.gitconfig` | `user.name` and `user.email`; plus, only if you add a folder or sign commits, a block between the same markers that includes files from the app's folder |
| `~/.zshrc` | nothing now — an older version's folder hook is removed on first launch |
| a repo's `.git/config` | only a repo you pick yourself |
| `~/Library/Application Support/io.github.icarusconf.gitswitcher/` (macOS), `%APPDATA%\io.github.icarusconf\GitSwitcher\` (Windows) | its own settings and cached avatars |
| `HKCU\…\CurrentVersion\Run` (Windows) | one `GitSwitcher` value, only while **Open at login** is on |

On Windows, `~` is your user folder (`%USERPROFILE%`), the same place git and
ssh use.

Everything outside those markers is left untouched, and a backup is written
before each change. If the markers are ever damaged, it refuses to write and
tells you instead of guessing.

Backups are kept as `<file>.gitswitcher-backup-*`, the newest five per file.
They hold no secrets and are safe to delete.

The app never sees your credentials. Every GitHub call goes through `gh`, which
keeps its tokens in the macOS keychain.

## Build from source

```bash
flutter test
flutter build macos --release      # on a Mac
flutter build windows --release    # on Windows
```

`tray_manager` is vendored in `third_party/` with a small patch, because the
published version ignores menu-item icons. Run `tool/vendor_tray_manager.sh` to
upgrade it — see `third_party/README.md`.

## Contributing

Contributions are welcome: bug reports, Windows testing, and pull requests.
Start with [CONTRIBUTING.md](CONTRIBUTING.md), which covers setup, how the code
is laid out ([docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)), and the few rules
the code follows. Please report security problems privately, as described in
[SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE). `third_party/tray_manager` is a patched copy of
[tray_manager](https://pub.dev/packages/tray_manager), also MIT-licensed; see
its own LICENSE.
