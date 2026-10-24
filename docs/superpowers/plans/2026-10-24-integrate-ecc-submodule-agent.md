# Integrate ECC Submodule and Pre-Request Agent Execution

## Root cause / Context

The user requested:
1. Pull `https://github.com/affaan-m/ECC.git` into our submodules.
2. Integrate this project into our general agent (Mobius default Agent mode / Continue chat agent).
3. Run this project before every request is processed by the agent (`每次跑请求前运行这个项目`).
4. Integrate this project into the agent's task invocation loop (`集成这个项目到我们的agent 调用任务中`).

ECC (Everything Claude Code / Agent Harness Performance Optimization System) provides a multi-harness operating layer consisting of:
- 300+ specialized engineering skills (`skills/*/SKILL.md`)
- Pre-request hooks (`session-start.js`, `context-prompt-suggestions.js`, `consult.js`)
- Quality gates, security monitors, instinct management, and memory stores
- CLI tools (`ecc.js`, `consult.js`, `doctor.js`, `status.js`, `profile.js`)

In Mobius, the General Agent is implemented by `ContinueChatAgent` in `vscode/src/vs/workbench/contrib/continue/browser/continueChatAgent.ts` (Agent mode, `CONTINUE_AGENT_IDS.agent`). Integrating ECC requires adding the submodule, establishing pre-request execution in `ContinueChatAgent.invoke()`, registering ECC skills and agents via `IPromptsService`, providing native ECC agent tools (`ecc_run`, `ecc_consult`, `ecc_skill`) during task execution, and registering the workflow contribution.

## Goal

1. Add `https://github.com/affaan-m/ECC.git` as a Git submodule at `ECC` with production dependencies ready.
2. Implement `scripts/ecc-agent-preflight.js` and `scripts/ecc-cli.js` as fast, standalone entrypoints for preflight analysis and task execution.
3. Implement `continueEccWorkflow.ts` in VS Code to:
   - Provide all 300+ ECC skills to `IPromptsService` (`PromptsType.skill`).
   - Provide ECC agents to `IPromptsService` (`PromptsType.agent`).
   - Execute ECC preflight before every request in Agent mode, surfacing active instincts, detected project types, and recommended skills in chat progress and injecting `<ecc-context>` into the agent system prompt.
   - Execute ECC tools (`ecc_run`, `ecc_consult`, `ecc_skill`) during agent tasks.
4. Wire ECC workflow into `continueChatAgent.ts`, `continueCopilotToolsBridge.ts`, and `continue.contribution.ts`.
5. Add unit tests in `continueEccWorkflow.test.ts`.
6. Verify compilation and execution with 0 errors.

## Non-goals

- Altering unrelated submodules (`hermes-agent`, `vendor/*`).
- Overwriting existing uncommitted plan documents from prior sessions (`2026-10-24-fix-agent-mode-auto-routing.md`).
- Breaking specialized mode routing (Chip, Game, PPT).

## Tasks

1. [x] Add `ECC` as git submodule (`git submodule add https://github.com/affaan-m/ECC.git ECC`) and install production dependencies (`npm install --omit=dev` inside `ECC`).
2. [x] Create `scripts/ecc-agent-preflight.js` and `scripts/ecc-cli.js` to run ECC analysis and CLI operations cleanly.
3. [x] Create `vscode/src/vs/workbench/contrib/continue/browser/continueEccWorkflow.ts` implementing skill registration, pre-request preflight, and agent tool execution.
4. [x] Update `vscode/src/vs/workbench/contrib/continue/browser/continueChatAgent.ts` to execute ECC before every request in Agent mode and route ECC tool calls.
5. [x] Update `vscode/src/vs/workbench/contrib/continue/browser/continueCopilotToolsBridge.ts` to register ECC tool schemas.
6. [x] Update `vscode/src/vs/workbench/contrib/continue/browser/continue.contribution.ts` to register ECC workflow contribution.
7. [x] Add unit test file `vscode/src/vs/workbench/contrib/continue/test/browser/continueEccWorkflow.test.ts`.
8. [x] Verify compilation and execution with 0 errors.
9. [x] Commit changes cleanly.

## Acceptance criteria

- `git submodule status` shows `ECC` present and initialized.
- Every prompt processed by Mobius Agent mode runs ECC preflight before calling the model, injecting `<ecc-context>` and displaying ECC status in chat progress.
- Agent has access to `ecc_run`, `ecc_consult`, and `ecc_skill` tools during task execution.
- 300+ ECC skills are registered as prompt skills and discoverable by Mobius skill embedding index.
- All unit tests and TypeScript compilation pass with 0 errors.
