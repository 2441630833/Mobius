# Reliable Mobius checkpoint recovery

## Root cause
Chat checkpoints are created at request start but restoreSnapshot navigates to the preceding checkpoint. Continue direct writes emit externalEdit only after writing and do not create before/after timeline operations. Terminal effects are not tracked. Git checkpoint support exists separately for Copilot worktrees and does not cover Continue. Existing unrelated dirty hermes-agent and vendor submodules must be preserved.

## Goal
Restore the selected request's starting state; record supported direct edits before and after the write, including dirty editor models; preview and protect conflicts; expose unprotected terminal operations; add isolated Git-backed snapshot enhancement without changing user HEAD or index.

## Non-goals
Never run hard reset or clean, overwrite unknown user edits, change branch/index, silently claim coverage of external effects, or snapshot ignored files/secrets indiscriminately.

## Tasks
1. [x] Trace session creation, edit events, conflict and Git plumbing; determine exact testable integration.
2. [ ] Fix request boundary, direct edits and unsaved model capture with explicit non-protection on failure.
3. [ ] Implement safe preview/conflict behavior and restore protection for recorded paths.
4. [ ] Implement isolated Git checkpoint enhancement and honest terminal coverage reporting, with multi-root/submodule and ignored-file boundaries.
5. [ ] Add meaningful end-to-end and unit tests for boundary, file edits, failure, dirty models, conflict, Git and terminal behavior.
6. [x] Run targeted tests and full `pwsh -NoProfile -File scripts/compile-vscode.ps1` from E:/MobiusCode/Mobius; full build can exceed five minutes. The get_errors/manage_todo_list tools are unavailable; use compiler diagnostics and this checklist.
7. [ ] Commit only this task in vscode and root; verify pre-existing dirty submodules are untouched.

## Acceptance criteria
Restoring a selected request targets its own pre-request checkpoint, never silently overwrites newer user changes, and supported writes record actual working-copy before/after states. Failures disclose unprotected coverage. Git support does not touch actual index or branch and never silently captures excluded files. Untracked terminal changes and limitations are clearly disclosed. Relevant tests and build pass; material limitations must be recorded if a hard blocker arises.

## Progress and verification
- Request boundary now targets the request checkpoint; missing checkpoints report an error. Restore confirmation lists tracked paths and marks unsaved files, but it does not yet detect all saved-file conflicts.
- Continue direct write fallback wraps start/stop external edit tracking and preserves dirty working-copy content while capturing snapshots. Other edit paths emit an unverified-coverage warning; terminal commands emit an unprotected-effects warning.
- Browser timeline suite: 43 passing, including request boundary, missing checkpoint, and mocked dirty working-copy capture. A complete live Continue UI/end-to-end test is still required.
- Both PowerShell 7 full builds succeeded; the second covered the final code. The first native tsgo check passed. get_errors/manage_todo_list are unavailable.
- The Git backend, complete conflict detection and diffs, restore safety snapshot, terminal change enumeration, and comprehensive multi-root/submodule/ignored-file handling remain open. Do not present this as complete.
- Partial implementation commit in vscode: 84779d6168e. This is not a completed three-layer implementation.
