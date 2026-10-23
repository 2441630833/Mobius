# Remove automatic parallel research from the workbench Agent

## Root cause
Ordinary non-lightweight code/investigation requests automatically enter a separate Continue extension orchestration path before the selected workbench model can act. That path loads a second model catalog, making it dependent on extension activation and model/config parity. All thrown errors become the same generic warning; the screenshot alone does not identify the underlying exception. Previous worker retries did not address this automatic cross-configuration prerequisite.

## Goal
Honor the user's fallback request and follow-up: delete the complete parallel-research implementation, tools, extension command bridge, dedicated A2A support, configuration example, dependencies, old settings and dedicated tests. Main-agent execution must proceed directly with ordinary tools and skills. Only a rejection guard for calls restored from old conversations remains.

## Non-goals
Do not delete independent CLI review workers, the general subagent model role schema, or user-configured third-party tools. Do not alter release tags or unrelated submodules.

## Tasks
1. [x] Delete the complete workbench and Continue parallel-research implementations and dedicated dependencies/configuration/tests.
2. [x] Reject retired tools restored from old chats; verify ordinary tools still run and remove obsolete current documentation.
3. [x] Typecheck, build the extension, run focused regressions, and commit/push Continue, VS Code, and root pointer/plan changes.

## Acceptance criteria
No Agent request automatically calls continue.orchestrateAgents or displays parallel-research progress/failure. orchestrate_agents is not advertised or callable through workbench tool aliases. Other tool execution and skill routing remain available.

## Results
VS Code client and Continue core typechecks passed. Extension esbuild and all worker bundles passed. Four core tool suites passed 21 tests; workbench tool/network gating passed 13 tests. The actual extension bundle contains no removed orchestration command, tools, or graph SDK. Both dependency manifests and the lockfile are pruned. Obsolete architecture documentation and A2A configuration example are deleted. Workbench extension source mirrors are synchronized with Continue.

Standalone extension tsc reports seven preexisting errors (CommonJS import.meta, definite assignment, and TextDocument.encoding typings). Verified by temporarily compiling the original HEAD sources, which reproduced the same seven errors; all current edits were then restored. No unrelated source fixes were made. Existing execution-plan records remain as historical records, not executable code or active settings. No release tag was changed for this task.

## Verification
Use npm run typecheck-client per vscode/AGENTS.md, then focused tool-bridge regressions. No get_errors/manage_todo_list tools are exposed; compiler and this checklist substitute. Preserve existing hermes-agent and vendor/{fastmcp,litex,litex-boards,mcp-python-sdk,openFPGALoader} changes. No provider credentials or live user logs are required for verifying that the removed branch cannot run.
