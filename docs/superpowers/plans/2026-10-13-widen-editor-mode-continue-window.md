# Plan: Widen Mobius Editor Mode Continue Window Default Width

## Root Cause
In Mobius, when running in "editor mode" (standard VS Code workbench), the Continue AI chat interface is hosted in the auxiliary bar (Secondary Side Bar, view container `workbench.panel.chat`).
The default auxiliary bar width in `vscode/src/vs/workbench/browser/layout.ts` and `vscode/src/vs/workbench/browser/parts/auxiliarybar/auxiliaryBarPart.ts` is hard-coded to `300px`:
- `AUXILIARYBAR_SIZE: new InitializationStateKey<number>('auxiliaryBar.size', StorageScope.PROFILE, StorageTarget.MACHINE, 300)`
- `LayoutStateKeys.AUXILIARYBAR_SIZE.defaultValue = auxiliaryBarForceMaximized ? Math.max(300, mainContainerDimension.width / 2) : Math.min(300, mainContainerDimension.width / 4);`
- `applyOverrides`: `this.setInitializationValue(LayoutStateKeys.AUXILIARYBAR_SIZE, Math.min(300, configuration.mainContainerDimension.width / 4));`
- `preferredWidth`: `return Math.max(width, 300);`

In Continue's GUI (`continue/gui/src/pages/config/index.tsx`), the Settings/Config page checks the container width against Tailwind's `sm` breakpoint (`330px`). If width < 330px:
- A blocking warning is displayed:
  "Screen width too small: To view settings, please expand the sidebar by dragging the left/right border"
- The settings content is hidden (`sm:block`, `sm:hidden`).

Because the default auxiliary bar width is 300px (less than 330px), whenever a user opens Settings in Continue in editor mode, they are greeted by this error warning instead of their settings, misleading users to believe there is a bug. Furthermore, 300px is too narrow for comfortable AI chat interactions, code blocks, diffs, and tool execution displays.

## Goal
1. Increase the default width of the auxiliary bar (Continue window in editor mode) from 300px to 450px across workbench layout initialization, dynamic container sizing, and preferred width.
2. In `continue/gui/src/pages/config/index.tsx`, adjust the screen width threshold from `sm` (330px) to `xs` (250px) so that even if a user resizes the sidebar below 330px (e.g. down to 260px), settings remain viewable and usable rather than showing a blocking error.
3. Rebuild Continue GUI and sync to `continue/extensions/vscode/gui`.
4. Recompile VS Code and verify with diagnostics.

## Non-goals
- Modifying Sessions workbench layout policy (Sessions workbench already allocates 480-800+ px to the primary chat column).
- Modifying unrelated submodules or unstaged files (`hermes-agent`, `vendor/*`, `docs/index.html`, etc.).

## Tasks
1. [x] Update `vscode/src/vs/workbench/browser/layout.ts` default auxiliary bar width to 450px.
2. [x] Update `vscode/src/vs/workbench/browser/parts/auxiliarybar/auxiliaryBarPart.ts` preferred width to 450px.
3. [x] Update `continue/gui/src/pages/config/index.tsx` to lower small screen alert threshold from `sm` to `xs`.
4. [x] Build Continue GUI and sync to `continue/extensions/vscode/gui`.
5. [x] Compile VS Code client and extensions.
6. [x] Verify git status and commit changes with encoding safety.

## Acceptance Criteria
- Default auxiliary bar width in editor mode is 450px.
- Snapping / preferred width returns 450px for the auxiliary bar.
- Continue settings page opens without "Screen width too small" warning on default layout.
- If sidebar is resized between 250px and 330px, settings remain viewable.
- Clean compilation without TypeScript errors.
