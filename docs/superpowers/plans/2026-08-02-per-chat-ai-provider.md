# Per-Chat AI Provider Switching Implementation Plan

> **For agentic workers:** Execute every task below in this session. Checkboxes track progress.

**Goal:** Allow each chat tab (conversation) to use its own AI API provider/model, not only when loading a different saved session from history.

**Architecture:** Persist `chatModelTitle` on in-memory `SessionState` (disk `Session` already has it). On model change, bind the title to the active chat. On every tab switch (parked or disk), restore that chat's model into the UI. During streaming, resolve the model from the (possibly parked) session's `chatModelTitle` so concurrent background chats keep their own providers.

**Tech Stack:** Continue GUI Redux (`sessionSlice`, thunks), ModelSelect UI, existing `Session.chatModelTitle` persistence.

## Root cause

- Disk sessions already store/restore `chatModelTitle` via `loadSession` / `persistSession`.
- In-memory tab switches (`switchChatSession` parked path) never restore the model.
- `SessionState` does not track `chatModelTitle`, so parking loses the binding.
- Streams read the global `config.selectedModelByRole.chat`, so one chat's provider change affects others.

## Non-goals

- Changing `.env` profile storage or ConfigHandler profile lifecycle.
- Per-message provider switching inside one chat.
- Committing unrelated dirty worktree files (`Directory.Build.targets`, ollama scripts, vscode submodule pointer, etc.).

## Files to modify

| File | Responsibility |
|------|----------------|
| `continue/gui/src/redux/slices/sessionSlice.ts` | Add `chatModelTitle`; set on `newSession` / `replaceSession`; reducer `setChatModelTitle` |
| `continue/gui/src/redux/slices/configSlice.ts` or new selector helper | Root selector: session title → model, else global |
| `continue/gui/src/components/modelSelection/ModelSelect.tsx` | Write `chatModelTitle` on change; display session-bound model |
| `continue/gui/src/redux/thunks/switchChatSession.ts` | Stamp model before park; restore on all switch paths |
| `continue/gui/src/redux/thunks/session.ts` | Keep `selectChatModelForProfile`; ensure newSession path sets state field |
| `continue/gui/src/redux/thunks/streamNormalInput.ts` | Use session-scoped model selector |
| `continue/gui/src/redux/thunks/streamResponse.ts` | Use session-scoped model selector |
| `continue/gui/src/redux/thunks/streamThunkWrapper.tsx` | Use session-scoped model selector |
| `continue/gui/src/redux/thunks/callToolById.ts` | Use session-scoped model selector |

## Tasks

- [x] 1. Add `chatModelTitle` to `SessionState` + wire `newSession` / `replaceSession` / `setChatModelTitle`
- [x] 2. Add `selectChatModelForActiveSession` root selector
- [x] 3. ModelSelect: update session + global on change; show session model
- [x] 4. switchChatSession / openNewChatTab: park with title; restore on switch; seed new tabs
- [x] 5. Point stream/tool thunks at session-scoped selector
- [x] 6. Verify lints on edited files

## Acceptance criteria

1. Chat tab A on provider X, chat tab B on provider Y; switching tabs shows and uses each tab's provider.
2. Background streaming on A keeps using X while B is switched to Y.
3. Saving/reloading a session still restores its provider (existing behavior preserved).
4. Unrelated pre-existing dirty files are not modified.

---
