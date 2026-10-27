# Preserve the current user request

## Root cause
ECC output is promoted to system instructions. Automatically recalled skill bodies introduce unrelated deliverables and an execution override forces edits before sufficient inspection.

## Goal
Keep current user intent authoritative. Automatic recall supplies optional references, while explicit skill invocations still load their bodies.

## Non-goals
Preserve unrelated dirty submodules hermes-agent and vendor/*. Incorporate the existing vscode workspace-scope routing changes and October 26 plan. The October 27 todo implementation is already in HEAD; retain its plan and verify its tests. No deployment or installer changes.

## Tasks
1. [x] Separate automatic skill references from explicitly requested skill bodies in warm and cold routing.
2. [x] Stop promoting ECC output to system instructions, fail open without invented fallback workflows, and enforce current-request precedence.
3. [ ] Add regressions; run targeted tests and npm run compile (may exceed five minutes). get_errors/manage_todo_list are unavailable; use this checklist and compiler diagnostics.
4. [ ] Review and commit related vscode changes and root plans/pointer; preserve declared unrelated changes.

## Acceptance criteria
Auto-routed skill body instructions cannot introduce mockups, new projects, README edits or other deliverables into the model request. Explicit skills remain available. ECC failure supplies no workflow. The original user message remains intact. Tests and compilation pass or external blockers are recorded accurately.

## Implementation notes
Automatic matches pass only names and paths, with an explicit instruction for the LLM to decide whether reading the skill helps the current request. Warm and cold paths both avoid body injection. Explicit slash/attachment requests bypass the warm shortcut and cannot be displaced by automatic ranking. ECC output is no longer appended to the system prompt; failed ECC returns no invented workflow. The final system guidance gives current-user-request precedence over supplementary context.
