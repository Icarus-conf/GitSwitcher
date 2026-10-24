# GitSwitcher

A macOS menu bar app for switching between GitHub accounts.

Pick an account and it switches three things at once:

- the active `gh` CLI account
- your global git commit name and email
- the SSH key used for `github.com`

Anything you haven't set up is skipped, and the notification tells you exactly
what ran.

## Install

1. Download the zip from [Releases](../../releases/latest) and unzip it.
2. Move `GitSwitcher.app` to `/Applications`.
3. **Right-click it and choose Open** the first time.

Step 3 is needed because the app isn't signed with an Apple Developer
certificate. Double-clicking shows a warning with no way past it; right-click →
Open gives you the choice. macOS only asks once.

To start it automatically, turn on **Open at login** in Settings.

## Setup

You need the [GitHub CLI](https://cli.github.com), signed in to each account:

```bash
gh auth login
```

Then open **Settings…** from the menu bar icon. Every account `gh` knows about
gets a card. Fill in a label, your git name and email, and the path to that
account's SSH key.

You don't have to fill anything in. An empty account still switches your active
`gh` account, which is enough on its own if you use HTTPS remotes.

## Optional

**Set for a repo** pins one repository to an account. A repo's own identity
beats the global one and ignores later switches, so it's the safest way to keep
the right email on your commits.

**Switch by folder** changes account when your terminal enters a folder you've
mapped — `~/work` to your work account, say. It adds a small hook to your
`~/.zshrc`; **Remove hook** takes it back out. Open a new terminal tab after
installing, and note that nothing happens until you add at least one folder.

**Add account** signs in to a new GitHub account without leaving the app.

## What it changes

| File | What |
|---|---|
| `~/.ssh/config` | only between its own `# >>> GitSwitcher` markers |
| `~/.zshrc` | only if you install the folder hook, same markers |
| global `.gitconfig` | `user.name` and `user.email` |
| a repo's `.git/config` | only a repo you pick yourself |
| `~/Library/Application Support/io.github.icarusconf.gitswitcher/` | its own settings and cached avatars |

Everything outside those markers is left untouched, and a backup is written
before each change. If the markers are ever damaged, it refuses to write and
tells you instead of guessing.

Backups pile up as `~/.ssh/config.gitswitcher-backup-*`. They hold no secrets
and are safe to delete.

The app never sees your credentials. Every GitHub call goes through `gh`, which
keeps its tokens in the macOS keychain.

## Build from source

```bash
flutter build macos --release
flutter test
```

`tray_manager` is vendored in `third_party/` with a small patch, because the
published version ignores menu-item icons. Run `tool/vendor_tray_manager.sh` to
upgrade it — see `third_party/README.md`.
