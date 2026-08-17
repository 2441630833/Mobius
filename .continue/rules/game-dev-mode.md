---
alwaysApply: true
description: Drive the Godot engine from the agent to build, modify and test games in game-dev/
---

# Game Dev Mode (Godot)

When the user asks to build, modify, or test a game (or says "game dev mode"),
treat `game-dev/` as the Godot project workspace. Every game asset is a plain
text file (`.gd` scripts, `.tscn` scenes, `.tres` resources), so Godot
auto-imports whatever the agent writes — "import into Godot" == "write files
under game-dev/".

## Drive Godot with the MCP tools

- `godot_detect` — locate the engine binary + version + project dir.
- `godot_project_init` — scaffold a new Godot 4 project (no-op if it exists).
- `godot_import` — run the editor headless to (re)import assets after adding files.
- `godot_run` — run the project headless for N frames and scan for Godot errors.
- `godot_test` — run `res://tests/test_runner.gd` headlessly, report pass/fail.

## Workflow

1. Write all game files under `game-dev/`.
2. After adding new assets/scenes, call `godot_import`.
3. Verify with `godot_test` (add `test_*` functions to `game-dev/tests/test_runner.gd`).
4. Smoke-run with `godot_run`, read the Godot output/errors, fix the file,
   re-run until green.
5. The user can preview visually by opening `tools/godot/godot.exe --editor
   --path game-dev`; the agent keeps editing the same files for real-time changes.

## If Godot is missing

Run `npm run godot:setup -- -Install` to download Godot 4 into `tools/godot/`.
The MCP server resolves the engine in this order: `GODOT_BIN` →
`tools/godot/godot.path` → `tools/godot/godot.exe` → PATH → common install dirs.
