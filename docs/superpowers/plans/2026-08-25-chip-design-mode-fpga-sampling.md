# Chip Design mode — FPGA thermal-noise token sampling loop

## Root cause / motivation

Mobius already ships a `Game` mode that puts the agent in a closed loop with an
external engine (Godot) through a workspace MCP server. There is no equivalent
mode for hardware/chip work, so an agent asked to drive an FPGA has no toolchain
tools, no auto-approve, and no system prompt that describes the loop.

We want a `Chip` mode that drives this chain:

```
AI-IDE (Mobius / Continue "Chip" mode)
  -> MCP: custom-fpga-mcp (fastmcp, self-built, single server)
       1. receive current-step logits from the host LLM
       2. Docker F4PGA: synthesize TRNG + SC probabilistic accelerator RTL -> bitstream
       3. host openFPGALoader: flash Arty A7-35T
       4. pyserial UART: push logits into FPGA CSRs
       5. FPGA: ring-oscillator thermal-noise TRNG -> SC stochastic softmax
                -> physical sampling -> token_id
       6. MCP reads token_id back over UART, returns structured JSON
  -> host LLM appends the hardware-sampled token, continues prefill/generate
```

## Goal

1. `Chip` appears in the Agents-window mode selector, cycles with `Ctrl/Cmd+.`,
   has its own icon, gets Agent-mode tool access + auto-approve + editor context,
   and routes to a dedicated system message.
2. A real, self-built `custom-fpga-mcp` fastmcp server exposing the six steps as
   MCP tools, degrading gracefully when Docker / board / openFPGALoader are absent.
3. Synthesizable RTL for the sampler (thermal-noise TRNG + stochastic-computing
   softmax + UART protocol) plus a LiteX SoC target for Arty A7-35T.
4. Upstream projects the flow depends on vendored as git submodules under
   `vendor/`, split into a light core tier and a heavy optional tier.
5. `chip-design/` + `vendor/` ship inside the packaged Mobius installer.

## Non-goals

- Actually flashing a board in CI. No Arty A7 is attached to the build machine, so
  every hardware tool must report a structured "not available" result instead of
  throwing.
- Building Verilator / openFPGALoader / llama.cpp from source during setup. Those
  are optional submodules; setup prefers prebuilt binaries on PATH.
- Full-vocabulary softmax in fabric. The host pre-filters to top-K (K <= 64) and
  the FPGA samples within that window.

## Upstream project selection

Two repos in the original request do not exist (verified with `git ls-remote`):
`osresearch/picoTRNG` and `HuamingLi/Stochastic-Computing`. Replacements chosen:

| Need | Requested | Used | Why |
| --- | --- | --- | --- |
| On-chip ring-oscillator TRNG (Verilog) | `osresearch/picoTRNG` (404) | `secworks/trng` | Real, maintained Verilog TRNG core with ring-oscillator entropy + whitening. |
| Stochastic-computing Verilog library | `HuamingLi/Stochastic-Computing` (404) | `arminalaghi/scsynth` | Synthesis tool + Verilog generators for SC arithmetic (mult / adder / Bernoulli). |

Canonical redirects resolved: `jlowin/fastmcp` -> `PrefectHQ/fastmcp`,
`ggerganov/llama.cpp` -> `ggml-org/llama.cpp`.

### Core tier (auto-init, ~105 MB shallow)

| Path | Repo |
| --- | --- |
| `vendor/fastmcp` | PrefectHQ/fastmcp |
| `vendor/mcp-python-sdk` | modelcontextprotocol/python-sdk |
| `vendor/pyserial` | pyserial/pyserial |
| `vendor/f4pga` | chipsalliance/f4pga |
| `vendor/litex` | enjoy-digital/litex |
| `vendor/litex-boards` | litex-hub/litex-boards |
| `vendor/trng` | secworks/trng |
| `vendor/scsynth` | arminalaghi/scsynth |
| `vendor/hotspot` | uvahotspot/HotSpot |

### Optional tier (`update = none`, opt in with `-Tier all`)

| Path | Repo | Size |
| --- | --- | --- |
| `vendor/f4pga-examples` | chipsalliance/f4pga-examples | 116 MB |
| `vendor/openFPGALoader` | trabucayre/openFPGALoader | 37 MB |
| `vendor/verilator` | verilator/verilator | 79 MB |
| `vendor/llama.cpp` | ggml-org/llama.cpp | 424 MB |

## Tasks

