# Terminal system notifications as agent-side progress

## Root cause

All background-terminal steering (`{cmd} completed`, `{cmd} terminal exited`, `{cmd} may need input`) uses `sendRequest({ isSystemInitiated: true, systemInitiatedLabel })`. That creates a chat **request** rendered in the user lane (System Notification), for every command — not only `npm run dev`.

## Goal

Keep `sendRequest` to wake / continue the agent, but never show system-initiated terminal notifications as user-side bubbles. Show `systemInitiatedLabel` as an agent response `progressMessage` instead.

## Non-goals

- Changing idle hard-gate suppress (already done).
- Relocating non-system steering / queued user messages.

## Tasks

1. [x] Filter `isSystemInitiated` request rows (and all-system pending steering divider) in `chatViewModel.getItems`.
2. [x] After `addRequest` for system-initiated sends, `acceptResponseProgress` with `progressMessage` from `systemInitiatedLabel`.
3. [x] Extend chatService test: system-initiated request stays in model, response has progressMessage; document view-model hide behavior.
4. [x] `get_errors` on touched files.

## Acceptance

- Any terminal command's completed / exited / may-need-input notification does not appear as a user-lane System Notification bubble.
- Label appears as agent-side progress step on the new response.
- Agent still receives full steering message text.
