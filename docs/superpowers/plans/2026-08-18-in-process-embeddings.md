# In-process embeddings (stop Ollama nomic contention)

## Root cause

Mobius ships bundled Ollama (`127.0.0.1:25137`) and forces **every** embed call through `nomic-embed-text`:

1. `@codebase` indexing / retrieval (Continue core, `config.yaml` `local-embed`)
2. Skill auto-routing on **every agent turn** (`continueSkillEmbeddings.ts` HTTP to Ollama, concurrency 4)

Ollama is a single llama.cpp process. Concurrent agents + indexing flood `/api/embed` (already noted in `Ollama.ts`: parallel batches can hang `/api/chat`). Even when chat is a cloud API, each turn still waits on skill-embed HTTP, and llama.cpp steals CPU from the workbench. More sessions → more embed traffic → slower agent start and token paint.

Cursor-style fix: in-process MiniLM (Continue already vendors `transformers.js` + `all-MiniLM-L6-v2` ONNX). Skill routing in the workbench browser cannot load onnxruntime-node; use a local hashing embedder so it never calls Ollama.

## Goal

- Default embed role = `transformers.js` / `all-MiniLM-L6-v2` (in-process ONNX).
- Startup sync migrates existing `local-embed` Ollama blocks (strip `apiBase`).
- Skill routing embeds in-process (no HTTP, no Ollama).
- Serialize MiniLM inference so N agents do not stack ONNX on the extension host.
- Ollama remains for GLM-OCR only.

## Non-goals

- Removing bundled Ollama or GLM-OCR.
- Changing cloud chat providers.
- Rebuilding historical LanceDB nomic indexes in-place (new `embeddingId` triggers a fresh index).
- Committing unrelated dirty files (untracked skills, vscode submodule pointer).

## Tasks

1. [x] Switch `config/continue-config.yaml` embed model to `transformers.js`.
2. [x] Change `physicalAiModelEnv.ts` `OLLAMA_EMBED` / `ensureOllamaEmbedBlock` to write transformers.js and strip `apiBase`.
3. [x] Rewrite `continueSkillEmbeddings.ts` to in-process hashed embeddings; drop `IRequestService`.
4. [x] Add a process-wide embed mutex in `TransformersJsEmbeddingsProvider`.
5. [x] Update Mobius docs that claim nomic is the default embedder.
6. [x] Extend `physicalAiModelEnv.vitest.ts` to assert `provider: transformers.js`.

## Acceptance criteria

- Default / repaired `config.yaml` has `provider: transformers.js` and no Ollama embed `apiBase`.
- Skill routing does not call `127.0.0.1:25137` for embeddings.
- MiniLM `embed()` calls are serialized.
- Existing vitest for config sync still passes; new assertions cover transformers.js.
