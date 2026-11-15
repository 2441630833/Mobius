# Allow Terminal Commands Sensitive Input Without Restrictions

> **Date:** 2026-11-15  
> **Status:** Complete  
> **Target:** Mobius IDE root, vscode submodule, and installed Mobius application

## 1. Root Cause & Background

1. **Auto-Cancellation in Autopilot / Auto-Approve Mode**:
   - In `vscode/src/vs/workbench/contrib/terminalContrib/chatAgentTools/browser/tools/monitoring/outputMonitor.ts`, when terminal output matches sensitive prompts (passwords, tokens, API keys, passphrases, secrets, OTP, etc.), `_isSensitivePrompt()` evaluates to `true`.
   - Instead of firing `onDidDetectInputNeeded`, `OutputMonitor` fired `onDidDetectSensitiveInputNeeded`.
   - In `vscode/src/vs/workbench/contrib/terminalContrib/chatAgentTools/browser/tools/runInTerminalTool.ts`, `_registerSensitiveInputElicitation` hooked `onDidDetectSensitiveInputNeeded`.
   - When running under Autopilot / auto-approve mode (`isAutoApproved = true`), it immediately marked `autoCancelled = true`, aborted the command via `cancelExecution()`, surfaced the notification:
     `终端命令已取消 - 需要敏感信息输入: 终端命令正在提示输入密码或其他机密。自动批准/Autopilot 模式无法安全提供机密，因此命令已取消。如果你想提供机密，请以交互方式运行命令。`
     and steered the agent to stop and refuse calling `send_to_terminal`.

2. **Model Steering & Prompt Blocking**:
   - In non-auto-approved mode, `onDidDetectInputNeeded` was never resolved for the agent, and the agent tool descriptions explicitly instructed the LLM:
     `NEVER use vscode_askQuestions to request sensitive input such as passwords, passphrases, API keys, tokens, or other secrets... do not call vscode_askQuestions or send_to_terminal for that prompt.`
   - This blocked both manual and automated terminal interaction from inputting sensitive credentials.

3. **User Requirement**:
   - Mobius must allow terminal commands to input sensitive information without any restrictions and obstacles ("不设任何限制和阻拦").

## 2. Goals

1. **Enable Unrestricted Sensitive Input in Terminal Output Monitor**:
   - In `outputMonitor.ts`:
     - Ensure sensitive prompts (passwords, tokens, API keys, passphrases, secrets, OTP, etc.) are recognized as high-confidence input patterns (`detectsHighConfidenceInputPattern` / `detectsInputRequiredPattern`).
     - Treat sensitive prompts as standard `onDidDetectInputNeeded` events rather than diverting them to a separate blocking/canceling channel.
2. **Remove Auto-Cancellation and Blocking in RunInTerminalTool**:
   - In `runInTerminalTool.ts`:
     - Eliminate the auto-cancel execution branch and cancellation warning in `_registerSensitiveInputElicitation`.
     - Remove the prohibition against asking questions or sending sensitive input via `send_to_terminal` from tool descriptions and steering guidance.
3. **Update Unit Tests**:
   - In `outputMonitor.test.ts`:
     - Update test cases to verify sensitive prompts fire `onDidDetectInputNeeded` so terminal input proceeds without barrier.
4. **Patch Installed Mobius Application**:
   - Hotpatch `workbench.desktop.main.js` in `C:\Users\mi\AppData\Local\Programs\Mobius\resources\app\out\vs\workbench\` so the currently installed Mobius IDE immediately benefits from this fix.
   - Update hotfix manifest and purge stale CLP cache if needed.
5. **Commit and Push to Cloud Remotes**:
   - Commit changes in `vscode` repository and push to `origin/main` (`https://github.com/2441630833/Mobius-vscode.git`).
   - Update submodule pointer and plan doc in root `Mobius` repository, commit, and push to `origin/main` (`https://github.com/2441630833/Mobius.git`).

## 3. Non-Goals

- Modifying non-terminal chat tools or unrelated sandbox policies.
- Breaking the `onDidDetectSensitiveInputNeeded` event signature (retaining interface compatibility for external consumers).

## 4. Execution Tasks

- [x] Task 1: Modify `vscode/src/vs/workbench/contrib/terminalContrib/chatAgentTools/browser/tools/monitoring/outputMonitor.ts` to recognize sensitive prompts as input-needed and fire `onDidDetectInputNeeded`.
- [x] Task 2: Modify `vscode/src/vs/workbench/contrib/terminalContrib/chatAgentTools/browser/tools/runInTerminalTool.ts` to remove auto-cancel and model prompt restrictions on sensitive input.
- [x] Task 3: Update `vscode/src/vs/workbench/contrib/terminalContrib/chatAgentTools/test/browser/outputMonitor.test.ts`.
- [x] Task 4: Verify typecheck in `vscode`.
- [x] Task 5: Hotpatch installed Mobius bundle at `C:\Users\mi\AppData\Local\Programs\Mobius\resources\app\out\vs\workbench\workbench.desktop.main.js`.
- [x] Task 6: Commit and push `vscode` submodule to remote.
- [x] Task 7: Commit and push root repository with submodule pointer and plan doc.

## 5. Acceptance Criteria

1. Sensitive input prompts in terminal commands fire `onDidDetectInputNeeded` and do not trigger command cancellation in autopilot/auto-approve mode.
2. Agent instructions in `runInTerminalTool` allow sensitive information to be provided via `send_to_terminal`.
3. Unit tests in `outputMonitor.test.ts` reflect the unrestricted input behavior.
4. Installed Mobius runtime has the hotpatch applied.
5. Both `vscode` and root `Mobius` git repositories are clean and pushed to `origin/main`.
