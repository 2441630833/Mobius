# Chip Design — FPGA thermal-noise token sampler

Chip mode in the Agents window drives a real FPGA as a physical sampling
co-processor for language-model token generation. The host LLM produces logits;
the board draws a `token_id` from fabric thermal noise and returns it over UART.

```
AI-IDE (Mobius Chip mode)
  -> MCP: custom-fpga-mcp (fastmcp, this directory)
       1. receive current-step logits
       2. host Yosys + openXC7 (nextpnr-xilinx): synthesize TRNG + SC RTL -> bitstream
       3. host openFPGALoader: flash Arty A7-35T (never inside Docker)
       4. pyserial UART: push logits into FPGA registers
       5. FPGA: ring-oscillator TRNG -> SC stochastic softmax -> token_id
       6. MCP reads token_id, returns structured JSON
  -> host LLM appends the token and continues prefill/generate
```

The standalone top level (`rtl/sampler_uart_top.v`) is what the MCP tools
synthesize and flash. `soc/arty_a7_sampler_soc.py` is an optional LiteX SoC
wrapping the same sampler behind CSRs.

## Setup

From the Mobius repo root:

```
npm run chip:setup
```

That creates `chip-design/.venv` (fastmcp + pyserial), initialises the core
`vendor/` submodules, downloads YosysHQ **OSS CAD Suite** into
`tools/oss-cad-suite/` (Verilator + usually openFPGALoader, ~570 MB,
same pattern as Godot in `tools/godot/`), downloads FPGAwars **openXC7** into
`tools/openxc7/` (nextpnr-xilinx + Arty A7 chipdb, ~650 MB), downloads
**w64devkit** or MSYS2 mingw64 gcc/make into `tools/mingw/` (GNU make + g++ so `fpga_simulate --build`
works; `npm run chip:mingw` prefers USTC MSYS2 packages, then GitHub w64devkit), and writes `chip-design/.toolchain.json`. Docker is **not** required. It does **not** pull
the multi-GB F4PGA image unless you pass `-PullImage`.

```
npm run chip:setup -- -PullImage          # also pull ghcr.io/chipsalliance/f4pga (optional)
npm run chip:setup -- -SkipCadSuite       # skip the Verilator download
npm run chip:setup -- -SkipOpenXc7        # skip the nextpnr-xilinx download
npm run chip:cad-suite                    # Verilator + Yosys bundle only
npm run chip:openxc7                      # nextpnr-xilinx + xc7a35tcsg324 chipdb
npm run chip:mingw                        # portable GNU make + g++ (Verilator --build)
npm run chip:setup -- -WithLitex          # LiteX SoC flow
npm run chip:setup -- -Tier all           # f4pga-examples + openFPGALoader + HotSpot
npm run chip:detect                       # what this host can actually do
npm run chip:mcp-self-test                # MCP initialize / tools/list / tools/call
npm run chip:test                         # stdlib unit tests, no venv or board
```

Then reload the IDE window so Continue re-spawns the `custom-fpga` MCP server,
and switch the Agents window to **Chip** (`Ctrl/Cmd+.` cycles modes).

## MCP tools

| Tool | Purpose |
|---|---|
| `fpga_detect` | Capability map + blockers. Start here. |
| `fpga_lint` | Verilator lint — no board needed |
| `fpga_simulate` | Statistical testbench (framing, CRC, distribution) |
| `fpga_synthesize` | Host Yosys + openXC7 → bitstream (Docker F4PGA only if native tools are missing) |
| `fpga_flash` | Host `openFPGALoader` over JTAG |
| `fpga_sample_token` / `fpga_sample_sequence` | Generation loop |
| `fpga_trng_entropy` | Prove the entropy source is alive |
| `fpga_verify_distribution` | Acceptance test after a flash |
| `fpga_self_test` | End-to-end, stops at the first hard failure |

Hardware is usually absent. `fpga_detect` reports exactly which of Verilator,
Yosys, openXC7, openFPGALoader, the venv and the serial port are missing. Stay
useful anyway: edit RTL and verify with lint + simulate. Docker is optional.

## Vendored upstream sources (`vendor/`)

Two requested repos do not exist (`osresearch/picoTRNG`,
`HuamingLi/Stochastic-Computing`). Replacements are real, maintained Verilog
that still provide a ring-oscillator TRNG and stochastic-computing arithmetic.

### Core (auto-init, shallow)

