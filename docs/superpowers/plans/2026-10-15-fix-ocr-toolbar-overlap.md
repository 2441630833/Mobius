# Fix OCR toolbar overlap

## Root cause

The Local OCR action renders an icon and the `OCR` / `OCR Off` label on an
element with the `codicon` class. The shared action-bar CSS fixes its content
width to 16px, so the text extends beyond its measured toolbar slot and overlaps
Configure Tools. The custom OCR CSS does not override that width and only targets
the input toolbar, although the action is also registered in the execute toolbar.

## Goal

Give the OCR action its full intrinsic width in both chat toolbars and preserve
the gap and independent click targets next to Configure Tools.

## Non-goals

No OCR behavior changes. Preserve all existing unrelated changes: root website
files (`index.html`, `main.js`, `styles.css`, and their `docs/` and `web/` copies),
`.github/agents/PPT.agent.md`, the pre-existing locale and PPT runtime plan files,
and all existing submodule deviations. In `vscode`, preserve the PPT agent files,
build/gulpfile.vscode.ts, build/lib/compilation.ts, build/next/index.ts,
continueChatAgent.ts, continuePptMode.ts, build/lib/mobiusPptMaster.ts,
resources/ppt-master/, and continuePptMode.test.ts. Do not reset existing advanced
submodule pointers or initialize unrelated godogen. Concurrent unrelated work
also created `docs/superpowers/plans/2026-10-15-windows-installer-completion.md`
and `scripts/patch-ide-ppt-master.ps1`, and modified `scripts/install-win.ps1`
and created `scripts/test-install-win.ps1`; preserve these without staging them.

## Tasks

1. [x] Inspect OCR rendering and the shared action-bar sizing rules.
2. [x] Update `vscode/src/vs/workbench/contrib/continue/browser/media/continueChat.css`
   to size the OCR label by content, prevent wrapping/shrinking, and cover both
   `.chat-input-toolbar` and `.chat-execute-toolbar`.
3. [x] Validate with `npm run typecheck-client` and targeted `npm run stylelint --
   src/vs/workbench/contrib/continue/browser/media/continueChat.css` in `vscode`;
   run root `npm run check` and `npm run compile:vscode` (may exceed five minutes).
   Use browser layout checks with actual action-bar/chat/OCR styles for on/off
   states, toolbar variants, zoom, and narrow containers. The session exposes no
   `get_errors` or `manage_todo_list` tool; compiler/linter diagnostics and this
   checklist serve as the available equivalents.
4. [x] Commit only the intended CSS change in `vscode`, then the submodule pointer
   and this completed plan in the root repository. Use ASCII commit messages:
   `fix: prevent OCR toolbar label from overlapping tool configuration` and
   `fix: update chat OCR toolbar layout`. Confirm the staged sets and final status.

## Acceptance criteria

- OCR and OCR Off remain inside their button bounds and do not overlap Configure
  Tools in input and execute toolbars, including constrained width and zoom.
- OCR toggle behavior and existing unrelated changes are preserved.
- Applicable checks pass, or external blockers are recorded accurately.
- Only the declared unrelated work remains uncommitted.

## Verification results

- `npm run typecheck-client`: passed with zero diagnostics.
- Targeted CSS stylelint: passed; five advisory suggestions concern existing
  font, spacing, radius, and weight literals, with no lint errors.
- `npm run check`: passed all build prerequisites.
- Browser layout verification with the actual action-bar, toolbar, chat, OCR,
  and Codicon styles: all 36 fixed scenarios passed. Covered both toolbars,
  `OCR` and `OCR Off`, widths 110/180/360px, and zoom 100%/150%/200%.
  All 36 original scenarios reproduced text overflow. Fixed buttons contain
  their text, retain a 4px gap at 100% zoom, and have independent hit targets.
  Inspected the rendered screenshot. Temporary harness/results are outside the
  repository in the Windows temporary directory.
- The root compile command initially failed before compiling because Windows
  PowerShell could not load `Get-FileHash`. Retried the same build script with
  `pwsh -NoProfile -File scripts/compile-vscode.ps1`. All extension compilation,
  extension media, generated names, and the core typecheck completed without
  errors. Core emission then failed with ENOENT for
  `out/vs/base/common/observableInternal/base.js`. A separate `gulp compile`
  process started at 16:21 while this build was running, and the output directory
  was missing when checked. Avoid disturbing that unrelated build.
- Retried the same `compileTask('src', isolatedOutput, false)` implementation
  from `build/lib/compilation.ts` with an independent Windows temporary output
  directory. This includes the complete client emit pipeline and typecheck and
  avoids competing over `vscode/out`. The verification runner is also in the
  temporary directory. Passed: the full client typecheck and compilation both
  completed with zero errors, all 10,820 output files were written, and the task
  exited successfully. Confirmed the emitted OCR CSS exactly matches the source.
- CSS fix committed in `vscode` as `34f4b20e19c` with only the intended stylesheet.
  The root commit records that pointer and this plan, preserving unrelated work.
- Cleanup of the temporary output and verification files was rejected by the
  automatic policy review (`blocked by policy`), including a narrower attempt
  limited to the four named temporary files. Retain these outside the repository
  under the Windows temporary directory; do not bypass the rejection. No
  verification files were created inside the repository.
