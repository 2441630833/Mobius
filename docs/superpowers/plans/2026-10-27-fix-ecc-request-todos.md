# Request-aligned Agent todos

## Root cause
Todo heuristics exclude short, documentation and search requests. Session-level existing todos suppress initialization for subsequent requests. Failed todo tool calls are treated as successful initialization. ECC runs independently of todo creation.

## Goal
Create visible todos from every nonempty Agent request before ECC, replace stale session todos, and ask the model to refine them using the current full request. Keep a request-specific fallback when models ignore or fail tool calls.

## Non-goals
Do not change chat-only mode or unrelated skills/terminal work. Preserve all initial dirty submodules (hermes-agent, vendor/*, vscode) and the two existing untracked October 26 plans. In vscode preserve the existing skills routing and terminal patches, including the three pre-existing lines in continueChatAgent.ts; stage only this task's hunks.

## Tasks
1. [x] Add request todo initialization and regression tests under vscode/src/vs/workbench/contrib/continue/.
2. [x] Wire initialization before ECC and reconcile force-tool, fast-path and retry instructions in browser/continueChatAgent.ts.
3. [x] Run targeted tests and npm run compile from E:/MobiusCode/Mobius (full build may exceed five minutes); fix introduced errors. get_errors/manage_todo_list are unavailable in this session, so use compiler diagnostics and this checklist.
4. [x] Review and commit only task changes in vscode and the root repository; verify remaining changes match pre-existing deviations.

## Acceptance criteria
Every nonempty Agent request immediately gets a current-prompt todo even if ECC fails. Old completed or unfinished todos cannot suppress planning for a new request. Model planning uses the full latest request, with 1-7 items appropriate to scope; failed/read-only/empty writes do not satisfy initialization. Documentation and search instructions do not disable todos. Regression tests and compilation validate the implementation, with external blockers documented if encountered.

## Verification results
- Request todo regression suite: 11 passing (10 scenarios plus runner error check).
- Existing ECC workflow suite: 10 passing. An initial run during compilation lacked an emitted dependency; rerunning after emission passed.
- Syntax diagnostics and git diff --check: clean.
- Default npm run compile encountered the existing Windows PowerShell Get-FileHash environment issue. Retried the same scripts/compile-vscode.ps1 with pwsh; full client compilation and source typecheck completed with zero errors. Final extension stage also passed with zero errors; the complete script exited 0.
- Implementation committed in vscode as cd25c662205. Existing terminal work was independently committed during this session as 7138ddbc84d (root 03d50131); it was neither discarded nor included in this task commit. Existing skills routing work remains unstaged.
