# Fix Search Web / Fetch Webpage Tool Failures

## Root cause

After `npm run compile`, Search Web still failed because Continue never loaded config:

```
Failed to parse config: Map keys must be unique
  useResponsesApi: false
  useResponsesApi: false
```

`physicalAiModelEnv.ts` `ensureUseResponsesApiOnNamedBlock` re-emitted every existing `useResponsesApi` line on each sync, so `~/.continue/config.yaml` accumulated duplicates. YAML parse is fatal → **Config not loaded** → `handleToolCall` fails for `search_web` / all Continue tools.

Earlier hardening (Copilot skip, clean fetch, arg aliases) remains valid but was not the post-compile blocker.

## Goal

- Config YAML stays valid across repeated model-env syncs.
- Search Web / Fetch Webpage work once Continue config loads.

## Non-goals

- Restoring Continue Hub trial proxy search.
- Changing LLM provider endpoints.

## Tasks

1. [x] Skip `copilot_fetchWebPage` / clean fetch / arg aliases (prior turn).
2. [x] Fix `ensureUseResponsesApiOnNamedBlock` to skip duplicate keys once `hasFlag` is set.
3. [x] Add `dedupeUseResponsesApiKeys` and run it in `prepareContinueConfigYaml` + `applyUseResponsesApi`.
4. [x] Repair user `~/.continue/config.yaml` (collapse duplicates).
5. [x] Vitest for dedupe + re-save idempotence; rebuild Continue extension.
6. [x] Mark plan tasks done; emit `TASK_COMPLETE`.

## Acceptance criteria

1. No duplicate `useResponsesApi` after repeated `saveModelEnv`.
2. `~/.continue/config.yaml` parses (single `useResponsesApi` under volcano).
3. After IDE reload (Continue extension rebuild, not just `npm run compile`), Search Web succeeds or shows a clear Bing/HTTP error.
