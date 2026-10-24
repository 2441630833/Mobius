# Integrate DeepSeek Harness & Complete Mobius Pluggable Agent Harness

## Root cause

Mobius previously only shipped with Continue as its single, hardwired, compiled-in agent harness. While Continue provides chat and inline editing, complex multi-step reasoning, autonomous execution loops, loop-hygiene guards (e.g. anti-repetition, step budget, tool-execution deadlines), and decoupled capability seams (Service Definition / Provider / Consumer) were either monolithic or incomplete.

DeepSeek's open-source agent harness (`deepseek-harness`, `@deepseek-ai/dsh`) introduces an "everything-is-a-plugin" architecture built on Cordis, separating core loop lifecycle (`turn/start`, `step/start`, `tool/call`, `tool/result`, `step/end`, `turn/end`), loop hygiene guards (`guard/`), decoupled capability seams (`llm/`, `shell/`, `fs/`, `tools/`, `skill/`, `subagent/`), and dynamic composable profiles.

To realize the Mobius Pluggable Agent Harness roadmap outlined in `README.md`, we must incorporate `deepseek-harness` as a git submodule and build out Mobius's pluggable agent harness layer to seamlessly support both Continue and DeepSeek Harness engines.

## Goal

1. **Submodule Integration**: Add `https://github.com/deepseek-ai/deepseek-harness.git` as a git submodule at `deepseek-harness`, recorded in `.gitmodules`.
2. **Pluggable Agent Harness Architecture**:
   - Design and implement `IMobiusAgentHarness` interface and `MobiusHarnessRegistry` in `vscode/src/vs/workbench/contrib/continue/browser/continueAgentHarness.ts`.
   - Support engine registration, selection, live switching, and configuration via `mobius.agentHarness.engine` ('continue' | 'deepseek').
3. **DeepSeek Agent Harness Implementation**:
   - Implement `DeepSeekAgentHarness` in `vscode/src/vs/workbench/contrib/continue/browser/continueDeepSeekHarness.ts`.
   - Incorporate key architectural paradigms from `deepseek-harness`:
     - **Turn & Step Lifecycle** with event hooks (`turn/start`, `step/start`, `tool/call`, `tool/result`, `step/end`, `turn/end`).
     - **Loop Hygiene Guards**: Anti-repetition guard (detecting duplicate tool execution loops) and timeout deadline enforcer.
     - **Modular System Prompt & Context Assembly**: System prompt sections (Persona, Working Memory scratchpad, Skill Memory, Tool Schemas).
     - **Capability Seam Providers**: Bridge to Mobius tools (Terminal, Files, Git, Godot, FPGA, PPT, Skills) and Language Model service.
4. **Continue Agent Harness Adapter**:
   - Implement `ContinueAgentHarness` in `vscode/src/vs/workbench/contrib/continue/browser/continueContinueHarness.ts` to wrap Continue's loop into the pluggable interface, ensuring 100% backward compatibility.
5. **Mobius Workbench Registration & Command Integration**:
   - Register the harness subsystem and configuration in `continue.contribution.ts`.
   - Add command `workbench.action.mobius.switchAgentHarness` to switch between Continue and DeepSeek engines on the fly.
   - Wire `continueChatAgent.ts` to dispatch through the active harness.
6. **RSI & Schema Alignment**:
   - Extend `rsi-test/lib/harness-schema.ts` to reflect the DeepSeek Harness capability seams and plugin profile structure, enabling RSI 2.0 evaluation and co-evolution.
7. **Documentation**:
   - Update `README.md` and `README.zh-CN.md` to document the pluggable harness architecture and DeepSeek Harness integration.

## Non-goals

- Replacing or deleting Continue's existing UI, autocomplete, or inline diff features.
- Modifying remote LLM model weights.
- Altering the upstream `deepseek-harness` submodule repository directly.

## Tasks

1. [x] Add `https://github.com/deepseek-ai/deepseek-harness.git` as a submodule at `deepseek-harness` with `--depth 1` and verify `.gitmodules`.
2. [x] Implement `continueAgentHarness.ts` defining `IMobiusAgentHarness`, `MobiusHarnessRegistry`, and lifecycle events.
3. [x] Implement `continueDeepSeekHarness.ts` with turn/step lifecycle, loop hygiene guards (anti-repetition, deadline enforcement), prompt assembly, and tool bridges.
4. [x] Implement `continueContinueHarness.ts` as the standard Continue engine wrapper.
5. [x] Wire harness selection and switching into `continue.contribution.ts` and `continueChatAgent.ts`.
6. [x] Extend `rsi-test/lib/harness-schema.ts` with DeepSeek Harness profile and capability seam definitions.
7. [x] Update `README.md` and `README.zh-CN.md` with the completed Pluggable Agent Harness architecture.
8. [x] Verify compilation and TypeScript typing without errors.
9. [x] Stage all changes and commit cleanly following AGENTS.md rules.

## Acceptance criteria

1. `git status` reflects `deepseek-harness` submodule registered in `.gitmodules`.
2. `MobiusHarnessRegistry` exposes both `ContinueAgentHarness` ('continue') and `DeepSeekAgentHarness` ('deepseek').
3. Configuration setting `mobius.agentHarness.engine` allows selecting between `'continue'` and `'deepseek'`.
4. DeepSeek Harness provides loop hygiene guards (repetition detector, timeout handler) and event-driven step execution.
5. Code compiles with zero TypeScript / build errors.
6. Documentation accurately describes the new architecture.
