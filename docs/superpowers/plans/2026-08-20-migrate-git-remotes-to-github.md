# Migrate git remotes from Gitee/GitCode to GitHub

## Root cause

Local remotes and `.gitmodules` still point at Gitee / GitCode forks. The canonical remotes are now GitHub.

## Goal

- Point the three Mobius remotes at GitHub.
- Stop using Gitee and GitCode as `origin`.
- Pull the latest code from those GitHub remotes.

## Non-goals

- Do not change `upstream` remotes (`microsoft/vscode`, `continuedev/continue`).
- The extra vscode `gitlab` mirror remote (`code.demxs.com`) has been removed; the project no longer uses that mirror.
- Do not rewrite hermes-agent to a new Mobius fork; `.gitmodules` already uses `NousResearch/hermes-agent` on GitHub. Only replace its leftover Gitee `origin`.

## Mapping

| Repo | New origin |
|------|------------|
| Root (Mobius) | https://github.com/2441630833/Mobius.git |
| vscode submodule | https://github.com/2441630833/Mobius-vscode.git |
| continue submodule | https://github.com/2441630833/Mobius-continue.git |
| hermes-agent submodule | https://github.com/NousResearch/hermes-agent.git (already in `.gitmodules`) |

## Tasks

1. [x] Update `.gitmodules` vscode/continue URLs (GitHub `main` already had them).
2. [x] `git remote set-url origin` on root + three submodules; `git submodule sync`.
3. [x] `REBASE.md` on GitHub `main` already uses GitHub URLs.
4. [x] Checked out `main` @ `69747b91`; updated submodules to pinned SHAs via gh-proxy (github.com:443 was reset).
5. [x] Verify remotes and `git status`.

## Acceptance criteria

- No `gitee.com` / `gitcode.com` URLs remain in `.gitmodules`, `REBASE.md`, or `origin` remotes.
- Root and submodules have fetched/pulled from the new GitHub remotes without error (or a hard blocker is recorded).
