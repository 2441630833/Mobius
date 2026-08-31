# GLM-OCR: ship `@huggingface/transformers` in the installer

## Root cause

`transformersJsGlmOcrWorker.js` requires `@huggingface/transformers` as an
esbuild external. `ensure-glm-ocr-onnx.ps1` copies the package into
`continue/extensions/vscode/node_modules`, but `.vscodeignore` has
`node_modules/**` and Continue packaging uses `vsce.listFiles` with
`PackageManager.None`. The installed extension therefore has the worker and
ONNX weights, but no `node_modules`.

Error: `Cannot find module '@huggingface/transformers'` from
`.../extensions/continue/out/transformersJsGlmOcrWorker.js`.

## Goal

Packaged and already-installed Mobius can `require('@huggingface/transformers')`
from the GLM-OCR worker.

## Non-goals

- Re-running the full Inno setup (1+ hour)
- Bundling the 371 MB package into the worker JS
- Commit unless the user asks

## Tasks

1. [x] Force-include `@huggingface/transformers` and `@img` when listing Continue files.
2. [x] Sync those packages into `out/node_modules` (worker resolve path).
3. [x] Allow them in `.vscodeignore`.
4. [x] Copy into the current installed IDE and staged client tree.

## Acceptance criteria

- Installed `extensions/continue/out/node_modules/@huggingface/transformers/package.json` exists.
- Worker require no longer throws `Cannot find module`.
