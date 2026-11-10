# Remove Selection Notice Disclaimer

## Root Cause

In `vscode/src/vs/workbench/contrib/continue/browser/continueSelectionEvidence.ts`, the function `formatRoutingCandidates` displayed an explanatory sentence after the routing candidates:
`Automatic routing — suggested skills: {0}; ECC agent profiles: {1}. The agent decides whether to use these suggestions; actual selections are shown as execution proceeds.`

In Mobius, this sentence is unnecessary and clutters the chat interface. Removing it makes the candidate banner concise and directly informative:
`Automatic routing — suggested skills: {0}; ECC agent profiles: {1}.`

## Goal

1. Remove the sentence "The agent decides whether to use these suggestions; actual selections are shown as execution proceeds." from `continueSelectionEvidence.ts`.
2. Update unit test in `continueSelectionEvidence.test.ts`.
3. Rebundle VS Code desktop minified bundle (`vscode/build/next/index.ts bundle --minify --nls --mangle-privates --out out-vscode-min --target desktop`).
4. Hotpatch the installed Mobius application at `C:\Users\mi\AppData\Local\Programs\Mobius`:
   - Backup current bundle and metadata to `C:\Users\mi\AppData\Local\MobiusHotfixBackups\20261110-remove-selection-notice`.
   - Copy updated files (`workbench.desktop.main.js`, `sessions.desktop.main.js`, maps, and `nls.*` files) to `resources\app\out`.
   - Update `product.json` with new commit hash and recomputed SHA256 checksums.
   - Clear stale CLP cache in `AppData\Roaming\Mobius\clp` to guarantee clean NLS cache regeneration.
   - Update `.mobius-chat-routing-hotfix.json` record.
5. Commit the vscode submodule change and document in root repository.

## Non-Goals

- Do not alter automatic routing recommendation algorithm or tool execution evidence logic.
- Do not commit unrelated dirty vendor submodules.

## Tasks

- [x] Task 1: Update `continueSelectionEvidence.ts` to remove the redundant disclaimer.
- [x] Task 2: Update `continueSelectionEvidence.test.ts` assertions.
- [x] Task 3: Verify client typecheck (`npm --prefix vscode run typecheck-client`).
- [x] Task 4: Rebuild minified NLS desktop bundle into `vscode/out-vscode-min`.
- [x] Task 5: Commit changes to `vscode` repository.
- [x] Task 6: Apply hotpatch to installed Mobius directory and purge stale CLP cache.
- [x] Task 7: Commit updated `vscode` submodule pointer and plan doc in root Mobius repository.

## Acceptance Criteria

1. The message `Automatic routing — suggested skills: ...; ECC agent profiles: ...` does not contain `The agent decides whether to use these suggestions; actual selections are shown as execution proceeds.`.
2. Typecheck passes without errors.
3. Installed Mobius runtime has the new bundle deployed and `product.json` checksums matching.
4. Language pack cache under `clp` is cleared.
