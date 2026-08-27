# Bundle YosysHQ OSS CAD Suite (Verilator + g++/perl + openFPGALoader)

## Root cause

Chip mode's `fpga_lint` / `fpga_simulate` need a host Verilator. `vendor/` only
has RTL reference sources. Verilator is not a single .exe: on Windows it needs
the YosysHQ **OSS CAD Suite** (verilator_bin, PERL/g++, VERILATOR_ROOT). Same
pattern as Godot: download into `tools/`, gitignore, resolve from Chip tools.

Windows suite ~568 MB (`oss-cad-suite-windows-x64-20260826.tgz`). Not committed.

## Goal

1. `npm run chip:setup` downloads the pinned suite into `tools/oss-cad-suite/`.
2. `config.find_tool` / `toolchain.run` use that tree (PATH + VERILATOR_ROOT).
3. Packaged Mobius stages the suite when present (`resources/mobius-chip/tools/`).

## Non-goals

- Bundling Docker / F4PGA image (still GB-scale, still `-PullImage`).
- Building Verilator from `vendor/verilator` source on Windows.

## Tasks

1. [x] Pin version; setup script; gitignore.
2. [x] config.py + toolchain env; setup-chip-design records bundled paths.
3. [x] stage-chip-design + package.json + README.
4. [x] Download/install on this machine; `fpga_detect` shows verilator available.

## Acceptance criteria

- After setup, `node scripts/fpga-cli.js detect` reports verilator available
  from `tools/oss-cad-suite`.
- Missing suite still degrades with a hint to run `npm run chip:setup`.
