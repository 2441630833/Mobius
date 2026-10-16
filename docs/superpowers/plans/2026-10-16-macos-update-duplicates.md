# macOS installer duplicate cleanup

## Root cause
The Pages command uses scripts/install-mac.sh, which only detects and replaces
/Applications/Mobius.app. Other copies in /Applications and ~/Applications survive,
and the same-tag early exit never repairs duplicates or Launch Services records.

## Goal
Keep a single canonical installation after an update, identify copies by bundle
identifier com.mobius.ide, and preserve the previous installation on copy failure.

## Non-goals
Do not delete downloads, mounted DMGs, user data, unrelated apps, or change releases.
Preserve all pre-existing modifications: README.md, scripts/package-mac.sh,
hermes-agent, vendor/{fastmcp,litex,litex-boards,mcp-python-sdk,openFPGALoader}, vscode,
the four existing untracked plan docs and scripts/verify-agent-startup.mjs.
Leave the unrelated uninitialized godogen and differing submodule revisions intact.
get_errors/manage_todo_list are unavailable; use Bash syntax checks, fixture tests,
and this checklist instead.

## Tasks
1. [x] Fix scripts/install-mac.sh: identity-checked cleanup in both application
   directories, repair even for same tag, stage/validate before replacement,
   restore on failure, refresh Launch Services, detach DMGs on error.
2. [x] Add scripts/test-install-mac.sh with mocked macOS commands and isolated
   fixture paths. Cover renamed/user copies, unrelated apps, same tag, --check,
   failed download/copy/swap and invalid payload; test DMG and ZIP paths.
3. [x] Run Git Bash syntax and fixture tests, npm run check and npm run compile;
   review and commit only the three intended files with ASCII commit message
   fix: remove duplicate macOS installations after updates.

## Acceptance criteria
Only verified Mobius copies are removed, and only after a valid canonical install.
--check performs no mutation. Download/copy failure preserves the prior app.
Same-version invocation repairs duplicates without downloading. Tests pass.
Real Finder/Launchpad behavior requires macOS; this host is Windows.

## Verification
- Bash syntax and whitespace checks passed.
- All 11 fixture scenarios passed, including a damaged same-tag installation.
- npm run check passed.
- Initial npm run compile failed because the host did not auto-load
  Microsoft.PowerShell.Utility (Get-FileHash unavailable). Retried with
  powershell -NoProfile -ExecutionPolicy Bypass -Command
  "Import-Module Microsoft.PowerShell.Utility; & './scripts/compile-vscode.ps1'".
- Retry completed successfully (exit 0): client compile, source typecheck,
  Monaco check and built-in extensions all passed with zero errors. The full
  client build took 6.32 minutes; the script's separate extensions build took 52 s.
- Re-ran all 11 fixture scenarios against the final installer: exit 0.
- Final scope: this plan, scripts/install-mac.sh and scripts/test-install-mac.sh.
  Local commit only; no release publication or push is part of this change.
