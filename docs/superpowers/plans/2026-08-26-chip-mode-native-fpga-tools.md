# Chip mode must call native fpga_* tools (not invent RTL)

## Root cause

Game mode works because `godot_*` schemas are merged in
`loadContinueAgentTools` and dispatched in `continueChatAgent._executeTool`.
Chip mode only injected a system hint naming `fpga_*`. Those names were never
in the model tool list, so the agent role-played `fpga_detect`, claimed
`chip-design/` was missing, and wrote new Verilog (`ro_inv.v`) instead of
driving `scripts/fpga-cli.js` and `vendor/`.

Workspace MCP (`.mcp.json`) is not wired into the Agents-window Continue
participant the way native Godot tools are.

## Goal

Chip mode gets the same native-tool loop as Game: `fpga_detect` / `fpga_lint` /
`fpga_simulate` (and the rest) shell out to `node scripts/fpga-cli.js`, which
runs `python -m custom_fpga_mcp` against `chip-design/` and probes `vendor/`.
Selecting Chip auto-runs `fpga_detect` and injects the JSON before the first
model turn. The agent must edit existing RTL, not scaffold a new tree.

## Non-goals

- Installing Docker / Verilator / a board in this change.
- Changing F4PGA Docker image internals.

## Tasks

1. [x] `continueFpgaTools.ts` — schemas, path resolve, CLI mapping, execute.
2. [x] Merge schemas + dispatch + auto-detect bootstrap in Chip mode.
3. [x] CLI `close` / `sequence`; tighten Chip.agent.md + system hint.
4. [x] Compile client; run `fpga-cli.js detect` once.

## Acceptance criteria

- Model tool list includes `fpga_detect`, `fpga_lint`, `fpga_simulate`, …
- Chip-mode start posts a real `fpga_detect` result that lists `chip-design/`
  and `vendor/` (even when Verilator/Docker are absent).
- Hint forbids creating parallel RTL (`ro_inv.v`) and installing iverilog
  when `fpga_lint` already wraps Verilator.
