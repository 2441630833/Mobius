"""custom-fpga-mcp — MCP server for the FPGA token sampler.

Exposes the chain as discrete tools so the agent never has to guess a raw shell
command:

    fpga_detect  -> fpga_lint -> fpga_simulate -> fpga_synthesize
                 -> fpga_flash -> fpga_sample_token / fpga_sample_sequence

Design rules for every tool here:

* Never raise into the transport. A missing Docker daemon or an unplugged board
  is normal, expected state; it comes back as a structured result with a hint,
  because an exception traceback tells the agent nothing actionable.
* Never invent a number. Utilisation, timing, token ids and latencies are read
  from tool output or not reported at all.
* Say what is blocked and why. `fpga_detect` is the single source of truth for
  what this host can actually do.
"""

from __future__ import annotations

from typing import Sequence

from . import config, flash, report, sampling, sim, synth, toolchain

try:
    from fastmcp import FastMCP
except ImportError as exc:  # pragma: no cover - depends on venv
    raise SystemExit(
        "fastmcp is not installed in this interpreter.\n"
        "Run `npm run chip:setup` (or "
        "`chip-design/.venv/Scripts/python -m pip install -r chip-design/requirements.txt`) "
        "and start the server from chip-design/.venv."
    ) from exc


mcp = FastMCP(
    name="custom-fpga-mcp",
    instructions=(
        "Drives an Arty A7-35T FPGA as a physical token sampler for LLM "
        "generation: ring-oscillator thermal-noise TRNG -> stochastic-computing "
        "softmax -> inverse-CDF draw, with logits and tokens crossing over UART.\n\n"
        "Call fpga_detect first. It reports which of Yosys, openXC7, "
        "openFPGALoader, Verilator, the Python venv and the serial port are "
        "present, plus GNU make/g++ for Verilator --build, and every other "
        "tool's preconditions follow from it. When "
        "hardware is absent you can still do real work with fpga_lint and "
        "fpga_simulate. Docker is optional.\n\n"
        "Never report a token_id, bitstream path, or utilisation figure that did "
        "not come back from one of these tools."
    ),
)


# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------


@mcp.tool
def fpga_detect() -> dict:
    """Report what this host can actually do.

    Probes the vendored submodules, the Python venv, Verilator, GNU make, g++,
    Yosys, openXC7 (nextpnr-xilinx), Docker (optional fallback), openFPGALoader,
    the serial port and any built bitstream.
    Returns a capability map plus a list of concrete blockers. Start here --
    every other tool's failure mode is explained by this output.
    """
    return toolchain.detect().to_dict()


@mcp.tool
def fpga_paths() -> dict:
    """Show the resolved project paths.

    Useful when the server was spawned from an unexpected working directory and
    you need to confirm which checkout it is operating on.
    """
    return report.paths()


@mcp.tool
def fpga_setup() -> dict:
    """Explain how to finish setting up the toolchain.

    Deliberately does not install anything: pulling a multi-GB Docker image or
    building a venv from inside a tool call would block the agent for minutes
    with no progress output. This returns the exact commands to run instead.
    """
    return report.setup_advice()


# ---------------------------------------------------------------------------
# RTL verification
# ---------------------------------------------------------------------------


@mcp.tool
def fpga_lint(top: str = config.TOP_MODULE) -> dict:
    """Lint the RTL with Verilator.

    Catches width mismatches, inferred latches, incomplete case statements and
    combinational loops. Fast, needs no board, and should be clean before any
    synthesis run. Reports error and warning counts with the offending lines.
    """
    return sim.lint(top=top)


@mcp.tool
def fpga_simulate(samples: int = 2000, seed: int = 1) -> dict:
    """Simulate the sampler and check its output distribution.

    Builds the Verilator testbench, drives real protocol frames into the top
    level at an accelerated baud rate, and compares the resulting token
    histogram against the distribution the RTL is specified to implement.

    This is the meaningful pre-silicon test: framing, CRC, logit loading and the
    exponent table are all exercised, and a statistically wrong sampler fails
    here even though it answers every frame. No hardware required.

    Args:
        samples: tokens to draw. Fewer is faster but noisier; below ~500 the
            distribution check loses the ability to detect a wrong model.
        seed: host-side seed for the stimulus, for reproducible runs.
    """
    return sim.simulate(samples=samples, seed=seed)


# ---------------------------------------------------------------------------
# Build and program
# ---------------------------------------------------------------------------


@mcp.tool
def fpga_synthesize(pull: bool = True, timeout_s: float = 1800.0) -> dict:
    """Synthesize the RTL to an Arty A7-35T bitstream.

    Preferred path is native: Yosys (OSS CAD Suite) + nextpnr-xilinx / prjxray
    (openXC7) on the host. Docker F4PGA is used only when that host toolchain
    is incomplete.

    Returns the bitstream path, its size and the cell counts parsed from the
    Yosys log. Utilisation figures are read from that log, never estimated.

    Args:
        pull: if falling back to Docker, pull the F4PGA image when missing.
        timeout_s: hard limit for the synth run.
    """
    return synth.synthesize(timeout=timeout_s, pull=pull)


@mcp.tool
def fpga_clean() -> dict:
    """Delete the build directory (bitstream, logs, Verilator objects)."""
    return synth.clean()


