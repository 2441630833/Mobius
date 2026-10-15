# Adaptive professional agent teams

## Root cause

The first integration has one supervisor, four tasks and three concurrent read-only workers. It lacks a separate difficulty assessor, professional role assignments, per-task summarizers and a final synthesis agent. Workbench receives raw findings but does not display a reliable contribution ledger.

## Goal

Implement assessor -> orchestrator -> professional workers -> individual summary agents -> final synthesis agent with a configurable parallel ceiling from 5 to 10 (default 10). Choose the actual team size from task difficulty and independent work. Show each worker's role, task, execution/summary status and contribution, without claiming the main coding task is finished before the existing parent has implemented and verified it.

## Non-goals

- Workers retain the current read-only tool boundary; parent owns workspace edits and verification.
- No recursive spawning, new provider credentials or deployment of remote agents.
- Preserve existing unrelated root README, hermes/vendor pointers, vscode terminal changes, tmp-repro artifacts and the 2026-10-15 terminal plan. Keep the existing Continue extension junction; include intentional mirrored source changes in vscode when necessary. godogen remains uninitialized and unrelated.

## Tasks

1. [x] Add typed difficulty assessment, role/title task validation, 10-worker ceiling, specialist execution -> per-task summary subgraph, final-summary barrier, deterministic contribution records and truthful phase/completion states in continue/core/agents/orchestrator.ts.
2. [x] Wire separate model calls for assessment, planning, specialists, task summaries and final synthesis into the Continue adapter; update tools/prompts and selected-model/cancellation handling. Add max_agents input (5-10).
3. [x] Add continue.multiAgent.maxParallelAgents setting (5-10, default 10), propagate through the extension bridge and workbench; show contribution reports and require attribution in the parent's final answer. Update docs/research/multi-agent-orchestration.md.
4. [x] Verify actual 5/10 concurrency, assessment/planning order, specialist roles, summary barrier, partial failures, cancellation, attribution and actual tool/command wiring. Run Continue tsc, focused Vitest/Jest/Mocha, extension build, workbench tsgo, npm run check and full compile (pwsh -NoProfile -File scripts/compile-vscode.ps1; can exceed five minutes). get_errors/manage_todo_list are unavailable; use compiler diagnostics and this checked plan.
5. [x] Review and commit intended changes in Continue and vscode once each; commit root docs and intended pointers. Confirm only pre-declared unrelated changes remain. Planned subject: feat: assess and orchestrate professional agent teams with layered summaries.

## Acceptance criteria

- Actual model-backed assessor precedes the planner; worker team size cannot exceed the assessed budget or the configured 5-10 ceiling.
- Ten independent tasks can overlap; roles and task IDs remain distinct through local/A2A execution, individual summaries and final synthesis.
- Per-task summaries consume only that task's bounded evidence; the final synthesis starts after every branch settles. Failures and cancellation cannot be represented as successful task completion.
- Workbench displays a deterministic contribution report, and the parent is told to explain each worker's work in the final response after actual implementation/verification.
- New/changed code has no diagnostic errors. Existing seven extension-only CommonJS/type declaration errors are recorded separately if unchanged. All authorized changes are committed.

## Verification results

- Baseline before this upgrade: 15 graph/adapter tests passed. Final focused Vitest run: 82 tests (14 graph, 10 adapter, 7 real A2A HTTP-fixture tests and 51 existing parsing/discovery tests); existing OpenAI converter Jest suite: 25 passed; workbench source-bundled Mocha suite: 5 passed. Total: 112 passing.
- Real LangGraph tests measure overlapping execution at 5 and 10, not just task counts. They verify assessor-before-planner ordering, exactly one final synthesis after every individual summary, no budget overrun, stable role/task attribution, independently retained failure states, summary fallback and cancellation/timeouts.
- Adapter tests run all model-backed stages at both 5 and 10. The ten-task fixture includes maximum-length task prompts, verifying the planning output budget grows with the assessed team rather than truncating a legal ten-task plan. Worker tool/output budgets remain bounded.
- Continue core tsc: zero errors after final code edit. Workbench tsgo: zero errors. Extension esbuild: passed after the final planning-budget change, including embedding/OCR/chunk worker bundles.
- npm run check: passed. Full scripts/compile-vscode.ps1 under pwsh completed successfully: client compilation and built-in extensions reported zero errors. Native workbench code was unchanged after this build; the final core-only budget change was type-checked, retested and rebundled separately.
- Separate extension CommonJS tsc retains exactly the same seven previously recorded errors in TransformersJsGlmOcrClient.ts:281, VsCodeExtension.ts:291/300/468, ideUtils.ts:138 and VsCodeIde.ts:439/444. None are in changed code; no new diagnostics were introduced.
- Source/model-stream/loopback protocol tests do not claim live cloud model quality, provider quota capacity or a real remote-agent deployment. Workers remain read-only; taskCompleted=false is authoritative for this preflight phase, and the parent still must perform and verify actual implementation.
- Preserve prior README, vendor/hermes pointer deviations, terminal files and repro artifacts. Revert the generated vscode/extensions/continue/build/meta.json change before committing. The existing junction makes the bridge source intentionally tracked in both Continue and vscode.
- Implementation commits: Continue 13eccf873; workbench b3b88130eec. ASCII subjects avoid Windows codepage issues. Root stages only the updated report, this checked plan and the two deliberate pointers; initial unrelated changes remain excluded.
