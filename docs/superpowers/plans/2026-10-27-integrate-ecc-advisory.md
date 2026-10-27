# Integrate Non-Intrusive ECC Advisory

## Root Cause
Previously, ECC preflight generated a heavyweight engineering loop (`Plan -> Test/Audit -> Implement -> Verify -> Document`) and injected it directly into `agentSystem`. This hijacked user intent on simple queries or minor edits. Complete removal silenced ECC entirely, preventing the model from benefiting from project stack detection and optional ECC tools on complex tasks.

## Goal
Integrate ECC preflight output as a non-intrusive `<ecc-advisory>` block:
1. Provide passive background context (detected tech stack, optional ECC tools/skills).
2. Explicitly instruct the model that it is NOT a user instruction or workflow requirement.
3. Model self-determines usage: ignore for simple tasks (style, minor edits, questions); leverage for complex tasks (architecture, major refactoring, audits).
4. Strictly prioritize user's explicit request and forbid scope expansion.

## Non-goals
- Do not re-introduce mandatory engineering loops or quality gates into `agentSystem`.
- Do not preload full ECC skill bodies into prompts.
- Do not touch unrelated submodules (`hermes-agent`, `vendor/*`).

## Tasks
1. [x] Update `continueEccWorkflow.ts`:
   - Extend `EccPreflightResult` to include `projectType`.
   - Export `buildEccAdvisory(result: EccPreflightResult | undefined): string | undefined`.
2. [x] Update `continueChatAgent.ts`:
   - Compute `eccAdvisory` from `eccPreflightResult` via `buildEccAdvisory`.
   - Pass `eccAdvisory` to `buildChatMessages` and inject into `userParts` alongside `skillAttachments`.
3. [x] Update unit tests:
   - Add unit tests in `continueEccWorkflow.test.ts` and `continueRequestPriority.test.ts` verifying `<ecc-advisory>` format and priority assertions.
4. [x] Compile and verify:
   - Run `npm run compile-client` to verify 0 errors.
5. [x] Commit and push:
   - Stage and commit in `vscode` and `Mobius` root.
   - Push and update release tag.

## Acceptance Criteria
- Simple requests are never forced into multi-stage engineering loops.
- `<ecc-advisory>` provides passive stack detection and tool advice.
- Unit tests pass with 0 errors.
- Compilation succeeds with 0 errors.
