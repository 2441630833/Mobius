# Terminal Installer Sync Update Support & GitHub Pages Sync

> Date: 2026-10-13  
> Target: Enable one-line terminal installer command to automatically detect existing Mobius installations and perform seamless updates to the latest release, and reflect this capability on the GitHub Pages website.

---

## 1. Root Cause & Background

The current one-line terminal commands on the GitHub Pages site:
- macOS: `curl -fsSL https://raw.githubusercontent.com/2441630833/Mobius/main/scripts/install-mac.sh | bash`
- Windows: `irm https://raw.githubusercontent.com/2441630833/Mobius/main/scripts/install-win.ps1 | iex`
- Linux: `curl -fsSL https://raw.githubusercontent.com/2441630833/Mobius/main/scripts/install-linux.sh | bash`

were written primarily for a fresh install flow:
1. They do not inspect whether Mobius is already installed locally or what version is currently running.
2. If the user already has Mobius installed, running the command will re-download the entire payload (up to 1.7 GB on Windows) even if the local version is already up-to-date.
3. If Mobius is currently open/running, running the installer concurrently can lead to file-in-use locks (e.g. Inno Setup process blocks, DMG mount or /Applications replace errors).
4. The GitHub Pages site displays the widget solely as "一键安装命令" (One-Click Install Command), giving users no indication that this command can also be used as a simple update/sync mechanism.

## 2. Goal

1. **Intelligent Local Detection**:
   - Detect whether Mobius is already installed on the machine across Windows, macOS, and Linux.
   - Read the currently installed version number and commit/build information.
2. **Release Comparison & Sync Update**:
   - Query GitHub Releases for the latest release tag and downloadable binary/installer.
   - If Mobius is not installed: Perform a fresh installation.
   - If Mobius is installed and a newer version exists (or if forced via `-Force` / `--force`):
     - Notify the user of the update: `Current: vX.X.X -> Latest: vY.Y.Y`.
     - Safely check for and terminate running Mobius processes with clear user notices to avoid file locking.
     - Perform in-place upgrade preserving user settings and data.
     - Confirm successful update.
   - If Mobius is installed and already at the latest release:
     - Clearly notify user: `Mobius is already at the latest version (vX.X.X)!`
     - Provide option to re-run with `-Force` / `--force` to reinstall, and exit cleanly without redundant multi-gigabyte downloads.
3. **GitHub Pages (`index.html`, `web/index.html`, `docs/index.html`) Sync**:
   - Update the terminal card header/title to "一键安装与更新命令" (One-Line Install & Update).
   - Add status badge / subtitle clarifying both fresh install and sync update capabilities.
   - Add a helpful tip banner/callout explaining that existing users can run the command at any time to upgrade in-place.

## 3. Non-Goals

- Modifying the underlying Electron/VSCode build pipeline or Inno Setup compiler configuration.
- Touching unrelated submodules (`vendor/*`, `hermes-agent`) or untracked image assets.

## 4. Tasks

1. [x] Upgrade `scripts/install-win.ps1`:
   - Add local installation detection (check `%LOCALAPPDATA%\Programs\Mobius`, `%ProgramFiles%\Mobius`, and PATH `mobius.cmd`/`Mobius.exe`).
   - Query remote releases and compare versions (semver / release tag comparison).
   - Gracefully check running `Mobius` processes before installation.
   - Add `-Force` parameter support to allow reinstalling even if already latest.
   - Fix fallback URL if API rate-limited to existing release asset.
2. [x] Upgrade `scripts/install-mac.sh`:
   - Detect `/Applications/Mobius.app` and read `CFBundleShortVersionString` via `defaults read` or `PlistBuddy`.
   - Query remote release and compare versions.
   - If running, terminate `Mobius` gracefully before replacing `/Applications/Mobius.app`.
   - Add `--force` / `-f` support.
3. [x] Upgrade `scripts/install-linux.sh`:
   - Detect existing `mobius` via `dpkg -s mobius` or `mobius --version`.
   - Query remote release and compare versions.
   - Safely perform update or inform user if already latest.
   - Add `--force` / `-f` support.
4. [x] Synchronize GitHub Pages (`index.html`, `web/index.html`, `docs/index.html`):
   - Update terminal widget title from "一键安装命令" to "一键安装与更新命令".
   - Add badge or indicator for "首次安装 · 自动更新".
   - Add informative note explaining that running the command on an existing installation performs a zero-loss sync update to the latest compiled release.
5. [x] Verify scripts syntax, lint, and test local execution with powershell.
6. [x] Git commit using clean UTF-8.

## 5. Acceptance Criteria

- `scripts/install-win.ps1` runs safely, detects existing local Mobius `1.126.0`, compares with latest release, handles running processes, and supports `-Force`.
- `scripts/install-mac.sh` and `scripts/install-linux.sh` have matching detection, comparison, and update logic with `--force`.
- `index.html`, `web/index.html`, and `docs/index.html` all display updated "一键安装与更新" copywriting and update instructions.
- Zero PowerShell syntax errors or broken HTML.
