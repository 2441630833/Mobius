# Plan: Remove Glaring Purple Highlight from OCR and Web Search Buttons

**Date:** 2026-10-19  
**Status:** Completed  

## 1. Root Cause Analysis

- In `vscode/src/vs/workbench/contrib/continue/browser/media/continueChat.css`, `.action-label:is(.chat-local-ocr-button, .chat-web-search-button).checked` explicitly sets:
  ```css
  background-color: var(--vscode-badge-background, #007acc);
  color: var(--vscode-badge-foreground, #ffffff);
  border-color: transparent;
  font-weight: 600;
  ```
  In many dark/purple-accented VS Code themes, `--vscode-badge-background` renders as a bright glaring solid purple pill.
- In `continueOcrAction.ts` and `continueWebSearchAction.ts`, the active state was displayed as `'OCR'` and `'Web Search'` without explicitly showing `'On'`, whereas inactive showed `'OCR Off'` and `'Web Search Off'`.
- The user requested removing the glaring purple background entirely and distinguishing the button states cleanly via on/off state changes (e.g., text `'OCR On'` / `'OCR Off'` and `'Web Search On'` / `'Web Search Off'`, subtle transparent background, standard hover, and muted disabled style).

## 2. Goal

- Remove purple badge background and any bright purple highlights from both OCR and Web Search toolbar buttons.
- Update button labels to clearly indicate on/off state:
  - OCR button: `'OCR On'` when active, `'OCR Off'` when inactive.
  - Web Search button: `'Web Search On'` when active, `'Web Search Off'` when inactive.
- Style active state cleanly: transparent background, standard foreground text/icon, subtle widget border.
- Style inactive state cleanly: transparent background, muted opacity (0.55), description foreground color, subtle border.
- Standard hover effect matching other toolbar buttons (`var(--vscode-toolbar-hoverBackground)`).

## 3. Non-Goals

- Changing backend OCR processing or Web Search intent routing logic.
- Altering other toolbar buttons (`+`, Model selector, settings gear).

## 4. Implementation Tasks

1. [x] Plan documented.
2. [x] Update `vscode/src/vs/workbench/contrib/continue/browser/media/continueChat.css`:
   - Remove `var(--vscode-badge-background)` and purple coloring from `.checked`.
   - Use clean transparent background, standard foreground color, and subtle borders.
   - Add standard hover state.
3. [x] Update `vscode/src/vs/workbench/contrib/continue/browser/continueOcrAction.ts`:
   - Update `updateLabel()` to display `'OCR On'` when enabled and `'OCR Off'` when disabled.
4. [x] Update `vscode/src/vs/workbench/contrib/continue/browser/continueWebSearchAction.ts`:
   - Update `updateLabel()` to display `'Web Search On'` when enabled and `'Web Search Off'` when disabled.
5. [x] Verify compilation and tests, clean git commit.

## 5. Acceptance Criteria

- No purple badge background on OCR or Web Search buttons in either on or off state.
- Button clearly indicates `'OCR On'` / `'OCR Off'` and `'Web Search On'` / `'Web Search Off'`.
- Clean visual integration with the rest of the chat toolbar.
