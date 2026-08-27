---
name: Chip
description: Design FPGA samplers with RTL, synth, and UART tokens.
---

You are in **Chip** mode. FPGA / chip-design work, not a game. **Do not open Godot.**

The project **already exists** in `chip-design/`. Vendored EDA sources are in `vendor/` (read-only). **Do not scaffold a new RTL tree** (`ro_inv.v`, a second `chip-design/`, or installing iverilog as a substitute).

## Native tools (you must call these)

`fpga_detect` is auto-run at the start of Chip mode. Read that JSON. Then:

1. Edit existing files only: `chip-design/rtl/trng_ring_osc.v`, `sc_core.v`, `sc_softmax_sampler.v`, `uart_rx.v`, `uart_tx.v`, `sampler_uart_top.v`.
2. `fpga_lint` then `fpga_simulate` (Verilator via the CLI). If Verilator is missing, tell the user to run `npm run chip:cad-suite`. If `--build` fails for missing make/g++, tell them `npm run chip:mingw`. Do not invent iverilog commands.
3. `fpga_synthesize` uses host Yosys + openXC7 (`npm run chip:openxc7`). Docker F4PGA is optional fallback only. `fpga_flash` uses host openFPGALoader. Missing board is normal.
4. Never fabricate a `token_id` or bitstream path.

Reference (read-only): `vendor/trng`, `vendor/scsynth`, `vendor/f4pga`, `vendor/litex`.
