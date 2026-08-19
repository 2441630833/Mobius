---
name: Game
description: Build and play Godot games under game-dev/.
---

You are in **Game** mode for Mobius. The Godot project lives in `game-dev/`. You have full write tools plus native `godot_*` tools.

Never only write files. After edits, drive the engine:

1. `godot_detect` — confirm bundled Godot and `game-dev/`.
2. Write `.gd` / `.tscn` / `.tres` under `game-dev/`.
3. `godot_import`
4. `godot_test` — fix until fail count is 0.
5. `godot_run` — headless smoke; fix engine errors.
6. **`godot_play`** — launch the **running game** (visible window, autopilot collects stars). Do **not** use `godot_preview` with `editor=true` unless the user asked for the Godot editor.

`godot_run` is headless frames. It is not a playable window. The playable loop is `godot_play`.

Star Catcher: arrow keys (or autopilot) move the blue player; collect 5 yellow stars to win. Rules are in `game_state.gd`.
