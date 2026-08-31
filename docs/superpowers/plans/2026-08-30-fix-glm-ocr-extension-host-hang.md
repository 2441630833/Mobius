# Fix GLM-OCR hang in Mobius extension host

## Root cause

Standalone Node / `ELECTRON_RUN_AS_NODE` OCR completes in ~3–13s
(weights + worker present). In the Mobius Agents window the same path hits
`GLM-OCR timed out after 180000ms`.

Logs (`%APPDATA%\Mobius\logs\20260830T231958`):

- 23:20:14 OCR starts for Pasted Image (model `continue:Volcano` /
  `ark-code-latest` is text-only → OCR path, not vision passthrough)
- 23:23:14 exact 180s timeout from `continueOcrPreprocessor.ts`

Earlier the same day: `Cannot find module '@huggingface/transformers'`
(fixed by packing transformers), then sticky `GLM-OCR worker unavailable`.

`onnxruntime-node` + multiple `worker_threads` inside Electron is a known
hang/crash class. MiniLM embed already holds an ORT session in another
worker in the **same** extension-host process; GLM-OCR then loads a ~650MB
vision model in a second worker → hang until the 180s race times out.
Timeout does not kill the worker, so the hung ORT stays around.

## Goal

Agents-window local OCR completes reliably (typical pasted screenshot
well under 60s) without blocking the extension host.

## Non-goals

- Re-running full Inno installer
- Making `ark-code-latest` vision-capable (separate product decision)
- Commit unless the user asks

## Tasks

1. [x] Run GLM-OCR via `child_process.fork` + `ELECTRON_RUN_AS_NODE=1`
      (isolated process), keep IPC protocol compatible with the worker.
2. [x] Adapt `transformersJsGlmOcrWorker.ts` for `process.send` / `message`
      when not on `parentPort`.
3. [x] Put `out/node_modules` on `NODE_PATH`; set ORT/OMP thread caps to 4.
4. [x] On OCR timeout: terminate child + reset shared client
      (`continue.cancelGlmOcr` + preprocessor). Workbench cancel ships on next
      Mobius compile; Continue extension already patched into the install.
5. [x] Downscale large images before encode (max edge 1568) to bound CPU time.
6. [x] Rebuild worker bundle; patch installed Mobius Continue extension;
      smoke-test fork path (~12s for real pasted screenshot under Electron).

## Acceptance criteria

- [x] `node scripts/verify-glm-ocr.mjs` still passes (fork smoke).
- [x] Forked OCR under `ELECTRON_RUN_AS_NODE` returns text for a real PNG
      in &lt; 60s (~12s measured).
- [x] Timeout path terminates the child (no sticky hung ORT) — client
      `reset()` + `continue.cancelGlmOcr`.
- [x] Plan tasks marked `[x]`.
