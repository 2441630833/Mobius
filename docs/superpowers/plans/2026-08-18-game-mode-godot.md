# Game mode + built-in Godot (complete mini-game)

## Root cause

Continue GUI already has a **Game** mode (selector, system prompt, auto-approve) and a Godot MCP server (`scripts/godot-mcp-server.js` + `.continue/mcpServers/godot.json`). That path never reached the surface Mobius actually launches (`npm start -- --agents`):

- `ContinueChatAgent` only registers Ask / Edit / Agent. It never loads Continue MCP tools.
- `godot_*` is therefore not in the Agents-window tool list, so the model cannot import/run/preview Godot.
- `findWorkspaceRoot()` started at `process.cwd()`, so a mis-cwd MCP spawn could miss the repo.
- `game-dev/` was a stub (`Main scene ready`), not a playable game.

## Goal

- Agents window can call `godot_detect` / `godot_project_init` / `godot_import` / `godot_run` / `godot_test` / `godot_preview`.
- Continue GUI Game mode still works (MCP), with a workspace-root-safe server.
- `game-dev/` is a complete playable mini-game (Star Catcher) that imports, tests, and runs headless, and `godot_preview` opens the bundled editor.

## Non-goals

- Adding a new `ChatModeKind` to VS Code core (too invasive). Game remains a Continue GUI mode; Agents uses Agent + `godot_*` tools (and game-intent system prompt).
- Committing `tools/godot/` binaries or `.godot/` cache.
- Committing unrelated embedding-session dirty files.

## Tasks

1. [x] Fix MCP server: resolve workspace from `__dirname`, extra CLI flags, `godot_preview` npm script, richer `--self-test`.
2. [x] Native `godot_*` tools in ContinueChatAgent (same CLI as MCP).
3. [x] Inject game-dev system prompt on game intent; keep Continue GUI Game mode tests.
4. [x] Replace stub `game-dev/` with Star Catcher + headless tests.
5. [x] Install Godot if missing; run detect → import → test → run.

## Acceptance criteria

- `node scripts/godot-mcp-server.js --self-test` lists all six tools and finds Godot.
- `godot_import` / `godot_test` / `godot_run` succeed (pass>0, fail=0, no engine errors).
- Agents tool list includes `godot_detect` … `godot_preview` (compile of continue workbench files).
- Continue `getBaseSystemMessage("game")` returns `DEFAULT_GAME_SYSTEM_MESSAGE`.
