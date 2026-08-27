# Chip in the Mobius Agents window picker

## Root cause

Chip was added to Continue GUI `ModeSelect` (chat/plan/agent/game/chip). The
screenshot picker is VS Code `ModePickerActionItem` + `getMobiusChatModes()`,
which returns only Agent and Game. Game appears because
`.github/agents/Game.agent.md` exists and `findModeByName('Game')` is listed.
There is no Chip custom agent and Chip is not in that list.

## Goal

Chip appears in the Agents dropdown next to Agent and Game, with its own icon,
hover, and detail line. Selecting it uses Agent tools, injects the FPGA sampler
hint, and never auto-opens Godot.

## Non-goals

- Rebuild Continue GUI ModeSelect (already has chip).
- Flash hardware or change MCP tools.
- Commit leftover chip-design submodule work from the prior session.

## Tasks

1. [x] Plan doc (this file).
2. [x] `.github/agents/Chip.agent.md` + vscode copies + bundled agent name.
3. [x] `getMobiusChatModes` / hover / detail / icons / CSS / `registerIcon`.
4. [x] `CONTINUE_CHIP_AGENT_ID`, dynamic agent, `/chip` routing, system hint,
       `isAgentMode` includes chip, skip Godot.
5. [x] Lint changed TS files. `gulp compile-client` — 0 errors. Full `npm run compile` still fails on unrelated `extensions/configuration-editing` Octokit types (pre-existing).

## Acceptance criteria

- Agents picker list is Agent, Game, Chip.
- Chip detail: FPGA sampler, no auto Godot.
- Chip hover explains RTL / F4PGA / UART sampling.
- Chip mode does not bootstrap Godot.
- Chip mode still has Agent write tools.
