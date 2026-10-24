# Rebase Continue Repository onto Upstream

## Root Cause / Context
The `continue` repository is a submodule located at `continue/` tracking `https://github.com/2441630833/Mobius-continue.git` on branch `main`.
It has 25 custom commits on top of initial snapshot commit `0fa112ad60248af16301eb58fa9c7e940a0a817c` (Continue v1.3.40 snapshot).
Upstream Continue (`https://github.com/continuedev/continue.git`) has advanced significantly with bug fixes, performance improvements, and new capabilities.
The user requested to rebase our Continue repository to update to upstream while strictly preserving all existing features currently in use.

Key existing features in Mobius Continue:
1. In-process Transformers.js MiniLM embeddings provider and background worker (`transformersJsEmbedWorker.ts`).
2. GLM-OCR worker with process isolation and GPU auto-selection (`TransformersJsGlmOcrClient.ts`, `transformersJsGlmOcrWorker.ts`).
3. GUI mode selector extensions (Game mode and Chip mode icons, system prompts, and pickers).
4. TipTap editor draft persistence per chat/tab in Redux session slice.
5. Voice input with continuous auto-send and raw audio streaming for omni-modal models.
6. Robust multi-edit / search-and-replace line-ending normalization and fault tolerance.
7. Worker thread code chunking and tree-sitter parser pooling to prevent extension host hangs.
8. Offline search_web fallback and terminal tool alias compatibility.
9. Mobius build integration (`scripts/install-continue.ps1`, `scripts/sync-continue-gui.ps1`, esbuild & prepackage scripts).

## Goal
Update `continue` to upstream's latest `main` (or latest release) via a clean rebase of all Mobius custom commits, resolve all conflicts while preserving every Mobius feature, and verify the extension builds and passes checks cleanly.

## Non-goals
- Touching other submodules (`ECC`, `vscode`, `vendor/*`).
- Removing any established Mobius features or changing user-facing APIs without user approval.

## Tasks
1. [x] Fetch upstream `refs/heads/main` and inspect commit differences and architectural evolution.
2. [x] Export / rebase the 25 custom Mobius commits onto upstream target.
3. [x] Resolve any conflicts in core, gui, and vscode extensions:
   - Verify Transformers.js MiniLM worker integration.
   - Verify GLM-OCR worker integration.
   - Verify GUI ModeSelect (Game / Chip / Agent modes).
   - Verify Redux session slice draft persistence.
   - Verify Voice input and tool aliases.
   - Verify tree-sitter chunking worker.
4. [x] Run Continue dependency installation and builds:
   - `scripts/install-continue.ps1` (root packages, core, gui, extensions/vscode prepackage + esbuild).
5. [x] Run verification scripts:
   - `scripts/verify-minilm.mjs`
   - `scripts/verify-glm-ocr.mjs`
   - Unit tests for changed packages where applicable.
6. [x] Review git status, stage, commit, and verify submodule clean state.

## Acceptance Criteria
- Continue submodule is updated to upstream with all Mobius patches applied.
- All three workers (`out/extension.js`, `out/transformersJsEmbedWorker.js`, `out/transformersJsGlmOcrWorker.js`) build successfully.
- `verify-minilm.mjs` and `verify-glm-ocr.mjs` pass.
- GUI builds without compilation errors and includes Game/Chip mode selectors.
- No regression in existing Mobius features.
