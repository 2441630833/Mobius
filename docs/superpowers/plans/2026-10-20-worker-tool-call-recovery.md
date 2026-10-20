# Worker tool-call recovery

## Root cause
The screenshot reports a malformed file_glob_search call. The exact provider response is unavailable. The local worker adapter lets provider tool-format errors escape directly into a failed artifact, while only execution errors get feedback. Text-only tool markup can also be mistaken for a final answer.

## Goal
Recover from malformed worker calls within a bounded retry budget, preserve the read-only allowlist and cancellation, and retain explicit failure when recovery is exhausted.

## Non-goals
Do not revisit the user's completed platform fixes, change model credentials, execute XML as code, or publish a release.

## Tasks
1. [x] Add worker-only format validation and bounded corrective retries in continue/core/tools/implementations/orchestrateAgents.ts. Include the original request in worker context, including generic fallback tasks.
2. [x] Add regression coverage in orchestrateAgents.vitest.ts for provider errors, textual calls, invalid JSON, cancellation, and persistent failure. Align two stale orchestrator tests with the user's already committed fallback/clamping behavior; do not revert that implementation.
3. [x] Run Continue core TypeScript checking and targeted orchestration tests; commit the Continue change and root pointer/plan.

## Results
Continue core TypeScript checking passed. Both orchestration suites passed (31 tests, including 7 new regression cases). The actual extension and its MiniLM/GLM-OCR/chunk worker bundles built successfully with `npm run esbuild`. Continue commit: a41e00b4b. Changes are platform-independent, but no live provider replay or Ubuntu ARM/macOS runtime verification was possible from this Windows environment. No release tag was created.

## Acceptance criteria
A corrected call executes exactly once and yields actual evidence. Repeated malformed responses fail explicitly. Authentication/network errors are not classified as format errors. Existing read-only policy tests pass.

## Verification and workspace
Run `npx tsc --noEmit --pretty false` and `npx vitest run tools/implementations/orchestrateAgents.vitest.ts agents/orchestrator.vitest.ts` from E:/MobiusCode/Mobius/continue/core, then `npm run esbuild` from continue/extensions/vscode to verify the actual extension bundle. No get_errors or manage_todo_list tool is exposed; this checklist and TypeScript compiler are their substitutes. This core-only change does not require compiling VS Code. Preserve existing unrelated changes in hermes-agent, vendor/fastmcp, vendor/litex, vendor/litex-boards, vendor/mcp-python-sdk, and vendor/openFPGALoader. No Ubuntu ARM or macOS runtime is available locally.