1. [x] `continue/core/index.d.ts` — add `"chip"` to the `MessageModes` union.
2. [x] `continue/core/llm/defaultSystemMessages.ts` — add `DEFAULT_CHIP_SYSTEM_MESSAGE`.
3. [x] `continue/gui/src/redux/util/getBaseSystemMessage.ts` — route `chip`.
4. [x] `continue/gui/src/redux/util/getBaseSystemMessage.test.ts` — cover `chip`
   in both the routing test and the no-tools-warning test.
5. [x] `continue/gui/src/components/ModeSelect/ModeSelect.tsx` — listbox option,
   cycle order `chat -> plan -> agent -> game -> chip -> chat`, button label.
6. [x] `continue/gui/src/components/ModeSelect/ModeIcon.tsx` — chip/IC icon.
7. [x] `continue/gui/src/util/agentAutoApprove.ts` — treat `chip` like `agent`.
8. [x] `.../TipTapEditor/utils/resolveEditorContent.ts` — include `chip` in
   `isInAgentMode` so it gathers the same editor context as agent mode.
8b. [x] `AtMentionDropdown` + `agentAutoApprove.test.ts` — chip matches agent/game.
9. [x] `.gitmodules` + `vendor/` — add submodules, shallow, tiered.
10. [x] `chip-design/rtl/` — `trng_ring_osc.v`, `sc_core.v`, `sc_softmax_sampler.v`,
    `uart_rx.v`, `uart_tx.v`, `sampler_uart_top.v` (Verilog-2001, synthesizable).
11. [x] `chip-design/soc/arty_a7_sampler_soc.py` — LiteX SoC wrapping the sampler.
12. [x] `chip-design/constraints/arty_a7_35t.xdc` — pins for F4PGA standalone flow.
13. [x] `chip-design/sim/` — Verilator testbench + C++ harness.
14. [x] `chip-design/mcp/custom_fpga_mcp/` — fastmcp server:
    `config.py`, `protocol.py`, `toolchain.py`, `synth.py`, `flash.py`,
    `uart.py`, `sim.py`, `sampling.py`, `server.py`, `cli.py`, `__main__.py`.
    `protocol.py` must be stdlib-only so it is unit-testable with no venv.
15. [x] `chip-design/tests/` — stdlib `unittest` covering frame codec, CRC, CDF
    sampling reference, and toolchain degradation.
16. [x] `scripts/fpga-mcp-launcher.js` — resolve venv python, exec the server;
    fall back to `scripts/fpga-mcp-fallback.js` when the venv is missing.
    `--self-test` round-trips `initialize` / `tools/list` / `tools/call`.
17. [x] `scripts/fpga-mcp-fallback.js` — zero-dep Node MCP server exposing
    the same tool names as the Python server. Stdlib-only CLI commands
    (`detect`, `paths`, `lint`, `simulate`, `reference`) are delegated to a
    plain interpreter when one can import the package.
18. [x] `scripts/setup-chip-design.ps1` — submodule init, venv, vendored pip installs,
    openFPGALoader / Docker / Verilator detection, writes `chip-design/.toolchain.json`.
19. [x] `.mcp.json` + `.continue/mcpServers/custom-fpga.json` — register the server.
20. [x] `.continue/rules/chip-design-mode.md` — alwaysApply workspace rule.
21. [x] `package.json` — `chip:*` npm scripts mirroring every MCP tool.
22. [x] `scripts/stage-chip-design.ps1` + `scripts/package.ps1` step — stage
    `chip-design/` into `VSCode-win32-<arch>/resources/mobius-chip`.
23. [x] `.gitignore` — venv, bitstreams, sim objects, staged toolchain json.
24. [x] `chip-design/README.md` — flow, submodules, setup, packaging.

## Acceptance criteria

- `node scripts/fpga-mcp-launcher.js --self-test` lists all tools and round-trips
  a `tools/call`, both with and without the venv present.
- `python -m unittest discover chip-design/tests` passes with system Python and no
  third-party packages installed.
- `npx tsc --noEmit` (Continue gui + core) reports no new errors.
- `Get-Command -Syntax` parses every new/changed `.ps1`.
- `git submodule status` lists the core tier initialized; optional tier present in
  `.gitmodules` but not cloned.
- Mode selector cycles through `Chip`, and `getBaseSystemMessage("chip", ...)`
  returns `DEFAULT_CHIP_SYSTEM_MESSAGE`.
- `git status --short` clean at the end.
