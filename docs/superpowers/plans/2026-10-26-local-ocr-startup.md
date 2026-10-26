# Local GLM-OCR startup and packaging

## Root cause
Pulled main and synchronized its pinned vscode/continue submodules before investigation. Reproduced the installed Mobius.exe worker exit with code=1 signal=null: MODULE_NOT_FOUND for @huggingface/transformers. The installed extension also lacks GLM-OCR weights. The worker externalizes Transformers.js, but normal prepackage only copies MiniLM's ORT dependencies. Windows CI skips the separate GLM-OCR bundling script. The client discards stderr when reporting exits.

## Goal
Ship a complete, target-specific OCR runtime and local model in desktop packages. Surface bounded startup diagnostics instead of a bare exit code. Validate production worker startup and real OCR.

## Non-goals
Do not send user images to a cloud service or enable OCR by default. Preserve unrelated submodule revisions. Do not publish an unverified release.

## Tasks
1. [ ] Add reusable OCR packaging for runtime dependencies and complete local model files; wire it into the common extension packaging path.
2. [ ] Preserve worker startup stderr and isolate process lifecycle failures; add regression coverage.
3. [ ] Typecheck, bundle, run packaging/client regressions and actual OCR smoke test; verify installed startup path if feasible.
4. [ ] Commit and push intended Continue/VS Code mirrors and root changes.

## Acceptance criteria
A packaged worker can resolve its exact runtime dependency graph without the source checkout. Model assets are complete and local inference succeeds. Startup failure identifies the missing module/model or native loader problem. No unrelated work is discarded.

## Verification
Apply fix-onnx-worker-windows-gpu-hang skill's evidence-first flow. Use core TypeScript checking, node --check for packaging helpers, isolated packaging fixtures, extension esbuild, and production fork smoke with Mobius.exe. get_errors/manage_todo_list are unavailable; compiler and checklist substitute. Initial unrelated changes: hermes-agent and vendor/{fastmcp,litex,litex-boards,mcp-python-sdk,openFPGALoader}.
