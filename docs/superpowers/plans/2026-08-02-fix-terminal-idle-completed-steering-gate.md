# Fix: Idle session hard-gate for terminal completed steering

## Root cause

Installed Mobius already ships `suppressBackgroundSteeringForSession` + TASK_COMPLETE detection, but that only covers cancel / done markers. When the agent ends a normal turn (session idle, no in-progress response) and a backgrounded command later fires `onCommandFinished` / `onDisposed`, `_registerCompletionNotification` still calls `sendRequest` with `{cmd} completed` / `{cmd} terminal exited`, opening a new System Notification turn.

## Goal

Suppress completed / exited / input-needed background steering whenever the chat session has no in-progress response (`!lastRequest?.response` or `response.isComplete` / canceled).

## Non-goals

- Agent-side System Notification UI relocation (separate follow-up).
- Killing background processes.
- Changing Continue TipTap / userInput auto-submit.

## Tasks

1. [x] Document install-package probe (suppress present; idle gap remains).
2. [x] Add `sessionHasInProgressResponse` + idle hard gate in `runInTerminalTool.ts`.
3. [x] Proactively dispose listeners on `completedRequest` when response is complete (not only TASK_COMPLETE).
4. [x] Update / add unit tests for idle suppress and in-progress allow.
5. [x] `get_errors` on touched files.

## Acceptance criteria

- Idle session: no `{cmd} completed` / `{cmd} terminal exited` / input-needed `sendRequest`.
- In-progress response: completion steering still works.
- TASK_COMPLETE / `suppressBackgroundSteeringForSession` still work.

## Key files

- `vscode/src/vs/workbench/contrib/terminalContrib/chatAgentTools/browser/tools/runInTerminalTool.ts`
- `vscode/src/vs/workbench/contrib/terminalContrib/chatAgentTools/test/electron-browser/runInTerminalTool.test.ts`
