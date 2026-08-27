# Bundle MinGW make/g++ so fpga_simulate --build works

## Root cause

YosysHQ OSS CAD Suite on Windows ships `verilator_bin.exe` (lint works) but
not GNU make or g++. `verilator --cc --exe --build` therefore fails on the
generated C++ testbench. Icarus was a workaround; Chip mode's `fpga_simulate`
is supposed to use the Verilator statistical bench.

## Goal

1. `npm run chip:mingw` installs portable GNU make + g++ into `tools/mingw/`
   (gitignored). Preferred source: MSYS2 mingw64 packages from USTC
   (`config/mingw.packages`). Fallback: pinned w64devkit from GitHub.
2. `config.cad_suite_env` / `tool_env` put that `bin/` on PATH and set CXX/CC.
3. `npm run chip:setup` installs it by default. `fpga_simulate` then completes
   `--build` without a host MSYS2 / VS Build Tools install.

## Non-goals

- Replacing Icarus benches (they stay as extra coverage).
- Shipping Visual Studio / MSVC.
- Committing the ~200 MB unpacked toolchain.

## Tasks

1. [x] Pin w64devkit; setup script; gitignore; package.json; stage + chip:setup.
2. [x] config.py + toolchain probes + sim.py early hint.
3. [x] Download on this machine; `fpga_simulate` `--build` succeeds.
   CN path: MSYS2 mingw64 packages from USTC (`config/mingw.packages`), with
   w64devkit as GitHub fallback. Verilator makefile paths use forward slashes
   so GNU make + sh.exe do not eat backslashes. TB provides `sc_time_stamp()`.

## Acceptance criteria

- [x] After `npm run chip:mingw`, `fpga_detect` shows make and g++ available.
- [x] `node scripts/fpga-cli.js simulate` gets past Verilator `--build` (make/g++
  no longer the failure). Missing kit still hints `npm run chip:mingw`.
