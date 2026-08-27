# Stop automatic Git Credential Manager prompts

## Root cause

Mobius launches with `--agents`. In the Agents window, `git.autofetch` defaults to `true`, so the Git extension periodically fetches remotes. System Git uses `credential.helper=manager` (Git Credential Manager). GCM shows a GUI whenever HTTPS credentials are missing. The user's global gitconfig has `credential.https://gitee.com.provider=generic`, so Gitee requests become the username/password dialog.

## Goal

Do not auto-trigger Git Credential Manager. Periodic fetch and unattended git must fail closed instead of popping a login UI.

## Non-goals

- Removing GCM from the machine
- Changing the user's Gitee account or stored credentials
- Blocking intentional `git push`/`git pull` once credentials are already stored

## Tasks

1. [x] Default `git.autofetch` false in the Git extension Agents-window schema, Mobius configuration defaults, and workspace settings.
2. [x] Default `git.terminalAuthentication` false so integrated terminals do not inject askpass.
3. [x] Set `GIT_TERMINAL_PROMPT=0` and `GCM_INTERACTIVE=never` on Git extension spawns and in `launch-ide.ps1`.

## Acceptance criteria

- Opening Mobius on this repo does not show the Git Credential Manager dialog by itself.
- Git status / SCM still work locally.
- Stored credentials can still be used; missing credentials fail instead of prompting.
