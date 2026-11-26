# Changelog

Each release's full notes are on its
[release page](https://github.com/Icarus-conf/GitSwitcher/releases) and in
[`.github/release-notes/`](.github/release-notes/).

## [0.2.1] — 2026-11-25

The first release with a Windows build.

- **Windows:** a system-tray app with Ctrl+Alt+G, git installed through winget, and native notifications.
- **Identity by folder or organization:** through git's own `includeIf`, so it works in every terminal and editor. HTTPS remotes use the right account too.
- **Account setup:** Fill from GitHub (name and private noreply email), Create SSH key, and per-account commit signing.
- **Account checks:** expired sign-ins, rejected SSH keys, and keys belonging to another account, each with a one-click fix. Plus Test SSH and Check repos.
- **Everyday:** Clone as…, undo the last switch, export and import settings, update notices, and the active account's name in the menu bar.
- **Missing tools:** Settings installs gh (checksum-verified) and git.
- **Fixes:**
  - The SSH key could lose to an earlier key in `~/.ssh/config`.
  - Notifications showed Script Editor's icon.
  - Config backups piled up forever.

## 0.2.0

Tagged but never released: the macOS build failed for macOS 10.15. Fixed in
0.2.1.

## [0.1.1] — 2026-08-16

The first release, for macOS.

- One click switches the `gh` account, the global git name and email, and the SSH key for github.com.
- **Set for a repo** pins a repository to an account.
- **Switch by folder** through a zsh hook (replaced in 0.2.1).
- **Add account** signs in to GitHub from the app.
- **Open at login.**

[0.2.1]: https://github.com/Icarus-conf/GitSwitcher/releases/tag/v0.2.1
[0.1.1]: https://github.com/Icarus-conf/GitSwitcher/releases/tag/v0.1.1
