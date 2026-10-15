# Windows one-line installer completion

## Root cause

`scripts/install-win.ps1`, invoked by the Windows command in `main.js`,
`docs/main.js`, and `web/main.js`, only exits when `MOBIUS_AUTO_CLOSE=1`.
It has no desktop notification, ignores the Inno Setup exit code, and starts
Electron without isolating its console output. Failed installs can be recorded
and announced as successful.

## Goal

After a verified successful Windows installation/update, show a Windows Toast,
launch Mobius without writing into the installer console, and close the shell
by default. Preserve diagnostics on failure and support keeping the shell open.

## Non-goals

Do not change macOS/Linux installers, website styling, installed user data,
release publication, or unrelated work. Preserve all pre-existing changes:
`.github/agents/PPT.agent.md`, the three website copies (`index.html`, `main.js`,
`styles.css` at root, `docs/`, and `web/`), `vscode`, `hermes-agent`,
`vendor/fastmcp`, `vendor/litex`, `vendor/litex-boards`, `vendor/mcp-python-sdk`,
`vendor/openFPGALoader`, the untracked OCR/Pages/PPT plan documents, and
`scripts/patch-ide-ppt-master.ps1`. Keep existing submodule deviations, including
uninitialized `godogen`; do not reset their pointers or initialize unrelated code.

## Tasks

1. [x] Inspect the installer, website command, Inno Setup launch tasks, and
   open-source precedents: ScoopInstaller/Install exit handling,
   JanDeDobbeleer/oh-my-posh install flow, Windos/BurntToast notifications.
2. [x] Fix `scripts/install-win.ps1`: success-only default exit with `-KeepOpen`
   and `MOBIUS_AUTO_CLOSE=0` overrides; native Windows Toast with a registered
   AppUserModelID; isolated GUI launch; verify exit code and installed executable;
   clean temporary download in `finally`; only then record the release tag.
3. [x] Add focused installer regression coverage under `scripts/`, using mocked
   release/download/process/notification operations and isolated temporary paths.
   Exercise fresh install, update, already current, check-only, failed installer,
   missing executable, notification failure, launch isolation, and default exit.
4. [x] Run PowerShell parser diagnostics, `Get-Command -Syntax`, regression tests
   on Windows PowerShell 5.1 and PowerShell 7, `npm run check`, and `npm run compile`.
   Record actual results and any environmental build blockers. The provided tool
   set has neither `get_errors` nor `manage_todo_list`; use PowerShell AST parser
   diagnostics and this checked task list as their available equivalents.
5. [x] Review only intended changes, stage installer/tests/this plan together,
   commit once with ASCII message `fix: finish Windows installer with toast and automatic exit`,
   and verify final status contains only the preserved pre-existing changes.

## Acceptance criteria

- The existing GitHub Pages command closes its shell only on successful completion;
  `-KeepOpen` / `MOBIUS_AUTO_CLOSE=0` preserve it and check-only never closes it.
- Native Toast distinguishes installation, update, and already-current outcomes.
- A nonzero installer exit or missing installed executable never writes a release
  marker, launches the app, sends a success Toast, or closes the error console.
- The launched GUI cannot continue writing application logs into this console.
- Downloaded temporary files are cleaned on success and failure.
- Focused behavioral tests and PowerShell syntax checks pass; full build results
  are recorded, and unrelated changes remain untouched.

## Verification results

- PowerShell parser diagnostics and `Get-Command -Syntax` pass for both scripts.
- All 15 behavioral scenarios pass on Windows PowerShell 5.1.26100.9444 and
  PowerShell 7.6.5, including the final assertions that process handles are
  cached before waiting, which preserves exit codes on Windows PowerShell 5.1.
- Native Windows Toast submission succeeded using the installed Mobius AppID.
- Both scripts carry UTF-8 BOMs so saved-script execution in PowerShell 5.1
  correctly parses and displays Chinese text; piped execution remains supported.
- `npm run check` passes. The first `npm run compile` attempt failed because the
  inherited module path omitted Windows PowerShell's system modules. The retry
  added that directory to the validation process environment. Main source
  compilation and extension checks completed with zero TypeScript errors, but
  the command exited 1 during concurrent PPT Master resource staging because
  `vscode/out/vs/workbench/contrib/continue/mobius/skills/ppt-master/SKILL.md`
  was missing. Retrying the existing `stageMobiusPptMaster('out')` function
  separately passed, and the expected output file now exists. No unrelated
  PPT source was edited; the full `npm run compile` command is recorded as a
  failed command with successful isolated resource recovery, not a passing run.
- No real installer, application restart, or release publication is performed by
  the regression tests. Download, installer, launch, and Toast operations are
  mocked in child shells; default `exit` behavior is exercised in real processes.

## References

- [Scoop installer](https://github.com/ScoopInstaller/Install/blob/master/install.ps1):
  explicit result handling and distinguishing script completion from exiting an
  interactive shell. Mobius intentionally defaults to closing on success as
  requested, with `-KeepOpen` / `MOBIUS_AUTO_CLOSE=0` for the retained-shell mode.
- [BurntToast submission](https://github.com/Windos/BurntToast/blob/v0.8.5/BurntToast/Public/Submit-BTNotification.ps1):
  native Toast XML submitted with `CreateToastNotifier(AppId).Show(...)`.
- [VS Code CLI](https://github.com/microsoft/vscode/blob/main/src/vs/code/node/cli.ts):
  `ELECTRON_NO_ATTACH_CONSOLE=1` on GUI startup prevents attaching to the caller's
  terminal. Mobius restores the caller's original environment after launching.
