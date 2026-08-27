"""custom-fpga-mcp — drive an FPGA as a physical token sampler.

The chain this package implements::

    host LLM logits
      -> UART frame (protocol.py / uart.py)
        -> FPGA: ring-oscillator TRNG -> stochastic softmax -> inverse-CDF draw
      <- UART frame carrying token_id
    host LLM appends the token and continues

Plus the build steps that get the RTL onto the board: Verilator lint and
simulation (sim.py), native Yosys + openXC7 synthesis (synth.py) and host-side JTAG
programming (flash.py).

Import layering matters here. ``protocol``, ``stats``, ``config``, ``toolchain``
and ``report`` are stdlib-only, so they work on a bare interpreter with no venv
-- which is exactly the situation the diagnostics have to survive. ``uart`` and
``sampling`` need pyserial; ``server`` needs fastmcp. Nothing is imported eagerly
here for that reason.
"""

from __future__ import annotations

__all__ = [
    "config",
    "flash",
    "protocol",
    "report",
    "sampling",
    "sim",
    "stats",
    "synth",
    "toolchain",
    "uart",
]

__version__ = "1.0.0"