@mcp.tool
def fpga_flash(bitstream: str | None = None, persist: bool = False) -> dict:
    """Program the Arty A7-35T over JTAG with openFPGALoader.

    Runs as a host binary: forwarding the FTDI interface into a container needs
    privileged USB passthrough, which does not work on Docker Desktop.

    Args:
        bitstream: path to a .bit file. Defaults to the last synthesized one.
        persist: write the SPI flash so the design survives a power cycle.
            Slower and wears the flash; leave false while iterating.
    """
    return flash.flash(bitstream=bitstream, sram=not persist)


@mcp.tool
def fpga_list_cables() -> dict:
    """Enumerate attached JTAG probes.

    The fastest way to tell a cable or driver problem apart from a bitstream
    problem when fpga_flash fails.
    """
    return flash.list_cables()


# ---------------------------------------------------------------------------
# Sampling
# ---------------------------------------------------------------------------


@mcp.tool
def fpga_device_info() -> dict:
    """Identify the bitstream currently running on the board.

    Reports the firmware version, the candidate window K, the logit format, the
    stochastic stream length and the TRNG health flag. Worth calling after a
    flash to confirm the host and device agree on K -- a mismatch silently
    corrupts every sample.
    """
    return sampling.device_info()


@mcp.tool
def fpga_sample_token(logits: Sequence[float]) -> dict:
    """Sample one token on the FPGA from a logit vector.

    The board runs the physical draw: thermal-noise TRNG bits feed a
    stochastic-computing softmax, and the accumulated weights are cut by a
    hardware inverse-CDF scan. Send at most K logits (see fpga_device_info);
    for a real vocabulary, send a top-K slice and map the returned index back
    to a vocabulary id on the host.

    Alongside the token this returns the reference model's probability for it,
    the raw draw and total weight, and the TRNG/fallback flags -- so a wrong
    answer is detectable rather than merely plausible.

    Args:
        logits: natural-log-scale logits, quantised to signed Q8.8 on the wire.
    """
    return sampling.sample_token(list(logits))


@mcp.tool
def fpga_sample_sequence(steps: Sequence[Sequence[float]]) -> dict:
    """Sample one token per step over a single open serial link.

    This is the generation loop: the host produces logits for step t, the FPGA
    draws a token, the host appends it and produces step t+1. Batching the steps
    keeps the port open, which dominates per-token latency.

    Args:
        steps: one logit vector per generation step.
    """
    return sampling.sample_sequence([list(s) for s in steps])


@mcp.tool
def fpga_verify_distribution(logits: Sequence[float], samples: int = 400) -> dict:
    """Draw repeatedly from one logit vector and test the histogram.

    The acceptance test for a freshly flashed board. Computes a Pearson
    chi-square against the quantised-softmax model the RTL implements and
    reports the p-value, total variation distance and an interpretation.

    Use this rather than eyeballing a few tokens: a sampler with swapped logit
    bytes or a dead entropy source answers every frame and only fails here.

    Args:
        logits: the fixed logit vector to sample from. Use an uneven one --
            a flat vector passes even when the sampler is wrong.
        samples: draws to collect. At least ~200 for a usable p-value.
    """
    return sampling.verify_distribution(list(logits), samples=samples)


@mcp.tool
def fpga_trng_entropy(n_bytes: int = 256) -> dict:
    """Capture whitened TRNG bytes and run the online health tests.

    Monobit, serial-correlation and longest-run tests plus a min-entropy
    estimate. Prove the entropy source is alive with this before trusting any
    sampled token: a stuck oscillator makes the sampler deterministic without
    making it fail.

    These are health tests, not a NIST SP 800-90B assessment, and the result
    says so.

    Args:
        n_bytes: bytes to capture (max 256 per request). Von Neumann debiasing
            discards most raw bits, so a full request takes a few seconds.
    """
    return sampling.trng_entropy(n_bytes=n_bytes)


@mcp.tool
def fpga_self_test(samples: int = 200) -> dict:
    """Run the whole hardware chain end to end.

    Identify the bitstream, check entropy health, draw a single token, then
    verify a distribution. Stops at the first hard failure so the report names
    the actual blocker instead of a cascade of symptoms.

    Args:
        samples: draws for the distribution stage.
    """
    return sampling.self_test(samples=samples)


@mcp.tool
def fpga_close_link() -> dict:
    """Release the cached serial port.

    Call this before flashing or before opening a serial terminal: openFPGALoader
    cannot claim the FTDI interface while the port is held open.
    """
    return sampling.close_link()


# ---------------------------------------------------------------------------
# Host-side reference model
# ---------------------------------------------------------------------------


@mcp.tool
def fpga_reference_distribution(logits: Sequence[float]) -> dict:
    """Compute what the hardware *should* sample, without touching hardware.

    Returns the quantised-softmax distribution the RTL implements next to exact
    float softmax, so you can see how much the Q8.8 logits and the Q0.16
    exponent table cost before blaming the board. Also works with no board
    attached.

    Args:
        logits: natural-log-scale logits.
    """
    return report.reference_distribution(list(logits))


def main() -> None:
    """stdio entry point used by the IDE's MCP client."""
    mcp.run()


if __name__ == "__main__":
    main()
