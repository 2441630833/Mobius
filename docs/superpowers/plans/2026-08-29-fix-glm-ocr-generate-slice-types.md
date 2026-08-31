# Fix GLM-OCR generate() Tensor | ModelOutput slice error

## Root cause

`model.generate()` in `@huggingface/transformers` is typed as
`Promise<Tensor | ModelOutput>`. Default generation returns a `Tensor` (`.slice`
exists). `ModelOutput` does not. `tsc -p tsconfig.npm.json` therefore fails at
`outputs.slice(...)` in `transformersJsGlmOcrWorker.ts:104`, and
`package.ps1` aborts the Continue release build.

## Goal

Continue core `npm run build` (`tsc -p ./tsconfig.npm.json`) succeeds so
`scripts/package.ps1` can finish the Continue extension.

## Non-goals

- Change OCR runtime behavior or prompts
- Re-run the full IDE package unless tsc is already green
- Commit / push unless the user asks

## Tasks

1. [x] Unwrap `generate()` to a `Tensor` (`instanceof Tensor`, else `.sequences`).
2. [x] Call `.slice(null, [promptLength, null])` only on that Tensor.
3. [x] Run `npm run build` in `continue/core` (or `tsc -p ./tsconfig.npm.json`).

## Acceptance criteria

- [x] `continue/core` `tsc -p ./tsconfig.npm.json` exits 0
- [x] No remaining `Property 'slice' does not exist` error
