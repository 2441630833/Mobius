---
name: fix-onnx-worker-windows-gpu-hang
description: "Use when a packaged extension's local ONNX/Transformers.js worker for OCR, embeddings, or other model inference times out or reports connection refused, especially on Windows where the GPU execution provider can hang during startup."
auto-generated: true
generated-at: 2026-09-04T05:12:01.624Z
source-task: "continue"
---
## When to use
- A desktop/extension feature spawns a local Node/Electron worker for ONNX Runtime or Transformers.js inference (OCR, embeddings, ASR, vision) and the UI shows `ERR_CONNECTION_REFUSED`, a generic timeout, or never returns.
- The failure is platform-specific, especially Windows, and model initialization or first inference is suspected.
- You changed source but need to prove the installed/running application is actually using the fix.

## Steps
1. **Find the real execution path.** Trace the feature command to the child process/worker entry point. Confirm whether it is an HTTP server, forked Node worker, or native runtime; inspect both repository build output and the installed application's resources.
2. **Capture worker startup evidence.** Run the worker or a minimal harness with logging for platform, architecture, ONNX device, execution providers, model load time, and first inference. A hang and a crash need different fixes.
3. **Force a safe execution provider on affected platforms.** For Windows/known-bad GPU stacks, initialize ONNX/Transformers.js with CPU first (for example `device: 'cpu'` / `executionProviders: ['cpu']`) before creating the session. Keep GPU behind a flag or add fallback only after CPU startup is proven.
4. **Warm up the model after load.** Run a tiny dummy input through the pipeline and log `ready` time. This makes initialization failures happen before the user's request and avoids blaming the first real image or document.
5. **Add an explicit readiness timeout.** The client should wait a bounded time (such as 45 seconds) for worker ready/warmup, then report that the local worker failed to start, including platform/device logs instead of a misleading connection error.
6. **Build and install the artifact.** Rebuild, then copy or sync the built worker and extension bundle into the installed application's resources. Reload the desktop app/window after copying.
7. **Verify the running code, not just the source.**
   - Run a smoke test that loads the worker and performs one real inference.
   - Compare hashes of the repository build output and installed worker file.
   - Search the installed bundle for the new timeout/device logic.
   - Run type/compile error checks and require zero errors.
8. **Record evidence.** Document root cause, changed behavior, verification commands, smoke-test output, hash match, and the reload requirement.

## Pitfalls
- `ERR_CONNECTION_REFUSED` often means the child worker never became ready; it does not necessarily mean the network address is wrong.
- A GPU execution provider can hang without throwing, so a `try/catch` around inference may never run. Select CPU before session creation on affected platforms.
- Editing TypeScript source has no effect on a packaged app until the bundle is rebuilt and copied into the installed resources directory.
- A matching hash proves deployment but not correctness; still run inference in the installed context.
- Model download/load can take tens of seconds. Warmup logs separate slow initialization from a dead worker.
- Do not discard worker stderr; device, execution provider, and ONNX logs are the key diagnostic evidence.
- Windows may lock running files; fully reload or restart the app before verifying.

## Example
A local OCR command forks a Transformers.js/ONNX worker. On Windows, GPU provider initialization stalls until the UI's 180-second request fails with connection refused. The worker is changed to use CPU on Windows, performs a dummy OCR warmup after model load, and the client fails after 45 seconds with a clear "worker not ready" message. After rebuilding, a verification script logs `device=cpu`, ready time, warmup success, and returned OCR text. The repository worker hash is compared with the installed `resources/app/extensions/<extension>/out/<worker>.js` hash, the installed extension bundle is searched for the timeout logic, and the app is reloaded.
