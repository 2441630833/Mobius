# Fix run_in_terminal stale echo and spurious ^C cancellation

## Root cause

1. **Spurious ETX (`\x03`) sent by `runCommand` in `terminalInstance.ts`**:
   `runCommand` checked `if (shouldExecute && (!commandDetection || commandDetection.promptInputModel.value.length > 0)) { await this.sendText('\x03', false); await timeout(100); }`. On Windows with PowerShell, `WindowsPtyHeuristics` initializes `commandStartX` to 0 while waiting for ConPTY adjustments. Consequently, `promptInputModel.value` captures the entire prompt string (`PS C:\...> `), so `value.length > 0` is permanently true. Furthermore, if `!commandDetection`, it sent `\x03` blindly to an idle shell.
   When `\x03` is sent to PowerShell at an idle prompt, PowerShell cancels the line, emits `^C`, and fires an end-command OSC sequence (`633;D;130`).

2. **Premature resolution in `RichExecuteStrategy`**:
   `RichExecuteStrategy` raced execution completion against `this._commandDetection.onCommandFinished`. It attempted to filter out previously running commands with `staleMarker = this._commandDetection.executingCommandObject?.marker`. But when the shell was idle at a prompt at strategy entry, `executingCommandObject` was `undefined`, leaving `onCommandFinishedFiltered` completely unfiltered. When `runCommand` sent `\x03`, the resulting `^C` cancellation event resolved the promise immediately with exit code 130 and old echo, before the actual command even started. The actual command was then typed 100ms later in the background, out-of-band, repeating on every subsequent turn.

3. **`toolTerminal.receivedUserInput` tracking raw PTY output instead of user input**:
   In `runInTerminalTool.ts` (`_registerInputListener`), the listener subscribed to `toolTerminal.instance.onData` (data coming from the PTY/shell) instead of `toolTerminal.instance.onDidInputData` (data sent to the PTY). As soon as the shell produced any output, `receivedUserInput` was permanently set to `true`, causing `BasicExecuteStrategy` to attempt spurious prompt clearing.

4. **Empty output falling back to scraping old terminal buffer**:
   In both `RichExecuteStrategy` and `BasicExecuteStrategy`, when a command produced 0 lines of output (e.g. quiet commands or scripts), `finishedCommand.getOutput()` returned `undefined` because `startLine === endLine`. The strategies then fell into `if (output === undefined)`, scraping `xterm.getContentsAsText(startMarker, endMarker)`. If `startMarker` was invalidated or shifted, it scraped old commands and echo from the scrollback instead of returning empty output.

5. **`findCommandEcho` matching the oldest command rather than the latest**:
   In `strategyHelpers.ts`, `findCommandEcho` called `strippedOutput.indexOf(trimmedCommand)` (first occurrence). If a command was executed multiple times, it matched the initial execution's echo and returned all stale output since that first run. It should use `lastIndexOf` to match the latest invocation's echo.

6. **State wait bug in `runCommand`**:
   In `terminalInstance.ts`, `if (!commandDetection || commandDetection.promptInputModel.state !== PromptInputState.Input)` only listened to `onDidAddCommandDetectionCapability`. If `commandDetection` was already present, that event never fired again, hanging for the full 5000ms timeout.

## Goal

- Ensure `run_in_terminal` commands on Windows PowerShell (and all platforms) execute cleanly without sending spurious `\x03` (`^C`).
- Ensure `RichExecuteStrategy` does not resolve on stale or cancelled command events and only captures output and exit code of the requested command.
- Ensure commands producing no output return an empty string rather than scraping old buffer history.
- Ensure `findCommandEcho` matches the most recent invocation of the command (`lastIndexOf`).
- Ensure user input tracking listens to `onDidInputData`, not `onData`.
- Eliminate 5-second hang in `runCommand` when `commandDetection` is already attached.

## Non-goals

- Do not alter external shell profiles or unrelated submodules.
- Preserve existing vendor submodule states and git status.

## Tasks

1. [x] Update `terminalInstance.ts` (`runCommand`):
   - Add `skipInterrupt?: boolean` parameter to `runCommand` (and interface in `terminal.ts`).
   - Only send `\x03` when `!skipInterrupt`, `shouldExecute`, and `commandDetection` exists and is confirmed to have non-prompt user input (never send blindly when `!commandDetection`).
   - Fix prompt input state waiting so if `commandDetection` is already defined, it listens directly to `onDidStartInput`.
2. [x] Update `richExecuteStrategy.ts`:
   - Pass `skipInterrupt: true` to `runCommand`.
   - In `onCommandFinishedFiltered`, filter out events that do not match `commandId` (when `commandId` is specified and `e.id` is present).
   - If `finishedCommand` completed with `executedMarker && endMarker` and `getOutput()` is `undefined`, treat as clean empty output (`output = ''`) rather than falling back to marker scrape.
3. [x] Update `basicExecuteStrategy.ts`:
   - Treat `finishedCommand.executedMarker && finishedCommand.endMarker` with `getOutput() === undefined` as clean empty output (`output = ''`).
4. [x] Update `strategyHelpers.ts`:
   - In `findCommandEcho`, use `strippedOutput.lastIndexOf(trimmedCommand)` so repeated commands match the latest invocation.
5. [x] Update `runInTerminalTool.ts`:
   - In `_registerInputListener`, listen to `toolTerminal.instance.onDidInputData` instead of `toolTerminal.instance.onData`.
6. [x] Validation & Diagnostics:
   - Run `npm run typecheck-client` in `vscode` (Passed! 0 errors).
   - Add regression test in `strategyHelpers.test.ts`.
   - Commit changes in `vscode` (`7138ddbc84d`) and update the submodule reference.

## Acceptance criteria

1. Calling `run_in_terminal` on Windows PowerShell does not send `^C` or return stale echo.
2. Consecutive invocations of the same command return the fresh output of each turn, not the prior turn's output.
3. Quiet commands (producing 0 output) return clean empty output (`""`), not previous terminal history.
4. `npm run typecheck-client` passes with zero errors.
5. Focused unit tests pass.
