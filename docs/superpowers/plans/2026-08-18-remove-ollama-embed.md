# Remove Ollama nomic-embed-text; keep ONNX MiniLM

## Root cause

`@codebase` already uses in-process `transformers.js` / `all-MiniLM-L6-v2` ONNX, but bundling still pulls and verifies Ollama `nomic-embed-text`. That model still sits in `resources/ollama/models` and `npm run bundle:ollama` / `setup:ollama` / `verify:ollama` still treat it as required.

The ONNX file is present at `continue/extensions/vscode/models/all-MiniLM-L6-v2/onnx/model_quantized.onnx` (~23 MB) but is not verified at install/launch.

## Goal

- Stop pulling, warming, and verifying Ollama embeddings.
- Uninstall `nomic-embed-text` from the bundled Ollama models dir (retire + `ollama rm` + orphan blob GC).
- Keep GLM-OCR on Ollama.
- Ensure MiniLM ONNX actually embeds (worker_threads path) before claiming done.
- Continue local onboarding must not re-add nomic.

## Non-goals

- Removing bundled Ollama or GLM-OCR.
- Rebuilding historical LanceDB nomic indexes.
- Committing unrelated game-dev / Godot dirty files.

## Tasks

1. [x] Retire `nomic-embed-text` in `ollama-common.ps1`; drop embed pull/warm/API checks from bundle/setup/verify/ensure.
2. [x] `ensure-minilm.ps1` + `verify-minilm.mjs`; wire into install/launch; add worker to VSIX file list.
3. [x] Continue onboarding: embed role = `transformers.js` / `all-MiniLM-L6-v2` (no Ollama pull UI).
4. [x] Docs: Ollama is OCR-only; embeddings are built-in MiniLM.
5. [x] Delete nomic from the local Ollama store; run MiniLM embed smoke test.

## Acceptance criteria

- `resources/ollama/models/manifests/.../nomic-embed-text` is gone (or `ollama rm` succeeded).
- `bundle:ollama` / `setup:ollama` / `verify:ollama` do not pull or ping `/api/embed`.
- MiniLM worker returns 384-d vectors; similar sentences score higher than unrelated ones.
- `config.yaml` embed model remains `transformers.js` / `all-MiniLM-L6-v2`.
