# Fix Linux Web Search, Agent Network Privileges & Web Search Button

## Root cause
1. **Linux Network Detection Bug**:
   In Chromium / Electron on Linux (without NetworkManager running or in headless/container/systemd-networkd environments), `navigator.onLine` evaluates to `false` and fires the `window 'offline'` event.
   `continueNetworkStatus.ts` checked `navigator.onLine === false` synchronously and in `checkNetworkOnline()`, returning `false` immediately without probing.
   `continue/core/tools/implementations/searchWeb.ts` also checked `if (navigator.onLine === false) return Network offline`.
   As a result, on Linux Mobius was permanently locked in offline mode, causing web search to be reported as unavailable even though the host machine was connected to the network.
2. **Web Search Button & Setting Inversion**:
   When users saw web search was unavailable, clicking the "Web Search On" button toggled `continue.webSearch.enabled` to `false`.
   `ToggleWebSearchAction` updated `ConfigurationTarget.USER`, which could fail on Linux or be overridden by workspace configuration.
   When `continue.webSearch.enabled` became `false`, `continueChatAgent.ts` injected `<web-search-disabled>` and blocked `search_web` with `Web Search is disabled by the user. Answer without web search.`.
   Furthermore, the button styling `.checked` lacked clear visual feedback (transparent background), making its state ambiguous.
3. **Agent Sandbox & Network Privileges**:
   Terminal commands and agent tools defaulted to restricted sandboxing and domain filtering. Mobius agent requires full privileges and unrestricted network access across all platforms.

## Goal
1. Fix network connectivity detection in `vscode/src/vs/workbench/contrib/continue/browser/continueNetworkStatus.ts` so `navigator.onLine === false` does not falsely block network on Linux or Electron; probe reachability with adequate timeouts.
2. Remove the premature `navigator.onLine === false` gate in `continue/core/tools/implementations/searchWeb.ts`.
3. In `continueAgentToolsBridge.ts` and `continueChatAgent.ts`, re-verify network connectivity dynamically before rejecting `search_web`.
4. Fix `ToggleWebSearchAction` and `WebSearchButtonActionViewItem` in `vscode/src/vs/workbench/contrib/continue/browser/continueWebSearchAction.ts` so clicking reliably toggles the active configuration target, updates UI immediately, and has clear visual active styling in `continueChat.css`.
5. Grant all privileges and network access to Mobius agent in `continue.contribution.ts` default configuration overrides (`chat.agent.sandbox.enabled: 'off'`, `allowUnsandboxedCommands: true`, `retryWithAllowNetworkRequests: true`, `allowAutoApprove: true`, `chat.agent.networkFilter: false`, `continue.webSearch.enabled: true`).
6. Unconditionally register `continue.webSearch.enabled` in `ConfigurationRegistry`.
7. Verify all automated tests pass.
8. Commit changes and push to cloud remotes (`Mobius`, `Mobius-vscode`, `Mobius-continue`).

## Non-goals
- Changing Bing SERP parsing logic when online.
- Altering unrelated local tools (`read_file`, `write_file`, etc.).

## Tasks
1. [x] Create plan document.
2. [x] Update `continueNetworkStatus.ts` to prevent false offline reporting on Linux/Electron, enhance probing, and handle offline events safely.
3. [x] Update `continue/core/tools/implementations/searchWeb.ts` to remove blind `navigator.onLine === false` rejection.
4. [x] Update `continueWebSearchAction.ts` and `continueChat.css` for reliable toggle handling and clear button active state styling.
5. [x] Update `continueAgentToolsBridge.ts` and `continueChatAgent.ts` to avoid prematurely blocking web search and ensure search_web can execute.
6. [x] Update `continue.contribution.ts` to grant all privileges and network access by default, and register `continue.webSearch.enabled` configuration globally.
7. [x] Update tests in `continueNetworkStatus.test.ts` and `continueWebSearchAction.test.ts` to cover the new behavior.
8. [x] Run tests and compile verification.
9. [x] Commit in submodules (`continue`, `vscode`) and root repo with clean UTF-8 commit messages, push to cloud remotes, and emit TASK_COMPLETE.

## Acceptance criteria
1. `isNetworkOnline()` and `checkNetworkOnline()` default to online and do not falsely report offline on Linux when `navigator.onLine === false`.
2. `searchWebImpl` allows searches when network is connected.
3. Web Search button accurately toggles configuration, provides immediate UI update, and has clear active visual indicator.
4. Mobius agent defaults to unsandboxed mode with all privileges and unrestricted network access.
5. Automated tests pass and compilation succeeds.
6. Changes are pushed to cloud remotes.
