# MiniLM worker_threads + pause index + skill first-token

## Root cause

1. `TransformersJsEmbeddingsProvider.embed()` runs ONNX MiniLM on the Continue **extension-host event loop**. `setImmediate` only yields between groups; a group still blocks JS (and N agents + indexing share that thread). Cursor keeps embeddings in a separate process/thread.
2. Continue already has `index/setPaused` + `CodebaseIndexer.pauseToken`, but Agents never sets it. Indexing keeps feeding MiniLM while agents stream.
3. Every Agent turn `await buildContinueSkillsContext()` before the first LLM call: `findAgentSkills` + read up to ~22 SKILL.md files + hash fusion (~300–480ms). That delay is on the first-token path.

## Goal

- MiniLM inference in a dedicated `worker_threads` Worker (one ONNX session). Extension host only queues jobs.
- Interactive query embeds still jump the queue; background index jobs pause while any Agent session is running (`indexingPaused` refcount).
- Skill routing uses a **warm in-memory cache**. The first API call does not wait on disk. Cold cache → send without skill bodies rather than stall; warmup fills the next turn.
- Multi-session: pause refcount; MiniLM worker stays single-threaded so N sessions cannot stack ONNX on the UI/extension thread.

## Non-goals

- Moving MiniLM to a separate OS process (Worker is the Cursor-like step that fits this repo).
- Changing skill ranking quality (same lexical + hash fusion, just cached).
- Committing unrelated dirty files.

## Tasks

1. [x] Worker bundle + TransformersJsEmbeddingsProvider posts chunks to worker_threads; fallback in-process if Worker fails; `setTransformersJsBackgroundPaused`.
2. [x] `continue.setIndexingPaused` → `core.invoke("index/setPaused")` + MiniLM background pause; Agents refcount acquire/release.
3. [x] Skill index warmup at ContinueChatAgent ctor; hot path `buildContinueSkillsContextFast` (no disk); invoke does not await full routing.
4. [x] esbuild worker into `extensions/vscode/out/transformersJsEmbedWorker.js`; compile vscode; run targeted tests.

## Acceptance criteria

- Agent invoke does not `await` skill file reads before `_streamOnce`.
- `continue.setIndexingPaused(true)` sets `CodebaseIndexer.paused` and stops MiniLM **low** queue.
- MiniLM worker file exists next to `extension.js`; `NODE_ENV=test` still returns mock vectors (no Worker).
- vscode compile 0 errors; existing skill/message tests still pass.
