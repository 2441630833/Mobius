# Fix Local OCR failures (CONNECTION_REFUSED / 180s timeout)

## Root cause

Agents OCR uses Continue command `continue.runGlmOcr` → forked
`transformersJsGlmOcrWorker` (ONNX `onnx-community/GLM-OCR-ONNX`), not
Ollama. Installed Mobius already ships that path.

Observed failures:

1. **Logs (today):** `GLM-OCR timed out after 180000ms` — child hangs or
   spends too long on WebGPU/DML before falling back to CPU.
2. **UI:** `net::ERR_CONNECTION_REFUSED` — Chromium-style refuse, often from
   a dead `127.0.0.1:25137` Ollama probe or a failed local fetch while the
   GPU EP / hub path misbehaves. Bundled Ollama is present but not running.

Display name in UI uses the long HuggingFace id; older builds used `glm-ocr`.

## Goal

Local OCR completes for pasted screenshots under ~60s with a clear error if
the worker never becomes ready; no silent hang until 180s.

## Non-goals

- Full Inno rebuild / commit unless user asks
- Restoring Ollama as primary OCR

## Tasks

1. [x] Prefer `cpu` first on win32 (optional `MOBIUS_GLM_OCR_DEVICE`); keep
      webgpu/dml as later candidates to avoid EH hang.
2. [x] Add fork **ready timeout** (~45s) in `TransformersJsGlmOcrClient` with
      a clear error; reset child.
3. [x] Register `continue.runGlmOcr` / `continue.cancelGlmOcr` in Continue
      `package.json` contributes.commands.
4. [x] Shorten UI model label to `GLM-OCR` in `BUNDLED_ONNX_OCR`.
5. [x] Rebuild worker; patch installed Mobius Continue out/; run
      `node scripts/verify-glm-ocr.mjs` (and installed-tree smoke if needed).
6. [x] Ensure bundled Ollama can start on 25137 for any leftover callers
      (`ensure-ollama.ps1` once) — optional safety, not primary OCR.

## Verified evidence

- Worker bundle: `["cpu", "webgpu", "dml"]` (win32 cpu-first) + warmup, rebuilt 2026-09-04 11:33 (8584 B).
- Installed Mobius `out/transformersJsGlmOcrWorker.js` hash-identical to repo build (`hashMatchRepo: True`), `workerWarmup: True`, `workerCpuFirstSpaced: True`.
- Installed `out/extension.js` contains `did not become ready within` (45s ready timeout).
- `node scripts/verify-glm-ocr.mjs` PASS: `device=cpu (ready 3203ms, warmup ok)`, ONNX responded `"---"` via fork (not Ollama).
- `get_errors`: 0.

## Acceptance criteria

- [x] `verify-glm-ocr.mjs` passes
- [x] Ready timeout fires with a clear message if child never ready
- [x] Device order is cpu-first on Windows unless overridden
- [x] Commands listed in Continue package.json
- [x] Plan tasks marked `[x]`
