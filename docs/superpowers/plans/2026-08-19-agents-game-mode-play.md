# Agents window Game mode + visible play

## Root cause

Agents window mode picker is Ask / Edit / Agent only. Continue GUI Game mode never appears there. `ContinueChatAgent` only injects the Godot loop when the user message matches `hasGameDevIntent`. Separately, the workbench `godot_preview` wrapper treats missing `editor` as `true`, so Agents always opens the Godot **editor** instead of running Star Catcher. `npm run godot:preview` also passes `--editor`.

## Goal

- Agents window can select **Game** (custom agent + Continue Game participant).
- Game mode always gets write tools + `godot_*` + the game-dev system prompt.
- After import/test, the agent launches a **visible running game** (`godot_play`), with autopilot so the mini-game plays itself.
- Headless `godot_play` reports `YOU WIN` so the agent can verify without a display.

## Non-goals

- New VS Code `ChatModeKind`.
- Committing `tools/godot/` binaries, `.godot/` cache, or unrelated embedding/Ollama leftovers.

## Tasks

1. [x] Add `.github/agents/Game.agent.md` so Game shows in the Agents picker.
2. [x] Register Continue `*.game` agent; treat it as Agent tools; always inject game prompt.
3. [x] Add `godot_play` (visible autoplay + headless win check); fix preview default.
4. [x] Star Catcher autopilot (`--autoplay`) toward stars; quit headless on win.
5. [x] Verify detect/import/test/headless play; compile continue workbench files.

## Acceptance criteria

- Agents picker lists Game (workspace `.github/agents/Game.agent.md`).
- `godot_preview` without `--editor` launches the game, not the editor.
- `godot_play` with autoplay prints `YOU WIN` headlessly (fail=0).
- `godot_test` still 0 failed.
- Workbench `continueGodotTools.ts` / `continueChatAgent.ts` have no new errors.
