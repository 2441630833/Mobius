---
alwaysApply: true
description: Drive the Godot engine from the agent to build, modify and test games in game-dev/
---

# Game Dev Mode (Godot)

When the user asks to build, modify, or test a game (or says "game mode" / "game dev mode"),
or when Agents window **Game** mode is selected:

## Core Invariants

1. **All 2D & 3D Games MUST Use Godot**:
   - Every game (2D and 3D alike) MUST use the Godot engine (Godot 4 GDScript under `game-dev/` or target project).
   - **NEVER** build Web / Canvas / HTML5 / React / Vite games.
   - **NEVER** launch a web server (`npm run dev`, `vite`, `python -m http.server`, etc.) to run or preview games.

2. **Search GitHub & Pull First (No Starting from Scratch Immediately)**:
   - When requested to build a new game, do NOT start creating files from scratch immediately.
   - First search GitHub for mature open-source Godot game projects with matching mechanics or genre.
   - Pull/clone the project or reference its architecture and assets.
   - **gh-proxy Mirror**: If connecting to foreign GitHub fails, is blocked, or times out, ALWAYS use the `https://gh-proxy.com/` mirror source (e.g. `git clone https://gh-proxy.com/https://github.com/<owner>/<repo>.git`).

3. **No Godot Popups During Coding**:
   - While editing code, writing scripts, importing assets, or testing, **do NOT open the Godot editor or window by default**.
   - Keep all operations headless (`godot_import`, `godot_test`).
   - Only open the Godot editor if the user explicitly sends a prompt asking to open Godot.

4. **Playable Godot Preview on Completion**:
   - When the game code is finished and verified (`godot_test` passes), launch the playable preview game in Godot using `godot_play`.
   - The user previews and plays the real Godot game.

## Tools

- `godot_detect` — locate engine binary, version, and project directory.
- `godot_project_init` — scaffold a Godot 4 project (no-op if existing).
- `godot_import` — run editor headless to (re)import assets after writing files.
- `godot_run` — headless smoke run for N frames.
- `godot_test` — run `res://tests/test_runner.gd` headlessly, report pass/fail.
- `godot_play` — run the playable game window in Godot (with arrow keys / controls).
- `godot_preview` — open Godot window (`editor=true` ONLY when user explicitly asks to open editor).

## Workflow

1. For new games: Search GitHub for mature Godot projects; clone via `https://gh-proxy.com/` if foreign GitHub connection is blocked.
2. Write/edit game files under `game-dev/` (`.gd`, `.tscn`, `.tres`).
3. Call `godot_import` headlessly.
4. Verify headlessly with `godot_test`.
5. Do NOT open Godot windows while coding unless the user explicitly requested it.
6. When complete, call `godot_play` to launch the playable Godot preview game.
