"""Closed-loop latency/throughput model for the FPGA token sampler.

Redwood-style roofline, applied to the sampling loop: write down the
theoretical ceiling and the bottleneck *before* touching hardware, then let
measurements calibrate the model. For this loop the "memory" of the system is
the UART line, and one token costs

    T_step = T_tx(window) + T_stream(FPGA) + T_rx(token)

because the device cannot start the stochastic stream until the whole logit
window has arrived and the host cannot start the next step until the token
frame is back. No work or traffic is hidden across those boundaries — exactly
the Redwood paper's per-operator roofline rule ("memory and compute may overlap
within one operator, but no work is hidden across operator boundaries"), which
is also why it concludes that closing the gap to the memory roofline is future
work. Here the roofline says the loop is UART-bound, and the lever is K: every
candidate costs 2 wire bytes each way, so halving K almost halves T_step.

The wire byte counts are derived from ``protocol.build_frame`` /
``protocol.encode_sample``, so if the framing ever drifts this module fails its
tests instead of silently reporting a wrong ceiling.

Deliberately stdlib-only: imported by the unit tests, which run against a bare
system interpreter with no venv.
"""

from __future__ import annotations

import os

from . import config, protocol

# Real hardware divides the 100 MHz crystal by 2 (see sampler_uart_top.v) and
# runs the whole design at 50 MHz. Simulation uses SYS_HZ == CLK_HZ, but the
# model describes hardware, so it assumes 50 MHz unless overridden.
SYSTEM_CLK_HZ = float(os.environ.get("FPGA_SYS_CLK_HZ", "50_000_000"))

# 8N1 UART: one start bit + 8 data + one stop bit per byte.
BITS_PER_BYTE = 10

# 'T' reply: SOF + RSP + LEN(2) + payload(11) + CRC. The payload width is the
# RTL's resp_len for RSP_TOKEN (see sampler_uart_top.v, R_WAIT state) and is
# mirrored by parse_sample, which requires exactly 11 payload bytes.
TOKEN_REPLY_FRAME_BYTES = 5 + 11

# Sensitivity table shown when the caller does not pick one window size.
TABLE_K_DEFAULT = (8, 16, 32, 64)


def sample_frame_bytes(k: int) -> int:
    """Full host->device frame length for a K-logit window, from the codec.

    Using the actual encoder keeps this model locked to the wire format:
    len(frame) == 5 + 2*K is asserted in tests, so a framing change moves the
    roofline with it instead of invalidating it silently.
    """
    if not 1 <= k <= 64:
        raise ValueError(f"window K must be 1..64, got {k}")
    return len(protocol.encode_sample([0.0] * k, k=k))


def tx_ms(k: int, baud: int) -> float:
    """Wire time for one sample frame (the whole logit window)."""
    return sample_frame_bytes(k) * BITS_PER_BYTE / baud * 1000.0


def stream_ms(sc_log2: int, clk_hz: float = SYSTEM_CLK_HZ) -> float:
    """FPGA stochastic-stream time: ~2^SC_LOG2 cycles plus the entropy wait."""
    return (1 << sc_log2) / clk_hz * 1000.0


def rx_ms(baud: int) -> float:
    """Wire time for the token reply frame."""
    return TOKEN_REPLY_FRAME_BYTES * BITS_PER_BYTE / baud * 1000.0


def step_budget(
    k: int = protocol.DEFAULT_K,
    baud: int | None = None,
    sc_log2: int = protocol.DEFAULT_SC_LOG2,
    clk_hz: float = SYSTEM_CLK_HZ,
    host_overhead_ms: float = 0.0,
) -> dict:
    """Predicted per-token budget for the closed loop.

    Stages are serial (see module docstring): the attainable time is the sum of
    the stage maxima, not the max. Values are estimates — the model is meant to
    be calibrated against fpga_sample_token's latency_ms /
    fpga_sample_sequence's mean_ms_per_token, never quoted as a measurement.
    """
    if baud is None:
        baud = config.DEFAULT_BAUD
    if not 1 <= baud <= 12_000_000:
        raise ValueError(f"baud must be 1..12000000, got {baud}")

    t_tx = tx_ms(k, baud)
    t_stream = stream_ms(sc_log2, clk_hz)
    t_rx = rx_ms(baud)
    t_total = t_tx + t_stream + t_rx + host_overhead_ms
    parts = [
        ("uart_tx", t_tx),
        ("fpga_stream", t_stream),
        ("uart_rx", t_rx),
        ("host", host_overhead_ms),
    ]
    bottleneck = max(parts, key=lambda p: p[1])[0]
    return {
        "ok": True,
        "stage": "model",
        "k": k,
        "baud": baud,
        "sc_log2": sc_log2,
        "clk_hz": clk_hz,
        "sample_frame_bytes": sample_frame_bytes(k),
        "token_frame_bytes": TOKEN_REPLY_FRAME_BYTES,
        "tx_ms": round(t_tx, 4),
        "stream_ms": round(t_stream, 4),
        "rx_ms": round(t_rx, 4),
        "host_ms": round(host_overhead_ms, 4),
        "total_ms": round(t_total, 4),
        "tokens_per_s": round(1000.0 / t_total, 1) if t_total > 0 else None,
        "bottleneck": bottleneck,
        "serial_stages": True,
        "note": (
            "Model estimate, not a measurement. UART stages dominate at these "
            "baud rates, so the FPGA stream time is almost never the limit; "
            "K is the lever (2 wire bytes per candidate each way)."
        ),
    }


def step_total_ms(
    k: int = protocol.DEFAULT_K,
    baud: int | None = None,
    sc_log2: int = protocol.DEFAULT_SC_LOG2,
    clk_hz: float = SYSTEM_CLK_HZ,
) -> float:
    """Convenience: just the predicted per-token wall time, for sampling layers."""
    return step_budget(k=k, baud=baud, sc_log2=sc_log2, clk_hz=clk_hz)["total_ms"]


def table(
    k: int | None = None,
    baud: int | None = None,
    sc_log2: int = protocol.DEFAULT_SC_LOG2,
    host_overhead_ms: float = 0.0,
) -> dict:
    """Budget rows for one K or the default sensitivity sweep.

    The sweep is the actionable output for an agent picking a window size: at
    the default 115200 baud the difference between K=8 and K=64 is roughly 5x
    throughput, which is usually worth far more than the tail probability K
    buys.
    """
    if baud is None:
        baud = config.DEFAULT_BAUD
    if k is None:
        rows = [step_budget(k=kk, baud=baud, sc_log2=sc_log2, host_overhead_ms=host_overhead_ms) for kk in TABLE_K_DEFAULT]
    else:
        rows = [step_budget(k=k, baud=baud, sc_log2=sc_log2, host_overhead_ms=host_overhead_ms)]
    return {
        "ok": True,
        "stage": "model",
        "baud": baud,
        "sc_log2": sc_log2,
        "host_overhead_ms": host_overhead_ms,
        "rows": rows,
        "assumptions": {
            "clk_hz": SYSTEM_CLK_HZ,
            "bits_per_byte": BITS_PER_BYTE,
            "logit_bytes": protocol.LOGIT_FRAC_BITS * 2 // 8,
            "serial_stages": True,
        },
        "note": (
            "Redwood-style roofline: paper ceiling first, then calibrate with "
            "measured latency_ms from fpga_sample_token / fpga_sample_sequence."
        ),
    }
