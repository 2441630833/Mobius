# Restore agent progress and capability visibility

## Root cause
Installed Mobius is v1.0.21, workbench e5ae31dceaf1b3859c0f6d7955bc46408994e7c9 (2026-11-01), with the Super Agent runtime present. Successful ECC preflight is deliberately hidden; selection evidence only appears for observed tool use, with no final unused summary. Super Agent exposes palette commands only. Todo updates depend on model cooperation and bounded final reminders, with no intermediate stale-progress checkpoint.

Follow-up investigation found a separate deterministic regression: ChatToolInvocationPart writes historical todo snapshots to persistent storage whenever virtualized tool rows mount. Switching sessions or scrolling can therefore replace current todos with older requests. Rendering must be read-only; built-in tool execution already saves updates, and external-tool updates must be saved at progress ingestion instead.

## Goal
Make current-request todos update during execution and reconcile at completion without fabricating completed work. Show routed candidates and observed use/non-use of agents and skills. Expose Super Agent through a persistent workbench entry and a usable control panel. Build and apply the reviewed workbench changes to the installed local app with a backup.

## Non-goals
Do not mark failed/cancelled work completed. Do not automatically activate paid background coding. Preserve existing unrelated submodule deviations in hermes-agent, vendor/fastmcp, vendor/litex, vendor/litex-boards, vendor/mcp-python-sdk, vendor/openFPGALoader. Do not overwrite user settings or credentials.

## Tasks
1. [x] Inspect installed release, source version, logs and existing todo/ECC/Super Agent paths.
2. [x] Add bounded intermediate todo checkpoints and strengthen final status reconciliation with tests.
3. [x] Display ECC routing candidates and final observed selection summary with tests.
4. [x] Add a visible Super Agent workbench entry and panel controls/status.
5. [x] Typecheck, run regression tests, compile and bundle the workbench; apply to local installation with backup and verify loaded assets.
6. [x] Commit intended vscode and root changes, preserving unrelated changes.
7. [x] Prevent historical tool-card rendering from overwriting current todos; verify local persistence, clearing, session isolation and successful external-tool ingestion.

## Acceptance criteria
Todo synchronization is tied to actual model/tool evidence rather than unconditional completion. Each Agent response exposes whether agent/skill context was used and distinguishes candidates from actual execution. Super Agent is discoverable without memorizing commands. Installed runtime files match the tested artifacts. No background service is started implicitly.

## Validation
Use vscode npm run typecheck-client, focused Continue workbench tests, root npm run superagent:test and prerequisite checks, then pwsh -NoProfile -File scripts/compile-vscode.ps1 and the workbench bundle build. get_errors/manage_todo_list are unavailable; compiler diagnostics and this checklist substitute. Full builds may take more than five minutes. Planned commits: fix: synchronize agent progress and expose capability selection.

Completed: root prerequisite check; 16 Super Agent runtime tests; client typecheck; full client and built-in extension compilation; final client recompilation after the session-history fix; 112 Chromium/Edge browser unit tests covering Continue todos/evidence, status, todo widget/history and ChatModel. Panel smoke test with simulated tasks verified branch rendering, pause controls and no script errors. Bundling uses the repository's release esbuild entrypoint (desktop/minify/mangle/NLS). No paid model calls were made.

Local installation backup: C:/Users/mi/AppData/Local/MobiusHotfixBackups/20261104-agent-visibility (resources/app/out, resources/app/product.json, scripts/superagent). Retain release tag v1.0.21; record the local source commit in product metadata to invalidate stale localization caches. Verify installed bundle hashes after copying and record a hotfix manifest in the installation root.

Visibility source was committed in vscode 968a459b28e7b600207c0817c2871a75898c5985 and installed with verified bundle hashes. The follow-up chat-routing change also fixes view-lifecycle todo deletion and makes successful ECC preflight visible. The earlier no-implicit-start condition applied to visibility validation; the user subsequently authorized explicit chat-triggered background startup in the 2026-11-08 plan. Root artifacts are included in the final chat-routing integration commit.
