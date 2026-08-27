---
alwaysApply: true
description: Drive an FPGA as a physical token sampler — RTL, native Yosys/openXC7 synthesis, JTAG flashing and UART sampling from chip-design/
---

# Chip Design Mode (FPGA token sampler)

When the user asks about chip design, FPGA work, RTL, or physical/hardware token
sampling — or when Agents window **Chip** mode is selected — the project is
`chip-design/`. Vendored upstream sources live in `vendor/` and are read-only
reference: never edit them, and never commit inside a submodule.

## What the hardware actually does

```
host LLM logits
  → UART frame (pyserial)
    → FPGA: ring-oscillator thermal-noise TRNG
           → stochastic-computing softmax
           → inverse-CDF draw
    ← UART frame carrying token_id
host LLM appends the token and continues prefill/generate
```

The token is drawn by fabric thermal noise, not by a PRNG on the host. That is
the entire point, which is why proving the entropy source is alive matters as
much as getting an answer back.

## Drive it with these tools, in this order

Never guess a raw shell command when a tool exists.

| Tool | Purpose |
|---|---|
| `fpga_detect` | What this host can do, and every blocker. **Start here.** |
| `fpga_lint` | Verilator lint — width/latch/case bugs, no board needed |
| `fpga_simulate` | Statistical testbench: framing, CRC, logit loading, distribution |
| `fpga_synthesize` | Host Yosys + openXC7 (nextpnr-xilinx) → bitstream; Docker F4PGA only as fallback |
| `fpga_flash` | Host `openFPGALoader` over JTAG |
| `fpga_device_info` | Confirm the host and bitstream agree on K |
| `fpga_trng_entropy` | Prove the entropy source is alive |
| `fpga_verify_distribution` | Acceptance test for a freshly flashed board |
| `fpga_sample_token` / `fpga_sample_sequence` | The generation loop |
| `fpga_self_test` | All of the above, in dependency order |
| `fpga_reference_distribution` | What the hardware *should* sample — no board needed |

`fpga_close_link` releases the serial port. Call it before `fpga_flash`:
openFPGALoader cannot claim the FTDI interface while the port is held open.

## Hardware is usually absent — stay useful anyway

Most machines have no Arty A7 and may still be missing Verilator or openXC7.
`fpga_detect` reports exactly which. Read its output instead of assuming.

- Missing board → still edit RTL and verify with `fpga_lint` + `fpga_simulate`.
- Missing Verilator → say so; run `npm run chip:cad-suite`.
- Missing nextpnr-xilinx → say so; run `npm run chip:openxc7`. Docker is not required.

Say plainly which physical step is blocked and why. **Never fabricate a
`token_id`, a bitstream path, or timing/utilisation numbers you did not read from
a tool result.** If the MCP server reports `mode: fallback`, no FPGA operation is
possible at all — report that and stop, rather than improvising shell commands.

## Done means measured

"Files written" is not done. A sampler that answers every frame can still be
statistically wrong, and a dead entropy source makes it return argmax forever
while looking perfect. So:

- lint clean, and
- `fpga_simulate` passing its distribution check, and
- with a board attached, `fpga_verify_distribution` consistent with the model.

## RTL rules

Everything under `chip-design/rtl/` must be synthesisable Verilog-2001:

- no delays (`#10`), no `initial` blocks outside testbenches,
- reset every register,
- keep `` `default_nettype none `` at the top and restore it at the bottom.

The UART framing in `rtl/sampler_uart_top.v` and
`mcp/custom_fpga_mcp/protocol.py` are two halves of one contract. Change one and
you must change the other and update `chip-design/tests/`. A drift there does not
crash — it silently returns wrong tokens.

Logits are signed **Q8.8**; probabilities are **Q0.16**. The exponent constants in
`sc_softmax_sampler.v` encode that exact scaling, so changing `LOGIT_W` without
regenerating the table silently changes the sampling temperature.

## Two build paths

- `rtl/sampler_uart_top.v` — standalone top level with a hand-written UART
  framer. This is what the MCP tools drive. Default.
- `soc/arty_a7_sampler_soc.py` — the same sampler as a CSR peripheral on a LiteX
  SoC. Opt-in, needs LiteX installed (`npm run chip:setup -- -WithLitex`), for
  when you want firmware or a bus next to the sampler.

## If setup is incomplete

Run `npm run chip:setup` (downloads YosysHQ OSS CAD Suite / Verilator into
`tools/oss-cad-suite` and FPGAwars openXC7 into `tools/openxc7`; add
`-SkipCadSuite` / `-SkipOpenXc7` to skip, `-PullImage` only for the optional
F4PGA Docker fallback, `-WithLitex` for the SoC flow). Do not pip-install into the system
interpreter — the MCP server runs from `chip-design/.venv`, and installing
elsewhere will look like it worked and change nothing.

Tests: `npm run chip:test` (stdlib `unittest`, no venv or hardware required).
