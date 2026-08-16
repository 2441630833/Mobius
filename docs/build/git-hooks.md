# Git Hooks (`.githooks/`)

This repo uses a **shared hooks directory** (`.githooks/`) enabled via
`git config core.hooksPath .githooks`. Hooks in this directory are
**version-controlled** (unlike `.git/hooks/`, which is per-clone) and apply
to every clone that opts in.

## File layout (Windows compatibility)

Git for Windows invokes hooks through its bundled MSYS2 bash. To run
PowerShell reliably on every Windows machine (including machines that
only have Windows PowerShell 5.1, not PowerShell 7 / `pwsh`), each hook
is split into two files:

- **`commit-msg` / `pre-commit`** — POSIX shell shim (`#!/bin/sh`). The
  shim uses `cygpath -w` to convert POSIX paths (passed by git) to
  Windows paths, then `exec powershell.exe -NoProfile -NonInteractive
  -ExecutionPolicy Bypass -File ...` into the matching `.ps1` file.
- **`commit-msg.ps1` / `pre-commit.ps1`** — the real PowerShell logic.
  All non-ASCII (Chinese) phrases are built from
  `[char]0xXXXX` Unicode code points at runtime, so the source file is
  ASCII-only and is never mis-decoded by the cp936 codepage.

When adding a new hook, create **both** files: a `.ps1` with the logic
and a same-name shim (no extension) that execs into it.

## Enable hooks in a fresh clone (one-time)

```powershell
# from repo root (d:\AI\physical-ai-ide)
powershell -ExecutionPolicy Bypass -File scripts\install-git-hooks.ps1
```

Or manually:

```powershell
git config --local core.hooksPath .githooks
git config --local i18n.commitencoding utf-8
git config --local i18n.logoutputencoding utf-8
```

> The `.gitconfig` file at the repo root can be auto-included via
> `git config --local include.path ../.gitconfig`, which also sets
> `core.hooksPath`. That is the recommended approach if you want hooks to
> "just work" after a new clone.

## What the hooks enforce

### `commit-msg` — blocks half-finished commit messages

Rejects commits whose message suggests an agent bailed mid-task:
- Chinese: `请回复继续`, `请回复任意消息`, `要我继续吗`, `请继续`, `工具调用已用完`, `本轮工具调用`, `下一轮继续`
- English: `reply continue`, `please reply`, `reply any message`,
  `shall i proceed`, `please confirm`, `may i edit`, `ready to apply`,
  `tool turns left`, `out of tool`

Also blocks empty subject lines. Warns (does not block) on mojibake
`U+FFFD` replacement characters from cp936/UTF-8 mismatches.

**Bypass** (use sparingly, never by default):

```powershell
git commit --no-verify -m "..."
```

### `pre-commit` — blocks half-finished staged content

Runs on every `git commit`. Checks:
1. No empty commits (unless `GIT_ALLOW_EMPTY=1` is set in env)
2. Staged file content does **not** contain agent-stop phrases
3. Staged `.ps1` files parse without PowerShell ParseErrors
4. Staged files do not contain mojibake `U+FFFD` replacement bytes
   (`0xEF 0xBF 0xBD` at any offset)

**Bypass** (use sparingly):

```powershell
git commit --no-verify -m "..."
```

## How to test the hooks manually

```powershell
# Test commit-msg blocks a bad message
"请回复继续" | Out-File -FilePath test-msg.txt -Encoding utf8 -NoNewline
git commit --allow-empty -F test-msg.txt  # should FAIL
Remove-Item test-msg.txt

# Test commit-msg allows a clean message
git commit --allow-empty -m "chore: hook self-test"  # should PASS (then reset)
git reset --hard HEAD~1  # remove the throwaway self-test commit

# Test pre-commit blocks forbidden staged content
Set-Content -Path test-bad.txt -Value "请回复继续" -Encoding UTF8
git add test-bad.txt
git commit -m "test"  # should FAIL
git rm --cached test-bad.txt; Remove-Item test-bad.txt
```

## Adding new hooks

1. Create a file in `.githooks/` named after the hook (`pre-push`,
   `post-merge`, etc.). Make sure the first line is the shebang
   (`#!/usr/bin/env pwsh`), and `chmod +x` on POSIX (Windows does not
   require this).
2. Use `[System.Text.UTF8Encoding]::new($false)` when reading files —
   PowerShell's default is cp936 on this machine.
3. Exit `0` to allow, non-zero to block. Print clear diagnostics.
4. Add a section to this document describing the hook's purpose and any
   bypass mechanism.

## Why not husky / lefthook / pre-commit?

This workspace is a VS Code fork with heavy native build steps
(`compile:vscode-min`, inno setup, asar packing). We do not want a
JavaScript / Python hook runner as a prerequisite to commit. Pure
PowerShell hooks work on every dev machine in this repo with no extra
dependencies.
