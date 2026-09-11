# Fix: New Chat input draft is lost when switching chat tabs

## Root cause

`chatDrafts` (per-chat unsent-prompt store) is keyed by `session.id`:

- `sessionSlice.ts:404-412` `setMainEditorDraftContent` → `state.chatDrafts[state.id] = payload`
- `sessionSlice.ts:848` `replaceSession(Disk Session)` → `mainEditorDraftContent = chatDrafts[state.id]`

For a **real session** `state.id` is the stable `sessionId`, so drafts survive
navigating away and back.

For **New Chat** the id is *regenerated on every visit*:

- `sessionSlice.ts:813` (`replaceSession`, `!payload`) → `state.id = uuidv4()`
- `sessionSlice.ts:793` (`newSession`, `!payload`) → `state.id = uuidv4()`

So: type in New Chat → draft saved under `uuid#1` → switch to another chat →
switch back → `uuid#2` generated → `chatDrafts[uuid#2] === undefined` →
**draft permanently lost**, and `uuid#1` becomes an orphan key.

The thunk cannot short-circuit either: `switchChatSession.ts:62` compares
`sessionId === current.id`, which never matches when `sessionId` is `undefined`,
and `takeBackgroundSession(sessionId)` (`:91`) is never reached for New Chat
because of the early return at `:80-89`.

Introduced by `a82a92f0c` ("keep per-chat main editor drafts in Redux"), which
added per-session drafts but did not cover the no-`sessionId` New Chat case.

## Goal

An unsent prompt typed into a **New Chat** tab must survive switching to another
chat and back, and each New Chat tab must keep its own draft.

## Non-goals

- Do not change the New Chat `uuid` regeneration itself (out of scope; would
  affect session parking/streaming).
- Do not persist drafts to disk (in-memory per session is sufficient).
- Do not change streaming / abort behaviour.

## Tasks

1. `sessionSlice.ts`: add `draftKey?: string` and `pendingNewChatDraftKey?: string`
   to `SessionState` + `INITIAL_SESSION_STATE`.
2. `sessionSlice.ts`: add `setNewChatDraftKey` reducer (sets
   `pendingNewChatDraftKey`), export it.
3. `sessionSlice.ts`: `setMainEditorDraftContent` / `clearMainEditorDraftContent`
   key `chatDrafts` by `state.draftKey ?? state.id`.
4. `sessionSlice.ts`: in `newSession` and `replaceSession`:
   - New Chat branch: `draftKey = pendingNewChatDraftKey ?? state.id`; clear
     `pendingNewChatDraftKey`; resolve `mainEditorDraftContent` from `chatDrafts[draftKey]`.
   - Disk-session branch: `draftKey = session.sessionId`.
   - Parked branch: carry `draftKey` from parked state.
5. `switchChatSession.ts`: dispatch `setNewChatDraftKey(tabId)` before
   `replaceSession(undefined)` in the New Chat branch (`:80-89`) and in
   `openNewChatTab` (`:131`, hoisting `generateChatTabId()` so the same id is
   used for the tab).
6. Typecheck (`tsc --noEmit`) and run existing `sessionSlice.test.ts`.
7. Rebuild GUI bundle and hot-patch installed Mobius
   (`c:/Users/luoji/AppData/Local/Programs/Mobius/resources/app/`).
8. Commit + push the `continue` submodule, then bump + push parent.

## Acceptance criteria

- Type text in New Chat → switch to an existing chat → switch back → text is
  still in the input box.
- Two New Chat tabs keep independent drafts.
- Switching between existing (already-saved) chats still restores each draft
  (no regression).
- After sending the first message from New Chat, the input is empty (no
  stale draft leaking into the new session).
- `tsc --noEmit` clean; `sessionSlice.test.ts` passes.
