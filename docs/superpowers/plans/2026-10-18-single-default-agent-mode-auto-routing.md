# Single Default Agent Mode with Smart Auto-Routing

## Root cause

Previously, Mobius exposed a mode picker with multiple distinct modes (Agent, Game, Chip, PPT). Users were expected to manually choose between Agent and PPT (or other modes) before typing a prompt.
Furthermore, in `continueChatAgent.ts`, PPT mode and Chip mode were only enabled if explicitly selected in the mode picker, rather than being automatically routed by user intent.
The user wants only a single default **Agent** mode in the UI, which automatically routes to different agent capabilities (PPT presentation generation, Game development, Chip design, general coding) based on user prompt intent or slash commands, just like skill smart routing.

## Goal

1. Restrict the Mobius mode picker to only the single default **Agent** mode (`ChatMode.Agent`), eliminating manual mode selection between Agent, PPT, Game, and Chip.
2. In `continueChatAgent.ts`, intelligently auto-route agent capabilities (PPT mode with `ppt-master`, Game mode, Chip mode, and general Agent mode) from the user's prompt intent or slash command (`/ppt`, `/game`, `/chip`, `/agent`).
3. For PPT tasks:
   - Auto-detect PPT intent (`hasPptIntent` / `/ppt`).
   - Automatically load bundled `pptMasterSkill` and inject its full system hint (`pptModeSystemHint`).
   - Add `ppt-master` to auto-routed skills so it appears in the chat UI progress ("Auto-routed skills: `ppt-master`"), exactly like skill smart routing.
   - Run in presentation authoring mode without opening Godot.
4. Update `continueMobiusModeRouting.ts`:
   - `getMobiusChatModes` returns only `[ChatMode.Agent]`.
   - `normalizeMobiusChatMode` normalizes legacy or specialized modes to `ChatMode.Agent`.
   - Update Agent mode hover and detail subtitle to describe the unified agent with smart routing.
5. In `localChatSessionsProvider.ts`, ensure `_maybeAutoRouteMobiusMode` does not mutate the session away from the default Agent mode in the picker.
6. Verify type checking, unit tests, and build checks pass with 0 errors.

## Non-goals

- Altering the underlying PPT Master skill workflow or scripts.
- Removing or breaking support for `/game`, `/chip`, or `/ppt` slash commands.
- Changing unrelated submodule pointers (`hermes-agent`, `vendor/*`, or pre-existing uncommitted changes in `vscode`).

## Tasks

1. [x] Create plan document `docs/superpowers/plans/2026-10-18-single-default-agent-mode-auto-routing.md`.
2. [x] Modify `vscode/src/vs/workbench/contrib/continue/browser/continueMobiusModeRouting.ts`:
   - Set `getMobiusChatModes` to return `[ChatMode.Agent]`.
   - Update `normalizeMobiusChatMode` to normalize `'game'`, `'chip'`, `'ppt'` to `ChatMode.Agent`.
   - Update Agent mode detail line and hover content to reflect the single unified agent with smart routing.
3. [x] Modify `vscode/src/vs/workbench/contrib/continue/browser/continuePptMode.ts`:
   - Broaden `hasPptIntent` to match Chinese and English presentation keywords comprehensively.
4. [x] Modify `vscode/src/vs/workbench/contrib/continue/browser/continueChatAgent.ts`:
   - Wire `inferMobiusModeFromPrompt`, `hasPptIntent`, `hasChipDesignIntent` into turn execution.
   - Automatically enable `isPptMode`, `isChipMode`, `isGameMode` dynamically from prompt intent or slash command.
   - When `isPptMode` is routed, load `pptMasterSkill`, add `'ppt-master'` to `routedSkillNames` for UI display, and inject the PPT system prompt.
5. [x] Modify `vscode/src/vs/sessions/contrib/providers/localChatSessions/browser/localChatSessionsProvider.ts`:
   - Make `_maybeAutoRouteMobiusMode` a no-op so session picker mode is not changed.
6. [x] Update unit tests in `vscode/src/vs/workbench/contrib/continue/test/browser/continueMobiusModeRouting.test.ts`.
7. [x] Run tests and compile verification.
8. [x] Commit changes cleanly.

## Acceptance criteria

- Mode picker only contains `Agent`.
- Asking for PPT (e.g. "帮我做一份PPT" or `/ppt`) in default Agent mode activates `ppt-master` with UI announcement "Auto-routed skills: `ppt-master`".
- Godot is not opened during PPT tasks.
- Typecheck and unit tests pass with 0 errors.
