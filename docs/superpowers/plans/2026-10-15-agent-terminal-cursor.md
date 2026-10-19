# Agent view terminal cursor alignment

## Root cause

The reported Windows PowerShell terminal in the Agent view displays its initial cursor inside the prompt. Investigate the Agents Window terminal layout, xterm initialization and shell cursor synchronization before choosing the smallest correction. The screenshot's Output / Terminal tabs belong to the workbench panel.

## Goal

Keep the initial terminal cursor aligned with the shell prompt, including opening the terminal from the Agent view and resizing the panel.

## Non-goals

Do not change shell profiles, terminal history or unrelated work in progress. Preserve all initial modified/untracked items: `.github/agents/PPT.agent.md`, `scripts/install-win.ps1`, `scripts/patch-ide-ppt-master.ps1`, `scripts/test-install-win.ps1`, the OCR/PPT/installer plan documents, and existing changes in `vscode` (PPT agent/runtime/build files, `continueChatAgent.ts`, `continueChat.css`, PPT tests and resources). Preserve the existing hermes-agent/vendor submodule revisions and uninitialized godogen submodule; these are unrelated to the fix.

## Tasks

1. [ ] Trace the Agents Window terminal opening and reproduce the cursor mismatch with existing terminal tests or a focused runtime harness.
2. [ ] Correct the responsible initialization/layout behavior and add a focused regression test when needed.
3. [ ] Run TypeScript diagnostics (`npm run typecheck-client` in `E:/MobiusCode/Mobius/vscode`), compile via the root `npm run compile` entrypoint, and run the relevant terminal regression tests. Full compilation may exceed five minutes; run it rather than skipping it.
4. [ ] Review and commit only the intended terminal files in the vscode submodule, then commit this completed plan and the intentional vscode pointer in the root repository. Verify only predeclared unrelated changes remain.

## Acceptance criteria

- Terminal input cursor matches the shell prompt after the Agent view opens the terminal.
- Terminal sizing and subsequent input remain consistent after panel layout changes.
- Changed code has no new TypeScript errors and focused regression verification passes.
- All task items are complete and intentional changes are committed.

## Tool availability

This session does not expose `manage_todo_list` or `get_errors`. This plan is the persistent task checklist; the repository TypeScript checker and compiler provide the required diagnostics.

## Intended commit messages

- vscode: `fix: align the initial agent view terminal cursor`
- root: `fix: update agent view terminal cursor initialization`
