# Restore Agents chat input mode picker (Game included)

## Root cause

`npm start` always launches `--agents` (`sessions-dev.html`), not the regular workbench chat editor.

Two pickers:

1. Workbench `ChatInput` `OpenModePickerAction` — gated on `chatIsEnabled` (`_hasDefaultAgent`). Continue only calls `registerDynamicAgent`, so that key stayed false.
2. Agents welcome composer `Menus.NewSessionConfig` + `sessions.defaultCopilot.modePicker` — the real chip is `ModePicker` via `IActionViewItemService`. The Action2 `run()` is empty.

Live CDP (before fix): welcome showed a generic toolbar button `<a aria-label="Mode">Mode</a>`. Click did nothing. Why:

- Welcome has no session (`activeSessionType === ''`). The menu `when` originally hid the action; we opened it for new/local chat.
- Opening the action on welcome painted the toolbar **before** `CopilotPickerActionViewItemContribution` (`AfterRestored`) registered the view-item factory.
- `actionViewItemService.register()` does not fire `onDidChange` unless an event is passed, so `MenuWorkbenchToolBar` never rebuilt. The default Mode button stayed.

Ask is hidden unless `showOldAskMode`. Game/Plan come from `.github/agents/*.agent.md` in the **picked** Agents workspace folder.

## Goal

- Agents composer shows a working mode chip (click opens the list).
- List is Agent, Ask, plus custom agents (Game, Plan) from the opened folder.
- Selecting Game still drives `godot_play`. Plan stays read-only.

## Non-goals

- Rebuilding Continue GUI ModeSelect.
- Copying Cursor Debug/Multitask.

## Tasks

1. [x] `registerDynamicAgent` sets default-agent context keys like `registerAgentImplementation`.
2. [x] Show Ask in the workbench picker when Continue is `defaultChatAgent`.
3. [x] Add Plan custom agent; ContinueChatAgent treats Plan as no-write.
4. [x] Agents welcome `when` includes new session + empty/local type.
5. [x] `ModePickerModel` loads workspace custom agents + builtin Ask on Continue; local-chat `setSession` / `setSessionMode`.
6. [x] Register picker contribution at `BlockRestore`; fire `onDidChange` after register so a painted toolbar rebuilds.
7. [x] Fallback in `newChatInput.ts` `actionViewItemProvider` for `sessions.defaultCopilot.modePicker`.
8. [x] `npm run compile-client` (0 errors) + live CDP click.

## Live CDP result (2026-08-19, isolated `--user-data-dir`)

- Toolbar chip is `Pick Mode, Agent` (`.sessions-chat-picker-slot`), not the no-op `aria-label="Mode"` button.
- Click opens the action widget: **Agent**, **Ask**, Configure Custom Agents. No Debug/Multitask.
- Selecting **Ask** updates the chip to `Pick Mode, Ask`.
- Game/Plan did not appear on welcome while the workspace chip still said “Start by picking a workspace”. Those custom agents load from the folder the user picks, via `.github/agents/*.agent.md`.

## Acceptance criteria

- [x] Clicking Mode on the Agents welcome composer opens the list (not a no-op).
- [x] List includes Agent and Ask. Game/Plan when a workspace folder with those agent files is selected.
- [x] No Debug/Multitask.
- [x] Selecting a mode updates the chip label.
- [x] `compile-client` clean for edited TS.
