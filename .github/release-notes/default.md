A menu bar (macOS) and system tray (Windows) app for switching GitHub accounts.

## Install on macOS

1. Download the `-macos.zip` below and unzip it.
2. Move `GitSwitcher.app` to `/Applications`.
3. **Right-click the app and choose Open** the first time.

That third step is needed because this build is not signed with an Apple Developer certificate. Double-clicking shows a Gatekeeper warning with no way past it; right-click → Open lets you run it anyway. macOS only asks once.

## Install on Windows

1. Download the `-windows.zip` below and unzip it anywhere, for example into `%LOCALAPPDATA%\Programs`.
2. Run `GitSwitcher\GitSwitcher.exe`. It lives in the system tray.
3. If SmartScreen says "Windows protected your PC", choose **More info → Run anyway**. The build is not code-signed, so Windows asks once.

## Requirements

The [GitHub CLI](https://cli.github.com), signed in to each account you want to switch between. If it's missing, GitSwitcher can install it for you.
