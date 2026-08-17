# Mobius Game Dev Mode

Godot projects for agent-driven game development. Everything in this folder is
plain text (`.gd` scripts, `.tscn` scenes, `.tres` resources) and is read/written
directly by the Continue agent. Godot auto-imports files on the next run, so
"import into Godot" == "write files here".

## How the agent drives Godot

The Continue agent is wired to a Godot MCP server (`scripts/godot-mcp-server.js`)
that exposes these tools:

| Tool | What it does |
| --- | --- |
| `godot_detect` | Report the Godot binary + version + project dir |
| `godot_project_init` | Scaffold a new Godot 4 project (no-op if it exists) |
| `godot_import` | Run the editor headless to (re)import assets |
| `godot_run` | Run the project headless for N frames, scan for errors |
| `godot_test` | Run `res://tests/test_runner.gd` and report pass/fail |

## Setup

```powershell
npm run godot:setup          # detect existing Godot
npm run godot:setup -- -Install   # download Godot 4 into tools/godot/
```

The MCP server resolves Godot in this order: `GODOT_BIN` → `tools/godot/godot.exe`
→ PATH → common install dirs. Then run `npm run sync:config` and reload Continue
to activate the tools.

## Quick check

```powershell
node scripts/godot-mcp-server.js --self-test
```

## Workflow

1. Tell the agent: **"game dev mode: build a ..."**
2. The agent writes scenes/scripts under `game-dev/`, then calls
   `godot_import` → `godot_test` → `godot_run` and iterates on errors.
3. Open the project in the Godot editor (`tools/godot/godot.exe --editor
   --path game-dev`) for the visual preview; the agent keeps editing the same
   files for real-time changes.
