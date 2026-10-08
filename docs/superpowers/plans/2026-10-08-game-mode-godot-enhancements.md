# Game Mode Godot Integration & Workflow Enhancement

## Root cause

1. **Failure to consistently use Godot**:
   - Auto mode intent detection (`hasGameDevIntent`) was overly narrow (`/game[\s-]?dev|godot|\bmini[\s-]?game\b|小游戏|做个游戏|game mode|star catcher/i`), missing common requests like "写个2D游戏", "做一个3d游戏", "制作一款射击游戏", "贪吃蛇", etc.
   - LLMs by default often scaffold HTML5 canvas/WebGL/Vite web server games instead of Godot unless strictly forbidden. Existing workflow hints (e.g. Godogen) mentioned alternative engines (Babylon.js, Bevy) or web paths, creating confusion.
2. **Aggressive window popup during coding**:
   - `bootstrapGameModeGodotLivePreview` eagerly launched the Godot editor and game window immediately at chat start.
   - `executeGodotTool` automatically popped up the editor during `godot_import`, `godot_project_init`, and `godot_test`.
   - The user requested: During the coding process, Godot must NOT be opened by default; only open Godot when the user's prompt explicitly requests it. When finished, open the Godot playable preview.
3. **Missing GitHub search + gh-proxy workflow**:
   - Game mode had no instruction to search GitHub for mature open-source games before building from scratch, nor did it specify the `https://gh-proxy.org/` mirror fallback for blocked GitHub connections.
4. **Godot console executable pairing**:
   - `Godot_v4.4.1-stable_win64_console.exe` expected `Godot_v4.4.1-stable_win64.exe` alongside it, which was missing because setup moved the file to `godot.exe`.

## Goal

- Ensure 100% of 2D and 3D games in Game mode use Godot (Godot 4 GDScript). Strictly forbid web servers or browser/canvas games.
- In Game mode, do not start from scratch immediately: first search GitHub for mature open-source game projects, and pull/clone them. If foreign GitHub is unreachable, use `https://gh-proxy.org/`.
- During coding, default to NOT opening Godot windows (remain headless). Only open the editor if user prompt asks for it.
- Upon completion, launch the preview game in Godot (`godot_play`), not a web server.
- Fix Godot engine binary pairing and verify Godot integration end-to-end.

## Non-goals

- Modifying non-game modes (Chip / Agent).
- Replacing Godot with any other engine.

## Tasks

1. [x] Check Godot installation and pair `Godot_v4.4.1-stable_win64.exe` with `godot.exe`.
2. [x] Update `.github/agents/Game.agent.md` with strict Godot requirement, GitHub search + gh-proxy mirror source, no web servers, and headless-during-coding policy.
3. [x] Update `.continue/rules/game-dev-mode.md` with the same rules.
4. [x] Update `vscode/src/vs/workbench/contrib/continue/browser/continueGodotTools.ts` (expand `hasGameDevIntent`, update `GAME_EXECUTE_HINT`, suppress auto-open during coding).
5. [x] Update `vscode/src/vs/workbench/contrib/continue/browser/continueChatAgent.ts` (check explicit user prompt before opening Godot editor; launch playable preview on completion).
6. [x] Update `vscode/src/vs/workbench/contrib/continue/browser/continueGodogenWorkflow.ts` and `continueGameStudioWorkflow.ts` to enforce Godot-only rule and forbid web services.
7. [x] Update `scripts/patch-ide-godot.ps1` to keep console binary pairing.
8. [x] Compile/lint modified workbench files and verify Godot MCP tools.

## Acceptance criteria

- Godot executable and console binary test clean (`4.4.1.stable.official.49a5bc7b6`).
- `node scripts/godot-mcp-server.js --self-test` passes.
- Game mode prompts and hints explicitly forbid web servers and mandate Godot for all 2D/3D games.
- GitHub search + gh-proxy (`https://gh-proxy.org/`) clone workflow is documented and instructed in Game mode.
- Godot editor is not opened by default during code development, only on explicit user prompt. Playable preview game opens upon completion.
- TypeScript compilation of modified files succeeds with zero errors.
