#!/usr/bin/env python3
"""LiteX SoC variant of the FPGA token sampler for the Arty A7.

Two ways exist to get the sampler onto the board, and they are for different
jobs:

* ``rtl/sampler_uart_top.v`` — a bare top level with a hand-written UART framer.
  This is what the MCP tools drive (``fpga_synthesize`` / ``fpga_flash``). No CPU,
  no bus, ~nothing between the host and the sampler. Fast to build and easy to
  reason about, which is why it is the default.

* this file — the same sampler as a CSR peripheral on a real LiteX SoC, with a
  CPU, a wishbone bus and LiteX's UART. Use it when you want firmware running
  next to the sampler, want to add DMA or memory, or want to compare the
  hand-rolled framer against a bus-attached implementation.

The RTL is shared. Only the host interface differs, so a sampler bug reproduces
in both.

Build (needs the LiteX toolchain from vendor/litex, see chip-design/README.md)::

    python chip-design/soc/arty_a7_sampler_soc.py --build
    python chip-design/soc/arty_a7_sampler_soc.py --build --toolchain f4pga
    python chip-design/soc/arty_a7_sampler_soc.py --load

Register map (byte offsets are assigned by LiteX; read them from the generated
``csr.h`` / ``csr.csv`` rather than hardcoding them):

    logit       W  [15:0] value (signed Q8.8), [20:16] index, write triggers
    control     W  bit0 start (pulse), bit1 clear_done (pulse)
    status      R  bit0 busy, bit1 done (sticky), bit2 fallback_argmax,
                   bit3 entropy_fail
    token       R  sampled index
    draw_u      R  the uniform actually drawn
    total       R  sum of stochastic counts
    entropy     R  raw whitened TRNG word, refreshed continuously
"""

from __future__ import annotations

import argparse
import os
import sys

RTL_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "rtl")

# LiteX is a heavyweight optional dependency, so fail with something actionable
# rather than a bare ImportError from six levels down.
try:
    from migen import ClockDomain, ClockSignal, If, Instance, ResetSignal, Signal
    from litex.gen import LiteXModule
    from litex.soc.cores.clock import S7PLL
    from litex.soc.cores.led import LedChaser
    from litex.soc.integration.builder import Builder, builder_argdict, builder_args
    from litex.soc.integration.soc_core import SoCCore, soc_core_argdict, soc_core_args
    from litex.soc.interconnect.csr import AutoCSR, CSRField, CSRStatus, CSRStorage
except ImportError as exc:  # pragma: no cover - optional path
    raise SystemExit(
        "LiteX is not importable.\n"
        "  1. git submodule update --init vendor/litex vendor/litex-boards\n"
        "  2. chip-design/.venv/Scripts/python -m pip install -e vendor/litex "
        "-e vendor/litex-boards\n"
        f"(underlying error: {exc})"
    ) from exc

try:
    from litex_boards.platforms import digilent_arty
except ImportError as exc:  # pragma: no cover - optional path
    raise SystemExit(
        "litex-boards is not importable — install vendor/litex-boards (see above).\n"
        f"(underlying error: {exc})"
    ) from exc


# ---------------------------------------------------------------------------
# Sampler peripheral
# ---------------------------------------------------------------------------


