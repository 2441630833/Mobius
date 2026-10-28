# Reconcile todos before ending an agent request

## Root cause
The agent expects the model to update manage_todo_list, but accepts a final answer without enforcing that update. Its current fallback marks every todo completed after a broad completion decision, even if individual items were not performed; forced summaries, cancellation and error exits follow different paths.

## Goal
Reconcile outstanding todos with actual work before accepting a normal final response, and never blindly complete unfinished items on interruption or ambiguous outcomes.

## Non-goals
Preserve unrelated existing checkpoint-recovery edits in vscode and the untracked checkpoint plan, as well as dirty hermes-agent and vendor submodules. Do not alter automatic skill routing.

## Tasks
1. [x] Add bounded final todo reconciliation before accepting normal agent completion, allowing the model to update only genuinely finished items.
2. [x] Remove blind auto-completion and show a warning when remaining items cannot be reconciled; preserve state on cancellation and failures.
3. [x] Add regression tests and run focused browser tests and npm run compile (may exceed five minutes). get_errors and manage_todo_list are unavailable; use compiler diagnostics and this checklist.
4. [x] Commit only this task's changes without incorporating unrelated checkpoint edits, and verify the declared deviations.

## Acceptance criteria
Normal completed work triggers todo reconciliation before exit; already complete or absent todos need no extra step. Failed, canceled, incomplete and exhausted requests never automatically become completed. Retry is bounded and unresolved items remain visible with a warning. Tests cover successful, pending, canceled and retry-exhausted decisions.

## Verification
- Focused Edge browser suite: 11 passing.
- npm run compile encountered the existing Windows PowerShell Get-FileHash issue; pwsh -NoProfile -File scripts/compile-vscode.ps1 completed successfully, including source type checking and extension compilation.
- get_errors and manage_todo_list tools unavailable in this session; compilation and this checklist provided the available diagnostics.
- Unrelated checkpoint-recovery work remains uncommitted in vscode, along with its root plan; unrelated hermes-agent and vendor changes are preserved.
