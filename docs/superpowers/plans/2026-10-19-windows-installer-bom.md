# Windows installer HTTP BOM fix

## Root cause
Windows PowerShell Invoke-RestMethod preserves UTF-8 BOM before CmdletBinding,
causing Invoke-Expression parsing failure. Reproduced against published raw URL.

## Goal
Restore existing GitHub Pages install command on PowerShell 5.1 and 7.

## Non-goals
Preserve initial README.md, hermes-agent, vendor submodules, vscode and untracked
2026-10-15-agent-terminal-cursor.md plan changes. No real installation.

## Tasks
1. [x] Remove BOM; add HTTP byte decoding regression coverage. Use ASCII output
   messages so saved Windows PowerShell 5.1 scripts also remain parseable.
2. [x] Run parser checks and mocked installer tests on both hosts; commit fix.

## Acceptance criteria
HTTP decoded source parses and all mocked installer scenarios pass.

## Verification
get_errors and manage_todo_list unavailable: use PowerShell Language.Parser and
this checklist. IDE compilation does not cover this standalone installer.

Results: all 15 scenarios passed on PowerShell 7.6.5 and Windows PowerShell
5.1.26100.9711. Both script parsers passed; saved installer command syntax passed.
Commit message: fix(installer): remove BOM breaking Windows one-line install.
