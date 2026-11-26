# Security

GitSwitcher edits `~/.ssh/config` and `~/.gitconfig`, creates SSH keys, and
asks `gh` for account tokens. Security problems matter here, so please report
them privately.

## Reporting a problem

Use [**Report a vulnerability**](https://github.com/Icarus-conf/GitSwitcher/security/advisories/new)
on this repository. Please don't open a public issue. You'll get a reply as
soon as the maintainer can look, and credit in the release notes if you'd
like it.

Useful to include: what an attacker could do, the steps to reproduce it, and
the GitSwitcher version and OS.

## What's in scope

- Anything that leaks a token or private key: to logs, notifications, other
  processes, or files other users can read.
- Writing outside GitSwitcher's marked blocks in a user's files, or skipping
  the backup.
- Running something the user didn't choose, for example through an injected
  config value, a URL, or a downloaded tool that skipped its checksum.

## How the app handles secrets

- It never stores GitHub tokens. `gh` keeps them in the system keychain, and
  the app asks `gh` for one only for the command that needs it.
- Downloaded tools (`gh`) are checked against the SHA-256 GitHub publishes
  before they're installed.
- SSH keys it creates are readable only by you.

## Supported versions

Only the latest release gets fixes.
