# Local GLM-OCR startup and packaging

## Root cause
Pulled main and synchronized its pinned vscode/continue submodules before investigation. Reproduced the installed Mobius.exe worker exit with code=1 signal=null: MODULE_NOT_FOUND for @huggingface/transformers. The installed extension also lacks GLM-OCR weights. The worker externalizes Transformers.js, but normal prepackage only copies MiniLM's ORT dependencies. Windows CI skips the separate GLM-OCR bundling script. The client discards stderr when reporting exits.

## Goal
Ship a complete, target-specific OCR runtime and local model in desktop packages. Surface bounded startup diagnostics instead of a bare exit code. Validate production worker startup and real OCR.

## Non-goals
Do not send user images to a cloud service or enable OCR by default. Preserve unrelated submodule revisions. Do not publish an unverified release.

## Tasks
1. [x] Add reusable OCR packaging for runtime dependencies and complete local model files; wire it into the common extension packaging path. Remove the legacy Windows skip route and replace hardcoded x64 setup with the portable helper.
2. [x] Preserve worker startup stderr and isolate process lifecycle failures; add regression coverage.
3. [x] Typecheck, bundle, run packaging/client regressions and actual OCR smoke test; verify installed startup path.
4. [x] Commit and push intended Continue/VS Code mirrors and root changes.

## Acceptance criteria
A packaged worker can resolve its exact runtime dependency graph without the source checkout. Model assets are complete and local inference succeeds. Startup failure identifies the missing module/model or native loader problem. No unrelated work is discarded.

## Verification
Apply fix-onnx-worker-windows-gpu-hang skill's evidence-first flow. Use core TypeScript checking, node --check for packaging helpers, isolated packaging fixtures, extension esbuild, and production fork smoke with Mobius.exe. get_errors/manage_todo_list are unavailable; compiler and checklist substitute. Initial unrelated changes: hermes-agent and vendor/{fastmcp,litex,litex-boards,mcp-python-sdk,openFPGALoader}.

## Results
Core typecheck passed, 3 worker lifecycle tests and 2 packaging/model tests passed. Extension plus worker esbuild passed. Node syntax checks and PowerShell parser checks (including the Windows PowerShell 5 asset gate) passed. Runtime install pins the exact Transformers version from the installed core dependency and keeps its ORT separate from MiniLM's ORT 1.14. All release targets validate their native ORT binding, sharp platform package and local model assets before packaging.

Actual inference used the installed Mobius.exe in ELECTRON_RUN_AS_NODE mode with NODE_PATH cleared, a fresh packaged runtime, and two text-image requests. Both returned exactly "OCR 123". Repeated after syncing the installed extension, isolated runtime, worker and local weights: both requests passed again with Transformers 4.2.0. Source/installed worker hashes and extension bundle hashes match. Previous installed worker/extension are backed up under the system temp directory mobius-ocr-before-fix-20261026. Reloading the app/window activates the updated client bundle; the worker/runtime repair is already on disk.

Intel macOS needs ORT 1.23.2 because the upstream 1.24 npm tarball lacks its native binding (https://github.com/microsoft/onnxruntime/issues/27961). Confirmed that 1.23.2 contains the Intel macOS binary and ran its CPU model compatibility with two images on Windows successfully. This is not an Intel macOS or Linux runtime test; those platforms still need CI/native-host validation. ORT 1.22 was tested and rejected because it cannot load the model's GatherBlockQuantized bits attribute.

Concurrent work updated main from c0f2b1fac to ce362d98a and reset the shared checkout during investigation. Completed the fix in an isolated worktree based on that newer commit, pushed Continue d4c27bb09, then fast-forwarded the shared checkout without discarding the concurrent work. VS Code extension mirrors are synchronized in be78abdfd04. No new release/tag was created; future desktop builds now include roughly 650 MB of local OCR weights plus the isolated runtime.

The isolated worktree is clean and fully committed. Automatic approval review blocked its cleanup command with only "blocked by policy" and no further reason, so the worktree is retained at E:/MobiusCode/mobius-ocr-runtime-worktree. Shared dependency junctions and the original workspace were not deleted.
