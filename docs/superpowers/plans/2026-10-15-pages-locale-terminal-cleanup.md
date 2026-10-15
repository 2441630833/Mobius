# Plan: Improve locale contrast and remove terminal window titles

## Root cause
- The language switch uses pale text and a translucent white background over a bright moving video, making both language labels hard to read.
- The install card renders a terminal icon and simulated shell/window title for every operating system. The user requested removing these labels shown in the supplied screenshots.
- The landing page is maintained in the repository root, `web/`, and `docs/`; GitHub Pages deploys the root files through `.github/workflows/deploy-pages.yml`.

## Goal
Make the language switch consistently readable and remove the terminal icon/window title for macOS, Windows, and Linux while preserving the install commands, copying, and OS tabs.

## Non-goals
- Do not change the installation scripts, video, site navigation, or download behavior.
- Preserve pre-existing unrelated changes in `hermes-agent`, `vendor/fastmcp`, `vendor/litex`, `vendor/litex-boards`, `vendor/mcp-python-sdk`, and `vendor/openFPGALoader`, and the untracked `docs/superpowers/plans/2026-10-15-ppt-master-runtime-path.md`.
- Preserve existing submodule revisions, including the uninitialized `godogen` submodule.
- Preserve concurrent PPT/OCR work appearing during this task: `.github/agents/PPT.agent.md`, `vscode` working-tree changes, `scripts/patch-ide-ppt-master.ps1`, and `docs/superpowers/plans/2026-10-15-fix-ocr-toolbar-overlap.md`.

## Tasks
1. [x] Update `styles.css`, `web/styles.css`, and `docs/styles.css` with an opaque dark language button, bold white text, distinct hover/focus styles, and remove unused terminal-title/icon selectors, including the mobile rule.
2. [x] Update `index.html`, `web/index.html`, and `docs/index.html` to remove the terminal icon/title block and update CSS/JS cache versions. Update `main.js`, `web/main.js`, and `docs/main.js` to remove terminal title data and DOM updates.
3. [x] Verify JavaScript syntax, CSS/HTML parsing, both locales, all OS tabs and copying, desktop/mobile layout, and browser runtime errors. Run `npm run check` and `npm run compile` as required by AGENTS.md; the IDE compile may exceed five minutes and must be allowed to finish. The `get_errors` and `manage_todo_list` tools are unavailable in this session; use command diagnostics, browser checks, and this checklist as their available equivalents.
4. [x] Review the diff, stage only the nine landing-page files and this plan, commit once with `fix: improve locale switch contrast and remove terminal titles`, and verify only the pre-declared unrelated changes remain. Publish the main commit and a static-only deployment to `gh-pages` (the configured Pages source), preserving its separate history and assets, then verify the live site.

## Verification results
- `node --check` passed for all three `main.js` files.
- The installed VS Code CSS language service reported zero errors and zero diagnostics for all three stylesheets. HTML parsing verified unique IDs, all three OS tabs, intact language/copy controls, removed title markup, and updated CSS/JS cache versions.
- Browser verification passed at the default desktop size and at 390 x 844: Chinese/English switching, mobile menu switching, all three OS install commands, clipboard copy, and the visible keyboard-focus ring. The native clipboard exactly matched the selected Windows command. All three page copies loaded with white text on the opaque dark button and no terminal title. Browser error logs were empty.
- Language button contrast is 14.71:1 normally and 10.44:1 on hover.
- `npm run check` passed. `npm run compile` failed in legacy Windows PowerShell because `Get-FileHash` was unavailable. Retrying the same script with `pwsh -NoProfile -File scripts/compile-vscode.ps1` entered the actual IDE compile and passed Monaco typechecking, then failed with `EPERM` while removing the unrelated `vscode/extensions/media-preview/tsconfig.tsbuildinfo` cache file. This is an existing/concurrent IDE build limitation; no IDE source files are part of this change.
- The GitHub Pages settings API confirms `build_type: legacy`, source `gh-pages:/`, and custom domain `mobiusai.si`. Deploy only `index.html`, `main.js`, and `styles.css` from the main commit onto the existing `gh-pages` tree; do not force-push or publish the full repository tree there.

## Acceptance criteria
- Both language labels appear in bold white text on an opaque dark background with at least 4.5:1 contrast; hover and keyboard focus stay legible.
- No terminal icon/window title or unused terminal-title code remains in any landing page copy.
- macOS, Windows, Linux command switching, clipboard copying, and language switching still work.
- The browser reports no new errors from the changed local HTML, CSS, or JavaScript, and the available verification commands have been run with their results recorded.
- All four checklist tasks are complete and the intended files are committed without incorporating unrelated changes.
