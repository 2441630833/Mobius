# 2026-09-03 — Fix Continue webview SW + Agent Evaluating stuck UX

## Root cause

1. **Continue right panel fails on Windows**  
   VS Code webview host (`pre/index.html`) registers a ServiceWorker. On Windows this often hits `InvalidStateError: The document is in an invalid state` when the document is not fully active. That surfaces as `Error loading webview: Could not register service worker…` before Continue HTML can load. Continue itself does not register a SW.

2. **Agent stays on "Evaluating"**  
   `"Evaluating"` is a random cosmetic phrase from `chatThinkingContentPart` (`chat.thinking.thinking.5` / tool pool). It only changes when a tool appends. During long model thinking / streaming with no tool events, the same word sits forever with no elapsed time, so users cannot tell running vs hung.

## Goal

- Auto-recover webview SW failures (retry + reload fresh document + Reload Webview action).
- While agent is working, show live elapsed time and periodically rotate the status phrase so the UI proves the turn is still alive.

## Non-goals

- Clearing `%APPDATA%\…\Service Worker` as the only fix (still useful manual recovery).
- Changing Continue GUI React code for the SW error.
- Fixing every possible model stream hang (separate from status UX).

## Tasks

1. [x] Port microsoft/vscode#333833 recovery into:
   - `vscode/src/vs/workbench/contrib/webview/browser/pre/index.html`
   - `vscode/src/vs/workbench/contrib/webview/browser/webviewElement.ts`
   - Recompute CSP `script-src` sha256 for the modified inline script.
2. [x] In `chatThinkingContentPart.ts`, while streaming:
   - Keep current phrase base.
   - Append live elapsed (`· 12s` / `· 1m 05s`).
   - Rotate phrase every ~4s when no tool update arrives.
3. [x] In `chatProgressContentPart.ts` `startLiveProgress`, show live elapsed from `confirmationAdjustedTimestamp` (interface already documents this).
4. [x] Also update `chatSubagentContentPart.ts` spinner the same way.
5. [x] Delete temp download artifacts under `docs/tmp-*`.
6. [x] Sanity-check CSP hash match.

## Acceptance criteria

- SW `InvalidStateError` triggers silent webview reload retries instead of an immediate fatal toast; after budget exhaustion, toast includes **Reload Webview**.
- Agent working spinner shows updating elapsed time while `!streamingCompleted && !isComplete`.
- Phrase still rotates on tool append; also rotates on timer when idle.
- CSP hash matches the inline script body.
