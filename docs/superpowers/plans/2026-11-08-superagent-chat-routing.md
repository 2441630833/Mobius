# Super Agent chat request routing

## Root cause
Mobius only submits inferred periodic discoveries to the upstream Engine. Chat requests run independently. The executor's delivery callback does not consume follow-up messages.

## Goal
Automatically route clear complex coding requests to background work, keep simple requests in chat, attach follow-ups to the original task, and apply pause/cancel/status to that task. Persist request ownership and return progress/results to the originating session.

## Non-goals
Do not enable speculative discovery merely because a user requests a task. Do not run foreground and background writers for the same request. Do not discard prior uncommitted panel/documentation changes or unrelated submodule pointers. Do not publish or merge generated changes automatically.

## Tasks
1. [x] Check repository state and pull with --ff-only; upstream reports already up to date.
2. [x] Capture runtime-test and client-typecheck baselines (16 runtime tests, client typecheck passed).
3. [x] Implement persisted explicit-request intake, deduplication, task-scoped controls and follow-up delivery in scripts/superagent; maintain existing inferred discovery behavior.
4. [x] Wire authenticated local request transport and automatic daemon startup using existing Mobius model configuration.
5. [x] Route requests before foreground execution in continueChatAgent.ts; preserve request/session identity, show ownership and return results to the original session.
6. [x] Test routing, duplicate submissions, cancellation, follow-ups, persistence/recovery and workspace state; run client typecheck and full compilation.
7. [x] Update documentation and commit intended changes in vscode and the root repository.
8. [x] Show successful ECC stack detection and recommendations before routing; forward a bounded optional capability catalog to background workers and display only observed adoption, including unused capabilities. Keep todo storage intact during session switching.
9. [x] Apply the tested runtime and desktop bundle to C:/Users/mi/AppData/Local/Programs/Mobius, preserve a complete backup, update the local source revision and verify installed hashes.

## Acceptance criteria
Simple requests stay in chat. Explicit complex coding requests acquire a single background owner. Follow-ups reach the existing worker and cannot be silently dropped. Pause/cancel/status never create new tickets. Uncommitted project changes are handled explicitly rather than silently executing against stale HEAD. Retries and restarts cannot duplicate execution. No credentials are written to task files. Compiler and meaningful behavioral tests pass.

## Execution notes
Workspace E:/MobiusCode/Mobius. Runtime tests: npm run superagent:test. Client check: npm run typecheck-client in vscode. Full build: pwsh -NoProfile -File scripts/compile-vscode.ps1. Current session has full filesystem access. get_errors/manage_todo_list are unavailable; compiler diagnostics and this checklist substitute. Full compilation may exceed five minutes. Preserve unrelated existing submodule deviations: hermes-agent, vendor/fastmcp, vendor/litex, vendor/litex-boards, vendor/mcp-python-sdk, vendor/openFPGALoader. Prior related visibility/panel changes are incorporated. The initial full client/extension compile passed; client compilation is repeated for the subsequently requested ECC visibility changes.

Validation: 24 runtime tests pass against the actual upstream Engine and a mock model endpoint; 133 Edge browser tests pass across chat routing, ECC evidence, todos, historical rendering and ChatModel. The latest client typecheck reports zero errors. Full client and extension compilation completed successfully, and the release esbuild bundle includes the final ownership guard. No paid model calls or external messages were used for verification. Frontend commit: 37d16c72c80.

Hotfix backup: C:/Users/mi/AppData/Local/MobiusHotfixBackups/20261108-chat-routing (complete marker recorded before replacement). All 15 installed upstream core TypeScript files match the pinned source. Do not close active Mobius windows automatically; the replacement files load after restarting Mobius.

Installed hotfix verified: source 37d16c72c8035ee6455b1c522e4dc21c75bc6f80; 13,260 bundle file hashes match; all five runtime/panel files match; both workbench and sessions bundles contain the automatic routing entrypoint. Installed CLI/runtime syntax checks pass. Manifest: C:/Users/mi/AppData/Local/Programs/Mobius/.mobius-chat-routing-hotfix.json. Release tag remains v1.0.21 with the new source revision and refreshed localization cache key.
