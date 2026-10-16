# Default Agent startup

## Root cause
The shared startup predicate excludes --new-window, routing a normal new window to Editor. Second-instance launch duplicates the predicate, so entry points can diverge. macOS packaging has no check of the actual startup renderer.

## Goal
Default Mobius launches and pathless new windows to Agent view, including repeated launches. Reject macOS packages whose default startup opens Editor.

## Non-goals
Preserve explicit file/folder opening and extension development. Preserve all pre-existing changes in README.md, hermes-agent, vendor submodules, vscode (Continue and terminal changes and tmp-repro files), and the three pre-existing plan files. Do not publish or replace existing releases.

## Tasks
1. [x] Unify first and second launch decisions, allowing pathless --new-window to open Agents; add regression tests.
2. [x] Add an actual packaged macOS startup smoke check before archive creation.
3. [x] Run type checking, regression tests, npm run check and npm run compile; inspect changes and commit only intended files in vscode and the parent repository.

## Acceptance criteria
Default, reuse-window and new-window launches select Agents; explicit files/folders and extension development retain their behavior. A repeated default launch focuses the existing Agent window. macOS packaging verifies the sessions renderer for both default and --new-window startup. All checks run, with platform or pre-existing failures recorded accurately. Only predeclared unrelated work remains.

## Execution
Workspace E:/MobiusCode/Mobius; vscode is a submodule. get_errors and manage_todo_list are unavailable; use this checklist, npm run typecheck-client in vscode, and the root build/check commands. Full compile may exceed five minutes and must run. macOS runtime verification requires the macOS packaging host; the local host is Windows. Commit messages: fix: default new Mobius windows to Agent view; fix: verify packaged macOS Agent startup.

Type checking and prerequisites passed. The existing packaged Windows app reproduced the regression: fresh default launch loaded sessions.html, but --new-window loaded workbench.html; the new smoke check correctly rejected it. The npm compile wrapper failed in Windows PowerShell because Get-FileHash was unavailable; retrying the same scripts/compile-vscode.ps1 in PowerShell 7 proceeds successfully through compilation. JavaScript and shell syntax checks passed.

Concurrent unrelated work appeared during execution in scripts/install-mac.sh, scripts/test-install-mac.sh and docs/superpowers/plans/2026-10-16-macos-update-duplicates.md; preserve these as well.

Final verification: PowerShell 7 scripts/compile-vscode.ps1 completed with exit 0 (client and built-in extensions, zero errors). npm run test-node -- --run src/vs/platform/product/test/common/mobiusAgentsStartup.test.ts passed all 4 checks. node scripts/verify-agent-startup.mjs E:/MobiusCode/Mobius/vscode/.build/electron/Mobius.exe E:/MobiusCode/Mobius/vscode passed fresh launch, new-window launch, explicit Editor setup and default relaunch after Editor. node --check scripts/verify-agent-startup.mjs, bash -n scripts/package-mac.sh and targeted git diff --check passed. macOS runtime is unavailable locally; signed macOS packaging now runs the same smoke check before producing archives. No new macOS installer was built or published during this task.
