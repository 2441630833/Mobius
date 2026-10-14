# Automatically Disable Search Web Tool Calling When Offline

## Root cause

In Mobius, when a user asks an external knowledge or latest-information question, `hasWebSearchIntent` activates, forcing `search_web` tool calling on turn 0, injecting `<web-search-override>` instructions, and adding `search_web` to the agent tool superset.
Currently, this happens unconditionally, even when the user has no internet connection (offline). As a result:
1. `search_web` is offered to and forced on the LLM during offline usage.
2. The agent attempts to query Bing over the network, resulting in failed network requests, hanging timeouts, or error cascades.
3. The model is commanded not to answer from memory even when offline and unable to search.

Leftover git status from prior session:
- Root submodules (`hermes-agent`, `vendor/*`) have pointer differences; keep them untouched.
- `vscode/product.json` and `vscode/extensions/vscode-language-pack-zh-hans/` exist from earlier localization; keep them untouched.

## Goal

- Detect network status (online vs offline) in Mobius workbench.
- Automatically disable `search_web` tool calling when offline.
- Suppress web search intent (`webSearchIntent`), forceTool, `<web-search-override>`, and search-forcing nudges when offline so that no network requests are attempted during user requests.
- Filter out `search_web` from agent tools when offline.
- Guard tool execution so that even if `search_web` is somehow invoked while offline, it immediately aborts without attempting any network connection.
- Enable `search_web` and web search intent exclusively when an online connection is present.

## Non-goals

- Altering local tools (`read_file`, `write_file`, `grep_search`, `list_dir`, etc.).
- Changing third-party Bing SERP scraping logic when online.
- Disabling local LLM providers that do not require external network.

## Tasks

1. [x] Create `continueNetworkStatus.ts` in `vscode/src/vs/workbench/contrib/continue/browser/` to monitor network online/offline state using `navigator.onLine`, event listeners (`online`/`offline`), probe reachability caching, and test override helpers.
2. [x] Update `continueSkillsContext.ts`: gate `hasWebSearchIntent` with network status check so web search intent is never triggered when offline.
3. [x] Update `continueAgentToolsBridge.ts`: exclude `search_web` from `loadContinueAgentTools` when offline, and guard `invokeContinueBuiltInTool` against offline execution.
4. [x] Update `continueCopilotToolsBridge.ts`: exclude `search_web` from `loadAgentToolSuperset` when offline.
5. [x] Update `continueChatAgent.ts`: check network status at request start; suppress `webSearchIntent`, `forceTool`, search nudges, and `<web-search-override>` when offline; ensure `agentTools` excludes `search_web` when offline; block `search_web` in `_executeToolCall` when offline.
6. [x] Update `continue/extensions/vscode/src/agent/continueAgentTools.ts` and `continue/core/tools/implementations/searchWeb.ts` to guard against offline execution.
7. [x] Add comprehensive automated tests in `vscode/src/vs/workbench/contrib/continue/test/browser/continueNetworkStatus.test.ts` and `continue/core/tools/implementations/searchWeb.vitest.ts`.
8. [x] Run build and test verification (`npm run compile` / tests).
9. [x] Mark plan tasks done and verify against all acceptance criteria.

## Acceptance criteria

1. When offline (`isNetworkOnline() === false`):
   - `hasWebSearchIntent` returns `false`.
   - `search_web` is excluded from tool schemas passed to the LLM.
   - `forceTool` is not set to `search_web`.
   - Tool execution for `search_web` immediately returns offline error without making network calls.
2. When online (`isNetworkOnline() === true`):
   - `hasWebSearchIntent` detects web search keywords as before.
   - `search_web` is present in tool schemas.
   - Normal online behavior is preserved.
3. Automated unit tests pass with zero errors.
4. `npm run compile` completes with zero errors.
