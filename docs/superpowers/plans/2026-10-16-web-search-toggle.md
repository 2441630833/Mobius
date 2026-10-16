# Web Search composer toggle

## Root cause
The composer exposes Local OCR but has no user control for search_web. Search
intent, tool advertising and execution currently depend only on network status.

## Goal
Add a persistent Web Search on/off chip alongside OCR, enabled by default.
Disable search intent, tool advertising and execution when turned off, including
parallel research. Recheck the setting at execution so pending calls are blocked.

## Non-goals
Do not disable ordinary URL fetching or arbitrary network access. Preserve the
existing README modification, terminal source/test changes, vscode/tmp-repro.mjs,
vscode/tmp-repro.png, prior terminal plan, and all existing submodule deviations
(including uninitialized godogen). Concurrent work also modifies
`scripts/package-mac.sh`, `vscode/src/vs/platform/launch/electron-main/launchMainService.ts`,
`vscode/src/vs/platform/product/common/mobiusAgentsStartup.ts`, and adds
`vscode/src/vs/platform/product/test/`, the default-agent-startup and macOS release
plans dated 2026-10-16, and `scripts/verify-agent-startup.mjs`. Preserve all these
without staging. Do not stage unrelated items.

## Tasks
1. [x] Inspect OCR, agent tool paths and workspace instructions.
2. [x] Add setting, accessible composer toggle, and search permission enforcement.
3. [x] Add regression coverage; run vscode npm run typecheck-client before tests,
   targeted tests, root npm run check and npm run compile:vscode. The full build
   can exceed five minutes. No get_errors/manage_todo_list tools are exposed;
   use compiler diagnostics and this checklist as available equivalents.
4. [x] Commit intended vscode files with `feat: add Web Search composer toggle`,
   then only the vscode pointer and plan with `feat: expose Web Search control`.

## Acceptance criteria
The chip displays On/Off state, persists user preference, follows OCR layout,
and blocks search even for explicit search requests or pending calls when off.
Default enabled and offline behavior remain compatible. Checks pass or external
blockers are recorded. Only declared unrelated changes remain uncommitted.

## Verification results

- Client typecheck passed after the implementation and permission regression tests.
- Prerequisite check passed. CSS stylelint passed with five existing advisory
  design-token suggestions.
- Root compile initially failed in Windows PowerShell because Get-FileHash was
  unavailable; retried the same script with pwsh -NoProfile. The first retry failed because a test file was added after its compiler
  file list was captured. A second full retry passed all extension/media and
  client typechecks but failed emitting a concurrent unrelated newly added
  mobiusAgentsStartup.test.ts. Run compileTask('src', isolatedTempOutput, false)
  directly for a fresh complete client emit/typecheck without cleaning shared out.
- Permission regression suite: all 11 tests passed. The command-click test first
  exposed a notification-service mock setup error; corrected the mock before
  rerunning.

- Fresh isolated client compileTask completed with zero diagnostics, zero emit
  errors, and 10,829 pipeline files processed (exit 0). The output and verification
  logs are under the Windows temporary directory, outside the repository.
- The shared out directory was concurrently cleaned during a test retry. Copied
  the existing Electron test harness to the temporary directory and pointed its
  out junction at the verified isolated output. The unchanged standard runner
  passed all 13 tests (11 permission/network tests, one toggle persistence test,
  and the runner registry cleanliness test). No repository test harness changes.
- Final client typecheck after the test mock correction passed. Diff whitespace
  checks passed. Source changes were complete before the successful isolated emit.

- Implementation committed in vscode as d4694b3e0318a62a34ee3905955fd3f3350e0ad4.
  The root commit records only this submodule pointer and the completed plan.
