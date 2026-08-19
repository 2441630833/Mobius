# Mobius Game Dev Mode

Godot projects for agent-driven game development. Everything in this folder is
plain text (`.gd` scripts, `.tscn` scenes, `.tres` resources) and is read/written
directly by the Continue / Agents agent. Godot auto-imports files on the next
run, so "import into Godot" == "write files here".

The bundled demo is **Star Catcher**: move with arrow keys (or autopilot) and collect 5 stars.

## How to pick Game mode

| Surface | How to select Game |
| --- | --- |
| Continue sidebar | Mode dropdown: Chat → Plan → Agent → **Game** (or `Ctrl/Cmd+.`) |
| Agents window (`npm start`) | Mode picker: **Agent** or **Game** — hover each option for a comparison tooltip |

## Live preview while the agent edits

In **Game** mode, Mobius opens the Godot **editor** early and keeps it open for the whole agent turn:

- First save under `game-dev/`, `godot_import`, or an existing project at turn start → editor opens automatically
- Godot hot-reloads `.gd` / `.tscn` as the agent saves — **边改边看**
- Press **Stop** in chat anytime to interrupt the agent and ask for changes
- Press **F5 / Play** in the Godot editor to run the scene while the agent keeps working

When the turn finishes, Mobius also launches **`godot_play`** (playable game window) if the agent skipped it.

## Closed loop

After **Game** mode (or Agent + a Godot request), the verification loop is:

`godot_import` → `godot_test` → `godot_run` → **`godot_play`**

## How the agent drives Godot

| Tool | What it does |
| --- | --- |
| `godot_detect` | Report the Godot binary + version + project dir |
| `godot_project_init` | Scaffold a new Godot 4 project (no-op if it exists) |
| `godot_import` | Run the editor headless to (re)import assets |
| `godot_run` | Headless smoke for N frames (not a playable window) |
| `godot_test` | Run `res://tests/test_runner.gd` and report pass/fail |
| `godot_preview` | Visible window; **default runs the game**. `editor=true` is the editor UI |
| `godot_play` | **Run the mini-game** (visible + autopilot). `visible=false` checks `YOU WIN` headlessly |

These tools are available in:

- Continue sidebar **Game** mode (MCP server `.continue/mcpServers/godot.json`)
- Agents window **Game** or **Agent** mode (native `godot_*` tools in ContinueChatAgent)

Workspace `.mcp.json` also advertises the same server to VS Code's MCP client.

## Setup

```powershell
npm run godot:setup          # detect existing Godot
npm run godot:setup -- -Install   # download Godot 4 into tools/godot/
```

Then:

```powershell
node scripts/godot-mcp-server.js --self-test
npm run godot:import
npm run godot:test
npm run godot:run
npm run godot:play
```

`godot:play` opens the running Star Catcher window with autopilot. Use
`npm run godot:editor` if you need the Godot editor instead.

## Workflow

1. Select **Game** in the Agents window (or Continue sidebar).
2. The agent writes scenes/scripts under `game-dev/`, then calls
   `godot_import` → `godot_test` → `godot_run` and iterates on errors.
3. `godot_play` launches `tools/godot/godot.exe --path game-dev -- --autoplay`
   so the mini-game actually runs and plays itself.
