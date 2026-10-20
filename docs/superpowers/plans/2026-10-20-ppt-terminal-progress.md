# PPT preparation and terminal recovery

## Root cause
Native sync terminals waiting for input remain associated with the session and can consume subsequent commands as input. PPT preparation repeatedly rediscovers workflow/script paths despite a known installation root. The confusing hamster text is an upstream random loading-message easter egg.

## Goal
Detach input-waiting terminals from command reuse, provide concrete PPT workflow paths and bounded preparation guidance, and use meaningful loading messages.

## Non-goals
Do not claim ARM runtime verification or publish a release. Do not change existing unrelated submodule revisions.

## Tasks
1. [x] Fix terminal input-needed reuse and add regression coverage.
2. [x] Supply PPT resource paths and bounded preparation instructions; remove random joke messages from both thinking and progress displays.
3. [x] Typecheck VS Code, run focused tests, and commit submodule and root changes.

## Acceptance criteria
Input-waiting terminal stays accessible by ID but is not reused by new commands. PPT hint names installed workflow and scripts and directs partial reads and error recovery. Default status messages contain no easter eggs. Focused checks pass.

## Verification
Use npm run typecheck-client per vscode/AGENTS.md and its copilot instructions, then focused unit tests. get_errors/manage_todo_list are unavailable; use the compiler and this checklist. Preserve preexisting hermes-agent and vendor/{fastmcp,litex,litex-boards,mcp-python-sdk,openFPGALoader} changes.

## Results
Typecheck passed. Transpiled changed TypeScript into ignored out/ for Electron validation. Focused Electron suites passed 62 tests (PPT mode, thinking status, input-needed notification and terminal detachment). Node PPT suite passed 6 tests. Expanded Electron run: 247 passed, 105 pending, 5 unrelated sandbox/session approval failures. Recompiled the terminal implementation from HEAD and reran the approval subset: the same 5 failures reproduced (14 passed), then restored the fixed compiled output. No source changes were made for those baseline failures. No live model/Ubuntu ARM PPT export was tested; preparation guidance reduces repeated discovery but cannot guarantee model adherence.
