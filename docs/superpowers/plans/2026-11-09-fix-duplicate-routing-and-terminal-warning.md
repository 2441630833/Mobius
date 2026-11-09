# Fix duplicate Automatic routing and noisy terminal checkpoint warning

## Root cause
1. In `vscode/src/vs/workbench/contrib/continue/browser/continueChatAgent.ts`, commit `37d16c72c80` moved ECC preflight before Super Agent routing and updated `formatEccPreflight` to include `\n\n` + `formatRoutingCandidates(result.matchedSkills, result.matchedAgents)`. When `eccPreflightResult.ok` is true, line 781 renders the preflight message (including routing candidates). In foreground chat execution, line 1148 also called `formatRoutingCandidates(routedSkillNames, eccPreflightResult?.matchedAgents ?? [])` unconditionally. Because `routedSkillNames` and `eccPreflightResult.matchedSkills` match in normal requests, the exact same `Automatic routing — suggested skills: ...; ECC agent profiles: ...` message is displayed twice.
2. In `vscode/src/vs/workbench/contrib/continue/browser/continueChatAgent.ts`, line 1949-1952 emitted a chat `warning` progress item:
   `Terminal changes and external effects are not automatically protected by chat checkpoints.`
   whenever any terminal command tool was called (`run_in_terminal`, `terminal`, `run_command`, etc.). In VS Code chat, this renders as an alarming yellow warning box in the assistant message, making users believe normal terminal commands are failing or triggering errors.

## Goal
1. Suppress duplicate `formatRoutingCandidates` emission in foreground execution when `eccPreflightResult` already displayed routing candidates.
2. Remove the disruptive user-facing chat warning for terminal tools, replacing it with internal debug logging (`_logService.debug`).
3. Compile, verify, package the updated bundle into `C:/Users/mi/AppData/Local/Programs/Mobius/resources/app/out`, and update the hotfix manifest.

## Non-goals
- Do not disable ECC preflight or routing recommendations.
- Do not disable chat checkpoints for actual file edits (`_writeFileWithCheckpoint`).
- Do not modify unrelated dirty submodule pointers or untracked files.

## Tasks
1. [x] Check typecheck-client baseline and inspect `continueChatAgent.ts`.
2. [x] In `vscode/src/vs/workbench/contrib/continue/browser/continueChatAgent.ts`:
   - Set `let eccCandidatesShown = false;` when `formatEccPreflight` successfully outputs routing candidates.
   - At line 1148, only emit `formatRoutingCandidates` if `!eccCandidatesShown`.
   - At line 1949, replace `progress([{ kind: 'warning', content: new MarkdownString(...) }])` with `this._logService.debug('[Continue] Terminal tool invoked; external effects not tracked by checkpoints:', call.name)`.
3. [x] Run unit tests and typecheck-client in `vscode`.
4. [x] Build/minify workbench bundle (`npm run gulp minify-vscode` or incremental compile).
5. [x] Apply the updated files to `C:/Users/mi/AppData/Local/Programs/Mobius/resources/app/out` with backup, update the hotfix manifest `.mobius-chat-routing-hotfix.json`.
6. [x] Verify installed bundle files and syntax.
7. [x] Commit changes in `vscode` and the root repo following AGENTS.md rules.

## Acceptance criteria
- Foreground chat does not emit duplicate `Automatic routing` messages.
- Terminal commands execute without emitting the `Terminal changes and external effects are not automatically protected by chat checkpoints` warning in chat.
- All client typechecks and tests pass.
- Clean git commit with clean UTF-8 message.

## Execution and Verification Notes
- Client typecheck (`npm run typecheck-client`) passed with zero errors.
- Super Agent runtime tests (24 tests) passed.
- Esbuild bundle generated `out-vscode-min` in 131s without errors.
- Installed bundles syntax validated with `node --check`.
- Checksums in `product.json` updated with sha256 digests.
- Backup saved at `C:/Users/mi/AppData/Local/MobiusHotfixBackups/20261109-duplicate-routing`.
