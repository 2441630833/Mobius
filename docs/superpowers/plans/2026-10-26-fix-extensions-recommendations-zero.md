# Plan: Fix Zero Recommended Extensions in Mobius (推荐扩展为0)

## Root Cause
1. **Missing Recommendation Configurations in `product.json`**:
   `vscode/product.json` (as well as `VSCode-win32-x64/resources/app/product.json` and `$LOCALAPPDATA/Programs/Mobius/resources/app/product.json`) contains zero extension recommendation entries (`extensionRecommendations`, `configBasedExtensionTips`, `exeBasedExtensionTips`, `languageExtensionTips`, `keymapExtensionTips`, `remoteExtensionTips`). In official VS Code, these configuration dictionaries define the mappings for file extensions (`.py`, `.ts`, `.cpp`, `.html`), project configurations (`pom.xml`, `.git/config`), and installed system executables (`git`, `docker`, `python`). Because Mobius's `product.json` lacked all of them, no file-based, config-based, or exe-based recommendations were ever discovered.
2. **Empty Recommendation Model & Absence of Marketplace Fallback**:
   In `vscode/src/vs/workbench/contrib/extensions/browser/extensionsViews.ts`, `getAllRecommendationsModel` (which serves the default `@recommended:all` query for the "推荐" view in the Extensions sidebar) queries:
   - Workspace recommendations (`.vscode/extensions.json`)
   - Important recommendations (config/exe/file-based)
   - File-based recommendations
   - Other recommendations
   When a user opens a workspace that has no `.vscode/extensions.json` and has not opened files that match active extension tips, `allRecommendations` is empty (`[]`). Instead of falling back to popular/curated gallery recommendations, `getAllRecommendationsModel` returns `new PagedModel([])` (0 items).
3. **UI View Behavior**:
   In `DefaultRecommendedExtensionsView.show`, when the user has at least one installed extension (`!local.some(e => !e.isBuiltin)` is false), the view does not collapse when `model.length === 0`. This leaves the "推荐" header expanded with a badge of `0` and an empty blank pane, creating a confusing user experience.

## Goal
1. Populate `vscode/product.json`, `VSCode-win32-x64/resources/app/product.json`, and `$LOCALAPPDATA/Programs/Mobius/resources/app/product.json` with the standard 66+ `extensionRecommendations`, 16 `configBasedExtensionTips`, 43 `exeBasedExtensionTips`, 15 `languageExtensionTips`, 10 `keymapExtensionTips`, and 7 `remoteExtensionTips` (including Mobius-specific development tips).
2. Update `getAllRecommendationsModel` in `vscode/src/vs/workbench/contrib/extensions/browser/extensionsViews.ts` so that when `result.length === 0` (no contextual/workspace recommendations found), it gracefully falls back to querying the top popular extensions from the marketplace gallery (excluding already-installed extensions), ensuring the "推荐" section always displays meaningful recommendations.
3. Update `DefaultRecommendedExtensionsView.show` so that if `model.length === 0` (e.g. offline and no cached/fallback recommendations), the view automatically collapses (`setExpanded(false)`) instead of remaining expanded with `0`.
4. Compile the changed VS Code client code via `scripts/compile-vscode.ps1` (or verify TypeScript errors via `npm run typecheck-client`) and sync the compiled bundle and product configuration to the installed Mobius directory.
5. Verify that `product.json` parses cleanly, `@recommended:all` returns valid recommendations, and the installed IDE is updated.

## Non-goals
- Modifying how user-installed extensions are scanned or toggled.
- Overwriting or ignoring user project-specific `.vscode/extensions.json`.

## Tasks
- [x] Task 1: Update `vscode/src/vs/workbench/contrib/extensions/browser/extensionsViews.ts` to add gallery popular fallback in `getAllRecommendationsModel` and auto-collapse in `DefaultRecommendedExtensionsView.show`.
- [x] Task 2: Inject `extensionRecommendations`, `configBasedExtensionTips`, `exeBasedExtensionTips`, `languageExtensionTips`, `keymapExtensionTips`, and `remoteExtensionTips` into `vscode/product.json`.
- [x] Task 3: Compile VS Code client (`npm run compile-client` or gulp) and verify TypeScript / lint gates.
- [x] Task 4: Sync updated `product.json` and compiled output to `VSCode-win32-x64` and `$LOCALAPPDATA/Programs/Mobius`.
- [x] Task 5: Verify runtime integrity and test that recommended extensions query returns non-zero results.

## Acceptance Criteria
1. `vscode/product.json` contains full tip dictionaries (`extensionRecommendations`, `exeBasedExtensionTips`, `configBasedExtensionTips`, etc.).
2. `getAllRecommendationsModel` falls back to gallery popular extensions when contextual recommendations are empty, preventing "推荐 0".
3. TypeScript / client compile succeeds with zero errors.
4. Installed Mobius runtime at `$LOCALAPPDATA/Programs/Mobius` is updated and synchronized.
