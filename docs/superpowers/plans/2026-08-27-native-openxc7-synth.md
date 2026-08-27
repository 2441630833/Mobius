# Native Windows Xilinx 7-series synthesis (no Docker)

## Root cause

`fpga_synthesize` shells out to Docker `ghcr.io/chipsalliance/f4pga` because
F4PGA (Yosys + nextpnr-xilinx + prjxray) is a Linux flow. YosysHQ OSS CAD
Suite on Windows already ships `yosys.exe` but **not** `nextpnr-xilinx` (only
Lattice/Gowin nextpnr). That is why Docker was required.

## Goal

Same Chip loop on Windows without Docker:

`yosys` (OSS CAD Suite) → `nextpnr-xilinx` + `fasm2frames` + `xc7frames2bit`
(FPGAwars **openXC7** Windows package) → `.bit` on the host.

Docker remains an optional fallback when the native tools are missing.

## Non-goals

- Bundling Vivado
- WSL as the default path
- Changing RTL or the UART protocol
- Shipping every Xilinx 7-series chipdb (only Arty A7-35T `xc7a35tcsg324`)

## Tasks

1. [x] Pin `config/openxc7.version`; `scripts/setup-openxc7.ps1` downloads
   `apio-openxc7-windows-amd64-*.tgz` (~621 MB) plus the
   `xc7a35tcsg324` chipdb (~25 MB) into `tools/openxc7/` (gitignored).
2. [x] `config.py` / `toolchain.py`: resolve yosys + nextpnr-xilinx +
   xc7frames2bit + chipdb + prjxray-db; `can_synthesize` is native OR Docker.
3. [x] `synth.py`: native host flow first; Docker only if native is incomplete.
4. [x] Tests, README, Chip.agent.md, `fpga_*` tool blurbs, `chip:openxc7` npm
   script, `chip:setup` calls the new installer.
5. [x] Install on this machine; `fpga_detect` reports nextpnr-xilinx available.

## Acceptance criteria

- After `npm run chip:openxc7` (or `chip:setup`), `fpga_detect` shows yosys +
  nextpnr-xilinx without Docker.
- `fpga_synthesize` does not start Docker when native tools are present.
- Missing openXC7 still returns a structured failure with
  `npm run chip:openxc7`, not a traceback.
