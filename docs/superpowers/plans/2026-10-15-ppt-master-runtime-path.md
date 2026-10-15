# Resolve PPT Master from the Mobius installation

## Root cause

PPT mode hard-codes `.agents/skills/ppt-master/` relative to the user's workspace in `vscode/src/vs/workbench/contrib/continue/browser/continuePptMode.ts` and three PPT agent definitions. The skill exists in the Mobius source checkout, but a newly opened presentation workspace does not contain it. The runtime must resolve and ship the skill independently of the user's workspace.

## Goal

Provide PPT mode with a verified absolute skill directory and entry file, include the skill in development and packaged Mobius runtimes, and prevent the model from guessing workspace-relative skill paths or silently replacing the workflow after a missing-path error.

## Non-goals

Do not change presentation generation workflows or install Python packages into the user's environment. Preserve the pre-existing submodule changes in `hermes-agent`, `vendor/fastmcp`, `vendor/litex`, `vendor/litex-boards`, `vendor/mcp-python-sdk`, and `vendor/openFPGALoader`; preserve the uninitialized unrelated `godogen` submodule. Do not change their pointers.

## Tasks

1. [x] Inspect PPT prompt assembly, existing bundled resource resolution, packaging, and test conventions.
2. [x] Resolve PPT Master using the existing installation resource mechanism, inject its verified absolute paths, and correct all PPT agent definitions.
3. [x] Bundle the full skill payload for development and release builds; add regression coverage using an empty presentation workspace and missing-resource cases.
4. [x] Run relevant tests, `npm run check`, and `npm run compile`; inspect diffs and commit all intended files together with message `fix: resolve bundled PPT Master outside presentation workspaces`.

## Acceptance criteria

- PPT mode locates its skill when the presentation workspace has no `.agents` directory.
- Prompts contain verified absolute paths and require reading `SKILL.md` before using its workflow.
- Missing skill resources produce an actionable diagnostic instead of invented paths.
- Development and packaged builds include the skill scripts, workflows, references, and templates.
- Regression tests and compilation pass, or genuine external blockers are recorded precisely.
- Final status contains only the pre-declared unrelated submodule changes.

## Verification notes

The session does not expose `manage_todo_list` or `get_errors` tools (checked in the tool catalog). This document is the task checklist; use actual compiler diagnostics, targeted regression tests, and `git diff --check` as the available error checks. The full compile can exceed five minutes and will be run without skipping it.

Implementation uses a pinned full skill archive in `vscode/resources/ppt-master/` (about 13,000 files before excluding caches), expanded by `vscode/build/lib/mobiusPptMaster.ts` into every relevant build output. `scripts/patch-ide-ppt-master.ps1` restores the same payload and corrects the two legacy installed bundles without interrupting running Mobius sessions. Changes inside the `vscode` submodule must be committed there first, then the intentional pointer update and root files committed together.

Concurrent unrelated work appeared after session start: `index.html`, `main.js`, `styles.css`, the corresponding three files in both `docs/` and `web/`, and `docs/superpowers/plans/2026-10-15-pages-locale-terminal-cleanup.md`. Preserve these files and exclude them from this task's staging/commit.

Additional concurrent work: `scripts/install-win.ps1`, `scripts/test-install-win.ps1`, `docs/superpowers/plans/2026-10-15-windows-installer-completion.md`, `docs/superpowers/plans/2026-10-15-fix-ocr-toolbar-overlap.md`, and `vscode/src/vs/workbench/contrib/continue/browser/media/continueChat.css`. Preserve and exclude these as well. Some concurrent website work has already been committed by its owner.

At final staging, other sessions also own `docs/superpowers/plans/2026-10-15-agent-terminal-cursor.md`, `docs/superpowers/plans/2026-10-15-mobius-editor-branding.md`, `vscode/product.json`, `vscode/src/vs/nls.ts`, `vscode/src/vs/base/test/common/nls.test.ts`, and `vscode/src/vs/workbench/browser/parts/editor/media/editorgroupview.css`. Exclude these from this task's commits; already committed changes from their owners remain part of shared repository history.

Checks so far: client typecheck passed; build typecheck passed after using its normal `pretypecheck` policy DTO generation; `npm run check` passed. Root `npm run compile` fails before compilation because the system Windows PowerShell cannot load `Get-FileHash`; rerun the same `scripts/compile-vscode.ps1` with PowerShell 7 for the complete build.

PPT regression suite: five tests passed using an isolated esbuild test bundle in the ignored `vscode/.build/ppt-master-tests/` directory. The client compile emitted with zero TypeScript errors; its resource stage initially raced the still-writing archive and failed with an incomplete gzip stream. Re-run resource staging after archive completion. The existing Gulp emit also left pre-existing base modules absent, so validate the configured modern `build/next/index.ts transpile --out out` path before using the standard test runner. The full parallel build's Markdown Math media subprocess failed transiently; direct retry passed. Parallel extension workers exhausted RAM and were stopped; run all 43 extension targets two at a time using their existing build tasks.

The completed skill archive contains 13,016 files and is 16,999,640 bytes. SHA-256: `191a1a3e5e3a106a6d24aa35a63d31179d386eb51bd78de853ecb5a5969b93ae`.

## Final verification

- Client typecheck: passed with zero errors, including the Gulp client compiler's final typecheck.
- Build tools typecheck: passed through `npm --prefix build run typecheck`.
- Prerequisites: `npm run check` passed.
- All 43 extension targets compiled successfully with concurrency limited to two.
- Complete modern client build and skill staging: `node --experimental-strip-types --max-old-space-size=4096 build/next/index.ts transpile --out out-ppt-master-verify` passed. A fresh output directory avoided the old generated output's Windows `ENOTEMPTY` cleanup failure; its verified files were copied back into `vscode/out` without deleting user files.
- Standard test runner against the complete emitted output: six checks passed (five PPT regressions plus the framework's unexpected-error check).
- The official skill integrity guard passed in both the fresh build and the installed application.
- Installed application payload exactly matches all 13,016 archive file paths. Entry point, attribution files, integrity guard, authoring script, and routing workflow bytes match the archive.
- Both installed window bundles passed `node --check`, contain absolute skill paths, and have original `.ppt-master.bak` backups.
- The actual runtime resolver successfully read the installed `SKILL.md` through a filesystem-backed file-service adapter and produced the absolute-path prompt with complete skill instructions.
- All patch whitespace and PowerShell parser/syntax checks passed.

The local installation is repaired. Reload the Mobius window to load the patched bundles. No running user session was deliberately restarted. Preserve all concurrent changes declared above; stage only this task's explicit files in each repository.
