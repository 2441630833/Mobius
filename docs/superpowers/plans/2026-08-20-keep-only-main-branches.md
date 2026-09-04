# Keep only local `main` branches

## Goal

Match remotes: only `main` locally in the superproject and every submodule.

## Non-goals

- Do not remove `upstream` remotes (`microsoft/vscode`, `continuedev/continue`).
- Do not rewrite hermes-agent to latest NousResearch `main` unless the superproject pin says so.

## Tasks

1. [x] Fetch origin `main` for root, vscode, continue (via gh-proxy if needed).
2. [x] Fast-forward/reset local `main` to `origin/main` in the superproject; `git submodule update`.
3. [x] In each submodule, `checkout -B main` at the recorded / origin `main` commit; delete `master`, `mobius-custom`, `tim`, `fresh-start`.
4. [x] Prune stale `origin/*` remote-tracking refs; `.gitmodules` `branch = main` (from origin/main).
