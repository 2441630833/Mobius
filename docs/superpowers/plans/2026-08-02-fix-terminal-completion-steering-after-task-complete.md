# Fix: Agent terminal commands re-trigger chat after TASK_COMPLETE

## Root cause

On Windows Mobius agent mode, shell commands that are backgrounded (async `waitForCompletion: false`, or sync timeout → background) register a completion listener in `RunInTerminalTool._registerCompletionNotification`.

When the command later finishes (`onCommandFinished`) or the terminal process is disposed (`onDisposed`), VS Code calls:

```ts
chatService.sendRequest(..., {
  isSystemInitiated: true,
  systemInitiatedLabel: "{command} completed" | "{command} terminal exited",
  queue: ChatRequestQueueKind.Steering,
})
```

That creates a **new chat request** rendered in the user/request lane (right-aligned grey bubble under **System Notification**), which starts a new agent turn (`Considering...`).

Why the user-input side: `isSystemInitiated` requests are still chat *requests*, so the list renderer places them in the request lane with a compact "System Notification" header — not as assistant responses.

Suppression gaps that still let late exits through:

1. Detection preferred `entireResponse.toString()`, which can omit earlier markdown after `clearToPreviousToolInvocation`, while `getMarkdown()` still contains `TASK_COMPLETE`.
2. Continue often accepts a finished turn without the literal `TASK_COMPLETE` token (Chinese/English "done" closers, or verify-nudge exhaustion) — text matching only for the token missed those.
3. Race: pty/`onDisposed` can fire around the same time Continue exits; need an explicit session-level dispose when Continue sets `exitedOnTaskComplete`.

## Goal

After the agent finishes a turn with `TASK_COMPLETE` (or Continue's equivalent done signal), dispose/suppress pending background-terminal completion steering so the finished command cannot open a new task or show a System Notification bubble.

## Non-goals

- Removing legitimate “end your turn and wait for background command” steering (when the agent did **not** finish the task).
- Changing Continue TipTap composer / `userInput` auto-submit paths.
- Killing long-running terminals; only suppress the chat steering message.
- Relocating System Notification UI to the assistant lane (separate UX change).

## Tasks

1. [x] In `runInTerminalTool.ts` `_registerCompletionNotification`, suppress steering when the launching (or last) response indicates task complete.
2. [x] Proactively dispose the notification on `completedRequest` when canceled **or** task-complete.
3. [x] Prefer `getMarkdown` / `getFinalResponse` over `toString()` for detection; share Continue-style done heuristics.
4. [x] On Continue `exitedOnTaskComplete`, call `RunInTerminalTool.suppressBackgroundSteeringForSession`.
5. [x] Add unit tests: markdown-only TASK_COMPLETE, terminal-exited after Chinese done closer, session suppress API.
6. [x] Verify with `get_errors` (no diagnostics on edited files).

## Acceptance criteria

- After task-complete, a late `onCommandFinished` / `onDisposed` does **not** call `sendRequest`.
- Cancelled-session suppression still works.
- Background completion still steers when the response completed without a done signal.
- Screenshot-style `"{cmd} terminal exited"` / `"{cmd} completed"` bubble no longer appears after a finished Mobius agent turn.

## Key files

- `vscode/src/vs/workbench/contrib/terminalContrib/chatAgentTools/browser/tools/runInTerminalTool.ts`
- `vscode/src/vs/workbench/contrib/terminalContrib/chatAgentTools/test/electron-browser/runInTerminalTool.test.ts`
- `vscode/src/vs/workbench/contrib/continue/browser/continueChatAgent.ts`