class StochasticSampler(LiteXModule, AutoCSR):
    """The TRNG + stochastic softmax sampler behind a CSR interface.

    `done` from the RTL is a one-cycle pulse, which software polling would miss,
    so it is latched here and cleared explicitly. That is the usual reason a
    bus-attached version of a working core appears to hang.
    """

    def __init__(self, platform, k: int = 32, sc_log2: int = 12, pool_w: int = 32):
        logit_w = 16  # signed Q8.8; the RTL exponent table encodes this scaling
        idx_w = max(1, (k - 1).bit_length())
        acc_w = sc_log2 + idx_w + 1

        self.logit = CSRStorage(
            fields=[
                CSRField("value", size=logit_w, description="Signed Q8.8 logit."),
                CSRField("index", size=idx_w, offset=16, description="Candidate slot."),
            ],
            description="Write a single logit. The write itself commits it.",
        )
        self.control = CSRStorage(
            fields=[
                CSRField("start", size=1, pulse=True, description="Begin a sample."),
                CSRField("clear_done", size=1, pulse=True, description="Ack `done`."),
            ]
        )
        self.status = CSRStatus(
            fields=[
                CSRField("busy", size=1),
                CSRField("done", size=1, description="Sticky; clear via control."),
                CSRField("fallback_argmax", size=1),
                CSRField("entropy_fail", size=1),
            ]
        )
        self.token = CSRStatus(idx_w, description="Sampled candidate index.")
        self.draw_u = CSRStatus(acc_w, description="Uniform draw used by the CDF scan.")
        self.total = CSRStatus(acc_w, description="Sum of stochastic counts.")
        self.entropy = CSRStatus(pool_w, description="Raw whitened TRNG word.")

        # # #

        rand_bit = Signal()
        rand_bit_valid = Signal()
        rand_word = Signal(pool_w)
        rand_word_valid = Signal()
        entropy_fail = Signal()

        busy = Signal()
        done = Signal()
        done_sticky = Signal()
        token = Signal(idx_w)
        draw_u = Signal(acc_w)
        total = Signal(acc_w)
        fallback = Signal()

        self.specials += Instance(
            "trng_ring_osc",
            p_POOL_W=pool_w,
            i_clk=ClockSignal("sys"),
            i_rst_n=~ResetSignal("sys"),
            o_rand_bit=rand_bit,
            o_rand_valid=rand_bit_valid,
            o_rand_word=rand_word,
            o_word_valid=rand_word_valid,
            o_entropy_fail=entropy_fail,
        )

        self.specials += Instance(
            "sc_softmax_sampler",
            p_K=k,
            p_LOGIT_W=logit_w,
            p_SC_LOG2=sc_log2,
            p_POOL_W=pool_w,
            i_clk=ClockSignal("sys"),
            i_rst_n=~ResetSignal("sys"),
            i_logit_we=self.logit.re,
            i_logit_addr=self.logit.fields.index,
            i_logit_wdata=self.logit.fields.value,
            i_rand_word=rand_word,
            i_rand_word_valid=rand_word_valid,
            i_rand_bit=rand_bit,
            i_rand_bit_valid=rand_bit_valid,
            i_start=self.control.fields.start,
            o_busy=busy,
            o_done=done,
            o_token_id=token,
            o_draw_u=draw_u,
            o_total_weight=total,
            o_fallback_argmax=fallback,
        )

        self.sync += [
            If(self.control.fields.start, done_sticky.eq(0)),
            If(done, done_sticky.eq(1)),
            If(self.control.fields.clear_done, done_sticky.eq(0)),
        ]

        self.comb += [
            self.status.fields.busy.eq(busy),
            self.status.fields.done.eq(done_sticky),
            self.status.fields.fallback_argmax.eq(fallback),
            self.status.fields.entropy_fail.eq(entropy_fail),
            self.token.status.eq(token),
            self.draw_u.status.eq(draw_u),
            self.total.status.eq(total),
            self.entropy.status.eq(rand_word),
        ]

        for name in ("sc_core.v", "trng_ring_osc.v", "sc_softmax_sampler.v"):
            platform.add_source(os.path.join(RTL_DIR, name))


# ---------------------------------------------------------------------------
# SoC
# ---------------------------------------------------------------------------


class SamplerSoC(SoCCore):
    def __init__(
        self,
        variant: str = "a7-35",
        toolchain: str = "vivado",
        sys_clk_freq: float = 100e6,
        k: int = 32,
        sc_log2: int = 12,
        **kwargs,
    ):
        platform = digilent_arty.Platform(variant=variant, toolchain=toolchain)

        kwargs.setdefault("ident", "Mobius FPGA token sampler SoC")
        kwargs.setdefault("uart_baudrate", 115200)
        SoCCore.__init__(self, platform, sys_clk_freq, **kwargs)

        self.crg = _CRG(platform, sys_clk_freq)
        self.sampler = StochasticSampler(platform, k=k, sc_log2=sc_log2)
        self.leds = LedChaser(
            pads=platform.request_all("user_led"), sys_clk_freq=sys_clk_freq
        )


class _CRG(LiteXModule):
    """Minimal clock/reset generator: the 100 MHz input straight through a PLL.

    The sampler has no timing-critical paths beyond the UART divider, so there is
    no reason to over-constrain it.
    """

    def __init__(self, platform, sys_clk_freq):
        self.rst = Signal()
        self.cd_sys = ClockDomain()

        clk100 = platform.request("clk100")
        rst_n = platform.request("cpu_reset")

        self.pll = pll = S7PLL(speedgrade=-1)
        self.comb += pll.reset.eq(~rst_n | self.rst)
        pll.register_clkin(clk100, 100e6)
        pll.create_clkout(self.cd_sys, sys_clk_freq)
        platform.add_false_path_constraints(clk100, pll.clkin)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="LiteX SoC with the stochastic token sampler as a CSR peripheral."
    )
    parser.add_argument("--build", action="store_true", help="build the bitstream")
    parser.add_argument("--load", action="store_true", help="load over JTAG")
    parser.add_argument("--variant", default="a7-35", help="a7-35 or a7-100")
    parser.add_argument(
        "--toolchain",
        default="vivado",
        help="vivado, or f4pga/symbiflow for the open flow (support varies by LiteX version)",
    )
    parser.add_argument("--sys-clk-freq", type=float, default=100e6)
    parser.add_argument("--k", type=int, default=32, help="candidate window")
    parser.add_argument("--sc-log2", type=int, default=12, help="log2 stream length")
    builder_args(parser)
    soc_core_args(parser)
    args = parser.parse_args()

    soc = SamplerSoC(
        variant=args.variant,
        toolchain=args.toolchain,
        sys_clk_freq=args.sys_clk_freq,
        k=args.k,
        sc_log2=args.sc_log2,
        **soc_core_argdict(args),
    )
    builder = Builder(soc, **builder_argdict(args))
    builder.build(run=args.build)

    if args.load:
        prog = soc.platform.create_programmer()
        prog.load_bitstream(
            os.path.join(builder.gateware_dir, f"{soc.build_name}.bit")
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
