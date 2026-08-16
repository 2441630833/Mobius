# Visible Mobius Running Terminals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show Mobius/agent-created terminals as normal closable tabs in both IDE and Agent (sessions) mode, instead of collapsing them into "N Hidden Terminals".

**Architecture:** Agent `run_in_terminal` shells are created via `ToolTerminalCreator` with `hideFromUser: true`, which parks them in `_backgroundedTerminalInstances` so `TerminalTabList` never lists them. Flip creation to visible tabs, keep truly-hidden leftovers filtered out of the footer, and auto-track new visible terminals against the active Agents session so only the current session's user+Mobius terminals appear in the list.

**Tech Stack:** VS Code workbench TypeScript (`toolTerminalCreator`, `terminalChatService`, `sessionsTerminalContribution`, `agentHostTerminalService`)

---

## Root cause

1. `ToolTerminalCreator` sets `hideFromUser: true` → `terminalService.createTerminal` pushes to `_backgroundedTerminalInstances`.
2. Tab list only shows group/editor instances → UI shows "N Hidden Terminals".
3. `SessionsTerminalContribution` explicitly skips `hideFromUser` terminals, so Agents mode cannot manage/close them either.
4. Background servers (e.g. hermes gateway) keep holding ports with no per-tab kill affordance.

## Goal

- Mobius-opened terminals appear as individual tabs in IDE Terminal panel and Agents session terminal list.
- User can select/close each Mobius terminal directly (kill process / free port).
- No "Hidden Terminals" entry for Mobius-created shells.
- Agents mode still session-scopes the list: only current session's user + Mobius terminals are shown.

## Non-goals

- Changing Continue's own `createTerminal()` path (already visible).
- Removing the Hidden Terminals UI for any remaining true `hideFromUser` terminals.
- Auto-killing hermes on IDE exit (separate concern).
- Committing unless the user explicitly asks (user rule overrides AGENTS.md commit-at-end).

## Files

| File | Change |
|------|--------|
| `vscode/.../toolTerminalCreator.ts` | `hideFromUser: false` |
| `vscode/.../agentHostTerminalService.ts` | revived AHP tool terminals `hideFromUser: false` |
| `vscode/.../terminalChatService.ts` | `hiddenOnly` requires `hideFromUser === true` |
| `vscode/.../sessionsTerminalContribution.ts` | auto-track new visible terminals for active session |
| `vscode/.../sessionsTerminalContribution.test.ts` | cover visible Mobius tool terminal session tracking |

## Tasks

1. [x] Set `hideFromUser: false` in `ToolTerminalCreator` so agent shells join the tab list at creation.
2. [x] Set `hideFromUser: false` for revived Agent Host tool terminals.
3. [x] Narrow `getToolSessionTerminalInstances(true)` to count only terminals that still have `hideFromUser: true`, so session-backgrounded Mobius tabs do not reappear as "Hidden Terminals".
4. [x] In `SessionsTerminalContribution.onDidCreateInstance`, when a non-hidden terminal is created while a session is active, track it for that session (so switch/archive/remove manage Mobius tabs with the session).
5. [x] Update/add unit tests: visible Mobius tool terminals are tracked/shown with the active session; truly-hidden (`hideFromUser: true`) terminals remain skipped.
6. [x] Run diagnostics on edited files; mark plan tasks complete. (`npm run compile` 0 errors; browser unit test blocked by missing Playwright browser binary.)

## Acceptance criteria

1. Agent `run_in_terminal` (sync or async) creates a tab visible in Terminal list (sparkle/chat icon OK).
2. "N Hidden Terminals" is not shown for those Mobius shells.
3. Closing the tab disposes the terminal / frees the port.
4. In Agents mode, switching sessions shows only the active session's terminals (user + Mobius).
5. Existing tests for remaining `hideFromUser: true` tool terminals still pass; new visible-terminal cases pass.
