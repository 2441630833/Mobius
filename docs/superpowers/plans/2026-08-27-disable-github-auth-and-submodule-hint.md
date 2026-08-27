# Disable GitHub Authentication Toast and Git Submodule Hint

## Root cause

1. `vscode.github-authentication` is a built-in with `main: ./out/extension.js`. Source-run Mobius does not compile that extension. Contributing an `authentication` provider still triggers `onAuthenticationRequest:github`, so activation fails and `$onExtensionActivationError` shows an error toast (dev builds always toast).
2. The Git extension warns when `git.detectSubmodules` is true and `repository.submodules.length > git.detectSubmodulesLimit` (default 10). This repo has 14 vendor submodules.

## Goal

- Never load or activate `vscode.github-authentication` in Mobius.
- Never show the "N submodules which won't be opened automatically" hint.

## Non-goals

- Compiling `github-authentication` `out/extension.js`.
- Auto-opening the 14 vendor submodules.
- Disabling the Git extension itself.

## Tasks

1. [x] Add `skipBuiltinExtensions: ["vscode.github-authentication"]` to `vscode/product.json` and merge that list into `skipBuiltinExtensions` in the environment service (with the existing `VSCODE_SKIP_BUILTIN_EXTENSIONS` env var).
2. [x] Append the same ID in `scripts/launch-ide.ps1`.
3. [x] Swallow remaining activation-error toasts for this extension ID.
4. [x] Default `git.detectSubmodules` to false and `github.gitAuthentication` to false in Mobius configuration defaults; add workspace `.vscode/settings.json`.

## Acceptance criteria

- Opening the Mobius repo no longer shows the GitHub authentication activation error.
- Opening the Mobius repo no longer shows the 14-submodules Git hint.
- Git still works; submodules can be opened by opening a file inside them.
