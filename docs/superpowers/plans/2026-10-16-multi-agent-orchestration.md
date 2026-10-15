# Multi-agent orchestration and A2A integration

## Root cause

Mobius workbench chat has a single agent loop. Some Copilot subagent names are advertised but there is no Mobius-owned parallel supervisor, bounded shared context, or interoperable remote-agent client. Continue already owns configured model instances and read-only tools; reuse them rather than asking for another API key.

## Goal

Research maintained open-source orchestration projects and protocols, integrate LangGraph JS into Continue as a bounded supervisor/parallel-worker graph, expose the capability to both Continue and workbench chat, and integrate the official A2A JS client for explicitly configured remote agents. Each complex Agent request goes through a planning agent before workers; parent remains responsible for edits, verification, and the final response.

## Non-goals

- No concurrent workspace writes, recursive worker spawning, automatic remote discovery, or sharing entire chat histories/secrets.
- No replacement of existing provider configuration, no new chat mode, no public inbound A2A server in this change.
- Preserve pre-existing changes: root README.md; hermes-agent; vendor/fastmcp, litex, litex-boards, mcp-python-sdk, openFPGALoader; vscode terminal files; docs/superpowers/plans/2026-10-15-agent-terminal-cursor.md. Preserve vscode/tmp-repro.mjs and tmp-repro.png as existing terminal-reproduction artifacts, excluded from this commit. Submodule pointer deviations stay untouched except deliberate Continue/vscode commits for this feature.

## Tasks

1. [x] Compare LangGraph/Deep Agents, Microsoft Agent Framework, Google ADK, CrewAI and Mastra using upstream documentation; distinguish A2A, MCP and application-owned shared memory in docs/research/multi-agent-orchestration.md.
2. [x] Add pinned @langchain/langgraph and @a2a-js/sdk dependencies to continue/core with lockfile. Implement a supervisor graph, bounded parallel read-only worker loops, scoped shared context and structured results, cancellation/timeout and task limits. Add official SDK-backed remote-agent client restricted to operator-configured endpoints.
3. [x] Register orchestration tools in Continue and wire workbench request preprocessing, progress, cancellation and selected model. Ensure simple/Chat requests keep their existing path; complex requests receive worker artifacts before the parent loop. Update configuration/help.
4. [x] Run meaningful graph/concurrency/isolation/failure/protocol/wiring tests, Continue TypeScript diagnostics, npm run check and npm run compile. Full compile can exceed five minutes and must still be attempted. Build failures originating in pre-existing files/dependencies are recorded explicitly. get_errors and manage_todo_list tools are not exposed in this session; compiler diagnostics and this checked plan are their available equivalents.
5. [x] Mark this plan complete, review diffs, commit only intended files in each changed submodule, then commit root docs/config and deliberate pointers. Verify status contains only declared unrelated changes. Planned commit subject: feat: orchestrate parallel research agents with LangGraph and A2A.

## Acceptance criteria

- Supervisor performs real model planning, independent workers overlap with a maximum concurrency and tool-step limit, and parent receives attributed successes/failures without parallel edits.
- Shared context is bounded, request-scoped and explicit; peers do not share raw mutable conversations. A2A context IDs group conversations and do not imply shared memory.
- Workbench and Continue discover and dispatch the tools using existing configured models. Cancellation/timeout terminates work, and remote transport never inherits the model API credentials.
- Tests exercise real LangGraph and the SDK transport against a local fixture without cloud credentials. Production model/network verification limits are reported honestly.
- No task files remain staged or uncommitted after completion.

## Verification results and deviations

- Baseline: 51 existing parseArgs/searchWebGating tests passed before implementation.
- Final: 73 Vitest tests across graph, SDK HTTP fixture, Continue adapter, argument parsing and tool discovery; 25 existing OpenAI converter Jest tests; 3 workbench command/routing/cancellation tests bundled from the actual TypeScript sources and executed with Mocha. Total: 101 passing.
- Continue core `npm run tsc:check`: zero errors. Workbench `tsgo -p src/tsconfig.json --noEmit --skipLibCheck`: zero errors, including the new routing tests.
- Continue extension `npm run esbuild`: passed, including MiniLM/GLM-OCR/chunk worker bundles. Rebuilt after the final streaming compatibility fix.
- Root `npm run check`: passed. `npm run compile` initially failed because the old Windows PowerShell could not resolve Get-FileHash. The same scripts/compile-vscode.ps1 invoked with `pwsh -NoProfile -File` completed successfully: client compilation and built-in extensions, zero errors (about eight minutes).
- The extension's separate CommonJS tsc command still reports seven pre-existing errors: TransformersJsGlmOcrClient.ts:281 import.meta under CommonJS; VsCodeExtension.ts:291,300,468 definite initialization; ideUtils.ts:138 and VsCodeIde.ts:439,444 missing TextDocument.encoding. These same seven were present in the first extension diagnostic run, before the new tests. No changed-file/new-feature errors remain. commands.ts's pre-existing missing Core type import was repaired because that file is part of the integration.
- Dependency pins: @langchain/langgraph 1.5.0 and @a2a-js/sdk 1.3.0. No live provider credentials or real external A2A service were used; test fixtures exercise actual graph and protocol code, not planning quality or production service availability.
- A2A first-contact context IDs are assigned by the remote; local run IDs are metadata. Tests verify this distinction and best-effort CancelTask after local cancellation.
- Fixed streaming interoperability discovered during review: preserve OpenAI tool indices and handle repeated Anthropic tool names by call ID. Dedicated regression tests plus the existing converter suite pass.
- vscode/extensions/continue is an existing junction to continue/extensions/vscode, and vscode tracks some of those source files. The three intentional extension source changes are therefore committed in both repositories. The generated extensions/continue/build/meta.json change is reverted to its pre-task version; it is a build artifact, not part of this feature.
- Existing submodule pointer deviations listed above remain untouched. godogen was already uninitialized and is unrelated; no initialization or checkout was forced. Existing terminal-reproduction artifacts and the previous terminal plan remain preserved as declared.
- Source integration/builds are complete; no installer release, public A2A server or automatic real-service configuration is claimed.
- Reviewed implementation commits: Continue `67b5b6633`, workbench `ffedd303734`. Both commit subjects are ASCII/UTF-8 safe. Root commit includes only this plan, the research report, the A2A example and these intentional pointers. Pre-existing README/vendor/terminal work remains outside the staged set.
