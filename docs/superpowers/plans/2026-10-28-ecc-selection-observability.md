# ECC selection observability

## Root cause
ECC preflight displays matches as recommendations, but Continue does not surface distinct evidence for skill reads and subagent execution. Automatic skills are only path references; explicit selections can be injected. The model's private reasoning is not a reliable observable execution record.

## Goal
Show concise, honest request-scoped execution evidence for actual skill reads and agent delegation, distinguish suggestions and injected selections, and allow a short model-authored decision explanation without claiming access to private reasoning.

## Non-goals
Do not expose hidden reasoning, invent adoption or agent identity, force subagent execution, or change ECC selection behavior. Preserve existing unrelated dirty submodules hermes-agent and vendor/fastmcp, litex, litex-boards, mcp-python-sdk, openFPGALoader.

## Tasks
1. [x] Inspect current selection, tool execution and explicit skill injection APIs; define evidence boundaries.
2. [x] Implement per-request visible evidence and succinct model-facing explanation guidance in Continue, with localized labels and no false success claims.
3. [x] Add regression tests for successful/failed skill reads, explicit injection, agent invocation and absent identities; check syntax after edits. get_errors/manage_todo_list are unavailable; use compiler diagnostics and this checklist.
4. [x] Update English and Chinese README feature descriptions and the ECC catalog based on the current submodule and integration.
5. [x] Run focused tests and full build using `pwsh -NoProfile -File scripts/compile-vscode.ps1` from E:/MobiusCode/Mobius. The full build is known to exceed five minutes. Fix introduced errors.
6. [x] Commit only this task in vscode and the root repository and verify both statuses.

## Acceptance criteria
The UI distinguishes recommendations, injected skills, actual successful or failed reads, and genuine agent calls; it never says a recommended agent ran without evidence. Request/session boundaries and duplicate or failure behavior are covered. A concise explanation is explicitly model-authored, not hidden reasoning. Compilation and regression tests pass or concrete blockers are recorded.

## Documentation scope
The ECC submodule currently contains 71 top-level agent profiles and the integration registers their Markdown files dynamically. Explain this is a changing catalog, not a fixed roster or an automatic delegation guarantee. Correct the existing inaccurate skill preloading and harness roadmap descriptions in both READMEs.

## Verification notes
- Selection evidence suite: 7 passing; existing skill routing suite: 12 passing.
- Full source compilation and a fresh tsgo --noEmit check passed with zero errors.
- `npm run compile` could not find Get-FileHash in Windows PowerShell; retried the same build script with PowerShell 7. Client and extension compilation both succeeded; the full script exited 0.
- get_errors and manage_todo_list are not available in this session; used transpile diagnostics, compiler checks and this plan instead.
- The selection-evidence fixture was corrected to use absolute Windows paths; the rerun passed. vscode commit: 1ff8658670e.
