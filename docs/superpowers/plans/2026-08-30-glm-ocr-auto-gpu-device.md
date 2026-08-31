# GLM-OCR: auto-select GPU (DirectML / WebGPU / CUDA) with CPU fallback

## Root cause

`transformersJsGlmOcrWorker.ts` hard-codes `device: "cpu"`. The machine has
an NVIDIA RTX 3050 (+ Intel UHD). `@huggingface/transformers` +
`onnxruntime-node` on Windows supports DirectML (`dml`) and `webgpu`, but
**not** CUDA on win32.

Probe results on this host (q4f16 GLM-OCR-ONNX):

| device   | load |
|----------|------|
| `dml`    | OK (~2s) |
| `webgpu` | OK (~3s) |
| `gpu`    | FAIL — `DML EP can only be used with CPU EPs` (dml+webgpu combined) |
| `auto`   | FAIL — same EP combination issue |
| `cpu`    | OK |

So we must try **one** EP at a time, prefer `dml` on Windows, then
`webgpu`, then `cpu`. Never pass `device: "gpu"` / `"auto"` as-is.

## Goal

OCR worker picks the best available device at init, falls back to CPU on
load failure, logs the chosen device. Optional override via
`MOBIUS_GLM_OCR_DEVICE`.

## Non-goals

- Shipping CUDA EP on Windows (unsupported by onnxruntime-node)
- Changing model weights / dtype (keep `q4f16`)
- Commit unless asked

## Tasks

1. [x] Add `resolveOcrDevice()` / `deviceCandidates()` — platform order + env override.
2. [x] Load model trying candidates until load **and warmup generate** succeed; cache winner.
3. [x] Log `[MobiusOCR] using device=…` to stderr (visible in parent).
4. [x] Rebuild worker, patch installed Mobius, smoke-test (selects `webgpu` here).
5. [x] Delete temp probe scripts.

## Acceptance criteria

- [x] Worker no longer hard-codes only `cpu` when a GPU EP works.
- [x] Init succeeds on this machine with `device=webgpu` (DML rejected by warmup).
- [x] `node scripts/verify-glm-ocr.mjs` still passes.
- [x] Plan tasks marked `[x]`.
