# Chat session bloat, multi-session leak, and headroom integration

## Root causes
1. **Session log bloat.** Sessions persist as an append-only mutation log
   (`chatSessions/<id>.jsonl`, `ObjectMutationLog`). Every tool result (terminal
   output, file reads, diffs, thinking) was stored verbatim forever, and the log was
   compacted only by entry count (1024), never by size. One long session reached
   ~20 MB; opening it parsed and replayed the whole log on the renderer main thread.
2. **Multi-session CPU/heap growth.** Every cached `LocalSession` (cap 100) subscribed
   to the git repository on its own. Each save ran one `diffBetweenWithStats2('HEAD')`
   per cached session and read every untracked file in full, once per session, to
   count lines. Cost grew with the number of sessions ever opened, idle ones included.
3. **Agent context loss.** `pruneHistoryForContext` kept only the first 12 KB of a tool
   result (the error at the end of a build log was cut off) and replaced older results
   over 2 KB with a bare stub.

Not a cause: the installed build `f03aa29` already had the 8-bucket input history and
the LRU session cache; `b8f939a` only coalesces diff passes.

## Fixes (vscode submodule)
- `chat/common/headroom/headroomCompressor.ts`: in-process port of headroom's
  `LogCompressor` defaults + `DenseLineElider`, error keywords from headroom-core's
  `KeywordRegistry::default_set()` (`headroom/` submodule, Apache-2.0).
- `chatSessionPersistCompression.ts` + `chatSessionOperationLog.ts`: tool, thinking,
  progress and elicitation parts are compressed in the persisted copy only (> 4 KB,
  16 KB cap). The live model is untouched.
- `objectMutationLog.ts`: compact after 4 MB appended; logs > 2 MB compact on next save.
- `sharedRepositoryChanges.ts` + `localChatSessionsProvider.ts`: one ref-counted git
  change tracker per repository; untracked files > 1 MB are never read, at most 200 counted.
- `continueChatAgent.ts`: tool outputs headroom-compressed to 12 KB (old ones to 2 KB)
  instead of head truncation / stubs.

## Hotfix for already-installed builds
`scripts/patch-ide-session-headroom.py` (+ `scripts/headroom-persist.js`, tests:
`node scripts/headroom-persist.test.js`) patches the installed
`workbench.desktop.main.js` with fix 1 only. Revert: `--revert`. Not needed once the
IDE is rebuilt from this commit.
