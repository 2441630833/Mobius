---
alwaysApply: true
description: Run terminal in chat panel; retry until success
---

# Terminal agent (inline in chat)

In **Agent mode**, run commands with the terminal tool — they execute in the chat panel (no copy-paste for the user).

## Windows PowerShell

- **Do not use `&&`** on Windows PowerShell 5.x (common in VS Code). It throws: `The token '&&' is not a valid statement separator`.
- Chain commands with **`;`**:
  - Good: `Set-Location "d:\physical_AI_IDE"; npm run web`
  - Bad: `cd "d:\physical_AI_IDE" && npm run web`
- Prefer `Set-Location` when changing directory before another command.

## Inline terminal in chat panel

- Commands run **inside the Continue chat panel** — look for the **Terminal · PowerShell · In chat panel** block.
- Output streams live in that block (not the external VS Code terminal tab).
- Status line shows: Queued → Running in chat panel → Completed / failed.

1. Run the command with `run_terminal_command`.
2. Read terminal output in the chat panel.
3. If it fails: fix the command line **or** edit the codebase (scripts, config, source).
4. Re-run until the task succeeds — do not ask the user to run commands manually.

## Examples

```powershell
Set-Location "d:\physical_AI_IDE"; npm run web
Set-Location "d:\physical_AI_IDE"; npm run sync:config
```
