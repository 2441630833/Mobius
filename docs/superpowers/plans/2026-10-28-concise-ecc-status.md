# Concise ECC and selection status

## Root cause
Successful ECC preflight, all suggested Skills, vision passthrough and empty selection outcomes each emit separate chat messages, often displayed together, obscuring the user request and actionable information.

## Goal
Keep ordinary successful preflight and vision routing quiet; show actual Skill/agent selection evidence concisely and preserve actionable failure warnings. Do not change routing, preflight, OCR/vision behavior, or evidence collection.

## Non-goals
Do not hide errors, invent adoption, suppress actual selection details or modify existing unrelated hermes-agent and vendor submodule changes.

## Tasks
1. [x] Simplify Continue chat progress, retaining visible paths and distinguishing injected, read, profile-read and agent tool outcomes.
2. [x] Add targeted regression tests for status policy, failures and separation of visible events. The tools get_errors and manage_todo_list are unavailable; use this checklist, transpilation and compiler diagnostics.
3. [x] Run focused tests and full `pwsh -NoProfile -File scripts/compile-vscode.ps1` from E:/MobiusCode/Mobius; it may take over five minutes. Fix introduced errors.
4. [x] Commit only task changes in vscode and the root repository; confirm remaining status matches predeclared deviations.

## Acceptance criteria
Normal ECC suggestions, supported vision and absence of selections do not add chat noise. Actual selection successes and failures remain correctly identified with paths where available; ECC and image failures remain visible. Routing and sent context remain unchanged; tests and build pass.

## Verification notes
- Selection evidence/status suite: 9 passing.
- npm run compile failed because Windows PowerShell could not find Get-FileHash; the identical build script completed successfully under pwsh 7 with zero compile errors.
- get_errors and manage_todo_list are unavailable; transpile diagnostics were checked after edits.
- Final emitted selection evidence suite: 9 passing. vscode commit: 01ffcc48b30.
