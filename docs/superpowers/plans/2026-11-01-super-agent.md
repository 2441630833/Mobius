# Continuous proactive coding with Super Agent

## Root cause
Mobius waits for chat requests. The user needs a continuously running project agent that infers valuable work from project materials, runs multiple workers, and consumes minimal human attention.

## Goal
Pin dsh-superagent-prototype and directly reuse its Engine and Repositories contract in an independent Node 24 background service. Discover tasks under written project rules, run bounded parallel workers in Git worktrees, verify and retain reviewable commits, persist state, and expose Mobius start/pause/stop/status commands. Reuse the active Mobius model configuration as requested by the user.

## Non-goals
No GitHub/Feishu watchers, external messages, automatic merges or deployment. Worktrees isolate Git changes, not OS permissions. Closing Mobius leaves the explicitly started service running; machine shutdown/sleep stops execution. No automatic replay of uncertain side effects after a crash. The earlier chat-harness edits were fully reverted because they did not implement the clarified goal.

Preserve unrelated changes in hermes-agent, vendor/fastmcp, vendor/litex, vendor/litex-boards, vendor/mcp-python-sdk, vendor/openFPGALoader and the uninitialized godogen submodule.

## Tasks
1. [x] Pull root main with git pull --ff-only (already up to date), inspect Mobius and upstream philosophy/core.
2. [x] Add dsh-superagent-prototype at 6337fc823ce20251c8de8085948165c81aaa701e; reuse its unmodified MIT core with a scoped TypeScript loader.
3. [x] Implement durable SQLite repositories, rule-gated discovery, daily budgets, bounded concurrency, Git worktrees, independent verification, quiet attention records and process control in scripts/superagent.
4. [x] Add workbench actions loading the existing active Mobius model profile and start the detached runtime through a terminal without writing credentials to task state.
5. [x] Add regression tests, packaging on Windows/Linux/macOS, and usage/limitations documentation.
6. [x] Run node tests, vscode npm run typecheck-client, root npm run check and npm run compile; review and commit vscode and root independently.

## Acceptance criteria
Discovery runs without chat input. At least two workers can run concurrently in distinct worktrees. Cancellation and failed verification never count as ready. Policy, budgets, deduplication and records survive restart; interrupted executions are retained for inspection. The local panel exposes actionable results and branches without periodic notifications. No API key appears in policy or task records. All existing unrelated changes remain untouched.

## Validation
Run npm run superagent:test at E:/MobiusCode/Mobius, npm run typecheck-client at E:/MobiusCode/Mobius/vscode, and root npm run check / npm run compile (may exceed five minutes). Node syntax checks replace unavailable get_errors; this checklist replaces unavailable manage_todo_list. Use real temporary Git repositories and a mock model HTTP endpoint to verify background process lifecycle without paid model calls. Planned commit: feat: add continuous proactive background coding with Super Agent.

## Results
All 16 Node tests passed, including real concurrent Git worktrees, durable recovery, changed-policy rejection, packaged-core loading, detached start/stop, and a mock OpenAI endpoint driving discovery plus a real file-tool write and verified commit. VS Code client typecheck passed. Root prerequisite checks passed. The root npm compile wrapper initially failed because Windows PowerShell could not load Get-FileHash; running the same scripts/compile-vscode.ps1 with pwsh -NoProfile completed the full client and built-in extension compilation with zero errors. PowerShell packaging syntax and Git Bash syntax checks passed. Workbench commit: e5ae31dceaf.

No live paid-model execution or 24-hour soak test was performed, and no persistent background service was activated on the user's repository. Linux/macOS packaging hooks were syntax-checked; those platforms were not run locally. Existing unrelated submodule deviations remain preserved.
