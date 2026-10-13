# Plan: Ensure Mobius on macOS Always Defaults to Agent View

## Root Cause
On macOS, Mobius opened in Agent view on first launch, but subsequently defaulted to Editor view due to platform lifecycle and entry point discrepancies:

1. **macOS Dock Activate Lifecycle (`app.on('activate')`)**:
   - On Windows, closing the window terminates the application process. Re-launching Mobius is always a fresh cold start which triggers `app.ts:openFirstWindow` -> `openAgentsWindow` (Agent view).
   - On macOS, clicking the red window close button (or `Cmd+W`) closes the window, but does **not** terminate the process. Mobius remains running in the Dock with 0 windows.
   - When the user clicks the Dock icon to re-open Mobius, Electron emits `app.on('activate')`. In `src/vs/code/electron-main/app.ts`, line 478 previously hard-coded:
     `if (!hasVisibleWindows) { await this.windowsMainService?.openEmptyWindow({ context: OpenContext.DOCK }); }`
     This opened a standard empty VS Code editor window (Editor view) instead of the Agents window!
   - Furthermore, if an Editor view was already open, clicking the Dock icon simply focused the Editor window because no check was made for an Agents window.

2. **Second-instance Launch (`launchMainService.ts`)**:
   - When Mobius is re-opened from Spotlight, Finder, or CLI while already running, `launchMainService.ts` lines 161-164 checked `this.windowsMainService.getLastActiveWindow()`. If the user had opened an Editor view (or Dock activate had opened one), it re-focused the Editor view instead of the Agent view.

3. **macOS Dock Context Menu "New Window" (`menubar.ts`)**:
   - In `menubar.ts` line 295, the Dock menu "New Window" action called `openEmptyWindow({ context: OpenContext.DOCK })`, opening an Editor view instead of the Agent view.

4. **Window Session Restore Filter (`windowsMainService.ts`)**:
   - In `windowsMainService.ts:filterAgentsWindowFromSessionRestore`, `agentSessionsWorkspace` was explicitly stripped from session restore, causing restored sessions to discard the Agents window and fallback to `EMPTY_WINDOW`.
   - When multiple windows were restored on startup, window focus prioritized the last restored window rather than the Agents window.

5. **Shell Launcher Discrepancy (`scripts/launch-ide-mac.sh`)**:
   - `scripts/launch-ide.ps1` explicitly launches with `--agents --disable-workspace-trust` when no arguments are provided, whereas `scripts/launch-ide-mac.sh` did not supply these defaults.

## Goal
1. Ensure Mobius on macOS defaults to the Agent view on every open/re-open, regardless of whether an Editor view was previously opened or is currently open.
2. In `app.ts`, update `app.on('activate')` and `app.on('new-window-for-tab')` so that for Mobius (`isMobiusProduct`), it focuses an existing Agents window or opens a new Agents window.
3. In `launchMainService.ts`, when Mobius is invoked without arguments, find and focus any existing Agents window, or open a new Agents window.
4. In `menubar.ts`, update macOS Dock menu "New Window" to open the Agents window for Mobius.
5. In `windowsMainService.ts`, stop stripping `agentSessionsWorkspace` in `filterAgentsWindowFromSessionRestore`, and ensure that if multiple windows are restored on startup, the Agents window is prioritized for focus.
6. Align `scripts/launch-ide-mac.sh` with `scripts/launch-ide.ps1` to pass `--agents --disable-workspace-trust` when launched without arguments.
7. Compile and verify TypeScript client without errors.

## Non-goals
- Disabling the user's ability to intentionally open an Editor view when opening a folder or project (`File -> Open Folder...` or `mobius <folder>`).
- Modifying submodules other than `vscode`.

## Tasks
1. [x] Update `vscode/src/vs/code/electron-main/app.ts` (`app.on('activate')` and `app.on('new-window-for-tab')`).
2. [x] Update `vscode/src/vs/platform/launch/electron-main/launchMainService.ts` to prioritize/open the Agents window when launched without paths.
3. [x] Update `vscode/src/vs/platform/menubar/electron-main/menubar.ts` for macOS Dock "New Window" menu item.
4. [x] Update `vscode/src/vs/platform/windows/electron-main/windowsMainService.ts` (`filterAgentsWindowFromSessionRestore` and focus prioritization).
5. [x] Update `scripts/launch-ide-mac.sh` to default to `--agents --disable-workspace-trust`.
6. [x] Compile VS Code client (`npm run compile-client` or `scripts/compile-vscode.ps1`) and check diagnostics.
7. [x] Verify git status and commit cleanly with encoding-safe commit.

## Acceptance Criteria
- On macOS, when clicking the Dock icon with no visible windows, Mobius opens the Agent view (Image 1).
- If an Editor view is open and user opens/activates Mobius without arguments, the Agent view is opened or focused.
- Dock "New Window" opens the Agent view.
- Cold restart with session restore restores and focuses the Agent view.
- Clean compilation without TypeScript errors.
