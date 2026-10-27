# Force UTF-8 Encoding in Mobius to Prevent Terminal & Git Mojibake

## Root cause

On Windows (Chinese locale), PowerShell and CMD default to Code Page 936 (GBK) for console I/O and process pipe encoding, and Windows PowerShell 5.1's `Get-Content` defaults to ANSI (CP936) rather than UTF-8. When tool calls execute commands that output UTF-8 text (such as comments in `.gitignore` or Chinese log output) or when Git emits text without explicit UTF-8 output encoding, stdout bytes are misdecoded as CP936, yielding corrupt mojibake (e.g. `推送` becoming `鎺ㄩ€`). Furthermore, AI agents sometimes fall back to shell commands (`type`, `Get-Content` without `-Encoding utf8`) rather than using structured `read_file` tools.

## Goal

Enforce UTF-8 encoding across all layers of Mobius:
1. **Terminal / Execution Layer**:
   - In `continue/core/tools/implementations/runTerminalCommand.ts`: Prepend `[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false); $OutputEncoding = [System.Text.UTF8Encoding]::new($false);` to all Windows PowerShell commands, and set `PYTHONIOENCODING=utf-8`, `PYTHONUTF8=1`, `LESSCHARSET=utf-8` in process environment.
   - In `vscode/src/vs/workbench/contrib/terminal/common/scripts/shellIntegration.ps1`: Force UTF-8 `[Console]::OutputEncoding` and `$OutputEncoding` and `chcp 65001` at shell initialization.
   - In `vscode/src/vs/workbench/contrib/continue/browser/continue.contribution.ts`: Add `PYTHONIOENCODING`, `PYTHONUTF8`, `LESSCHARSET` to `terminal.integrated.env.windows`.
   - In `vscode/src/vs/workbench/contrib/terminalContrib/chatAgentTools/browser/toolTerminalCreator.ts`: Inject UTF-8 environment variables into agent tool terminals.
2. **AI Tooling & Agent Guidance**:
   - In `continue/core/tools/definitions/runTerminalCommand.ts` and `vscode/.../runInTerminalTool.ts`: Add explicit guidelines for Windows PowerShell to prioritize `read_file` over `type`/`cat`, and require `-Encoding utf8` if `Get-Content` is used.
   - In `continue/core/llm/defaultSystemMessages.ts`: Guide Agent mode to use `read_file` and `-Encoding utf8`.
   - In `AGENTS.md`: Update section 2.4 with explicit file-reading guidelines.
3. **Git Configuration**:
   - In `.gitconfig`: Add `[i18n] commitencoding = utf-8` and `logoutputencoding = utf-8`.
   - In `scripts/setup.ps1` & `scripts/install-git-hooks.ps1`: Configure global and local `core.quotepath false`, `i18n.logoutputencoding utf-8`, and `i18n.commitencoding utf-8`.

## Non-goals

- Do not alter unrelated third-party submodules (litex, openFPGALoader, hermes-agent).
- Do not affect non-Windows POSIX platforms where UTF-8 is already the default system encoding.

## Tasks

1. [x] Update `.gitconfig`, `scripts/setup.ps1`, `scripts/install-git-hooks.ps1` to configure Git UTF-8 (`core.quotepath false`, `i18n.logoutputencoding utf-8`, `i18n.commitencoding utf-8`).
2. [x] Update `AGENTS.md` (section 2.4) with file-reading encoding rules.
3. [x] Update `continue`:
   - `core/tools/implementations/runTerminalCommand.ts`
   - `core/tools/definitions/runTerminalCommand.ts`
   - `core/llm/defaultSystemMessages.ts`
4. [x] Update `vscode`:
   - `src/vs/workbench/contrib/terminal/common/scripts/shellIntegration.ps1` (and `out/.../shellIntegration.ps1`)
   - `src/vs/workbench/contrib/continue/browser/continue.contribution.ts`
   - `src/vs/workbench/contrib/terminalContrib/chatAgentTools/browser/toolTerminalCreator.ts`
   - `src/vs/workbench/contrib/terminalContrib/chatAgentTools/browser/tools/runInTerminalTool.ts`
5. [x] Verification & Build:
   - Run typecheck in `vscode` (`npm run typecheck-client`) and `continue` (`npm run tsc:check` and `npm run esbuild`).
   - Test Git & PowerShell UTF-8 behavior.
6. [x] Git commit and status check.

## Acceptance criteria

1. Terminal commands run through Continue and VS Code integrated terminal / agent tools execute under UTF-8 console and output encoding.
2. Git configuration in `.gitconfig`, `setup.ps1`, and `install-git-hooks.ps1` enforces `core.quotepath false`, `i18n.logoutputencoding utf-8`, and `i18n.commitencoding utf-8`.
3. Agent system prompts and tool descriptions in Continue and VS Code instruct LLMs to prioritize `read_file` and use `-Encoding utf8` when calling `Get-Content`.
4. VS Code and Continue build/typecheck without regression errors.