| Path | Repo | Role |
|---|---|---|
| `vendor/fastmcp` | PrefectHQ/fastmcp | MCP server framework |
| `vendor/mcp-python-sdk` | modelcontextprotocol/python-sdk | MCP protocol SDK |
| `vendor/pyserial` | pyserial/pyserial | UART |
| `vendor/f4pga` | chipsalliance/f4pga | Yosys + nextpnr-xilinx Docker flow |
| `vendor/litex` | enjoy-digital/litex | Optional SoC builder |
| `vendor/litex-boards` | litex-hub/litex-boards | Arty A7 platform |
| `vendor/trng` | secworks/trng | Ring-oscillator TRNG reference |
| `vendor/scsynth` | arminalaghi/scsynth | Stochastic-computing Verilog generators |

### Optional (`update = none`, `npm run chip:setup -- -Tier all`)

| Path | Repo | Role |
|---|---|---|
| `vendor/f4pga-examples` | chipsalliance/f4pga-examples | Arty A7-35T constraint/Makefile templates |
| `vendor/openFPGALoader` | trabucayre/openFPGALoader | JTAG programmer **source** (use a host binary on PATH) |
| `vendor/hotspot` | uvahotspot/HotSpot | Optional thermal simulation |

`vendor/` trees are read-only reference. Never edit them; never commit inside a
submodule. Runtime Python packages are pip-installed into `.venv` from
`requirements.txt`, not imported from the git checkouts.

### Host-side, not cloned

- **Verilator** — bundled by `npm run chip:cad-suite` as YosysHQ OSS CAD Suite
  under `tools/oss-cad-suite/` (gitignored). Chip tools resolve
  `verilator_bin.exe` from there, so `fpga_lint` works with no extra install.
  `fpga_simulate` (`verilator --cc --build`) also needs GNU **make + g++**,
  bundled by `npm run chip:mingw` into `tools/mingw/` (the Windows OSS CAD
  Suite does not ship those). Source: https://github.com/verilator/verilator
- **llama.cpp** — host LLM that produces logits; not part of the MCP/FPGA
  chain. https://github.com/ggml-org/llama.cpp
- **openFPGALoader binary** — also in the OSS CAD Suite `bin/` folder. USB/JTAG
  cannot be forwarded through Docker Desktop, so this must stay a host binary.
- **openXC7** — bundled by `npm run chip:openxc7` as FPGAwars `tools-openxc7`
  under `tools/openxc7/` (gitignored). This is the Windows-native
  `nextpnr-xilinx` + `xc7frames2bit` + `xc7a35tcsg324` chipdb. F4PGA itself has
  no native Windows installer; Docker `ghcr.io/chipsalliance/f4pga` remains an
  optional fallback only.

F4PGA Docker image (optional): `ghcr.io/chipsalliance/f4pga` (tag via `F4PGA_IMAGE`).

## Layout

```
chip-design/
  rtl/          synthesizable Verilog-2001 (TRNG, SC softmax, UART)
  sim/          Verilator statistical testbench
  soc/          optional LiteX SoC variant
  constraints/  Arty A7-35T pin constraints
  mcp/          custom-fpga-mcp (fastmcp)
  tests/        host-side unit tests (stdlib, no hardware)
```

UART framing in `rtl/sampler_uart_top.v` and `mcp/custom_fpga_mcp/protocol.py`
is one contract. Change one, change the other, and update `tests/`. A drift
does not crash — it silently returns the wrong token.

Logits are signed **Q8.8**; probabilities are **Q0.16**. The exponent table in
`sc_softmax_sampler.v` encodes that scaling. The host pre-filters to top-K
(K <= 64, default 32); the FPGA samples inside that window.

## Packaging

`scripts/package.ps1` stages this tree into
`VSCode-win32-<arch>/resources/mobius-chip` so an installed IDE still has the
MCP server, RTL, and launcher. The venv and bitstreams are **not** shipped
(path- and machine-specific). If `tools/oss-cad-suite` exists on the build
machine, it is copied into the payload so Verilator is ready; otherwise the
user runs `npm run chip:cad-suite` (or `chip:setup`) once. Same for
`tools/openxc7` / `npm run chip:openxc7` (`SKIP_OPENXC7_STAGE=1` to omit it).

Set `SKIP_CHIP_STAGE=1` to skip staging during a package build.
Set `SKIP_CAD_SUITE_STAGE=1` to omit the ~570 MB Verilator bundle from the installer.
Set `SKIP_OPENXC7_STAGE=1` to omit the ~650 MB openXC7 bundle from the installer.
