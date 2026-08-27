"""Command-line access to the same operations the MCP tools expose.

Two reasons this exists next to the server:

* The setup script and CI need to check the toolchain without speaking MCP.
* When something is broken, running `python -m custom_fpga_mcp detect` in a
  terminal is a far shorter feedback loop than debugging through the IDE.

Subcommands that need no hardware (detect, paths, reference) also work on a bare
system interpreter with no venv, so they stay usable when the venv is the thing
that is broken. `serve` is the only subcommand that requires fastmcp.
"""

from __future__ import annotations

import argparse
import json
import sys
from typing import Any

from . import config


def _emit(payload: Any) -> int:
    """Print a result as JSON and derive the exit code from it."""
    print(json.dumps(payload, indent=2, default=str))
    if isinstance(payload, dict) and payload.get("ok") is False:
        return 1
    return 0


def _parse_logits(text: str) -> list[float]:
    """Accept a JSON array or a comma/space separated list."""
    stripped = text.strip()
    if stripped.startswith("["):
        return [float(v) for v in json.loads(stripped)]
    return [float(part) for part in stripped.replace(",", " ").split()]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="custom-fpga-mcp",
        description="FPGA token sampler: synthesis, flashing and physical sampling.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("serve", help="run the MCP server on stdio (needs fastmcp)")
    sub.add_parser("detect", help="report toolchain availability and blockers")
    sub.add_parser("paths", help="show resolved project paths")
    sub.add_parser("setup", help="list the commands still needed to finish setup")

    p_test = sub.add_parser("test", help="run the host-side unit tests (no hardware)")
    p_test.add_argument("-v", "--verbose", action="store_true")
    p_test.add_argument("-k", dest="pattern", default=None, help="only tests matching this substring")

    p_lint = sub.add_parser("lint", help="Verilator lint pass over the RTL")
    p_lint.add_argument("--top", default=config.TOP_MODULE)

    p_sim = sub.add_parser("simulate", help="run the statistical testbench")
    p_sim.add_argument("--samples", type=int, default=2000)
    p_sim.add_argument("--seed", type=int, default=1)

    p_synth = sub.add_parser("synthesize", help="native Yosys + openXC7 synthesis (Docker fallback)")
    p_synth.add_argument("--no-pull", action="store_true", help="fail instead of pulling the image")
    p_synth.add_argument("--timeout", type=float, default=1800.0)

    sub.add_parser("clean", help="delete the build directory")

    p_flash = sub.add_parser("flash", help="program the board over JTAG")
    p_flash.add_argument("bitstream", nargs="?", default=None)
    p_flash.add_argument("--persist", action="store_true", help="write SPI flash instead of SRAM")

    sub.add_parser("cables", help="enumerate attached JTAG probes")
    sub.add_parser("info", help="identify the running bitstream")
    sub.add_parser("close", help="release the cached UART link")

    p_seq = sub.add_parser("sequence", help="sample one token per logit vector")
    p_seq.add_argument("steps", help="JSON array of logit vectors")

    p_sample = sub.add_parser("sample", help="draw one token from a logit vector")
    p_sample.add_argument("logits", help="JSON array or comma/space separated floats")

    p_verify = sub.add_parser("verify", help="sample repeatedly and test the histogram")
    p_verify.add_argument("logits")
    p_verify.add_argument("--samples", type=int, default=400)

    p_entropy = sub.add_parser("entropy", help="capture TRNG bytes and run health tests")
    p_entropy.add_argument("--bytes", type=int, default=256, dest="n_bytes")

    p_self = sub.add_parser("self-test", help="end-to-end hardware check")
    p_self.add_argument("--samples", type=int, default=200)

    p_ref = sub.add_parser(
        "reference", help="hardware distribution model, no board needed"
    )
    p_ref.add_argument("logits")

    for name in ("info", "sample", "verify", "entropy", "self-test", "sequence"):
        action = sub.choices[name]
        action.add_argument("--port", default=None, help="serial port (default: auto-detect)")
        action.add_argument("--baud", type=int, default=None)

    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    command = args.command

    # Imported lazily so `detect` still runs when a dependency is missing --
    # which is exactly when you need `detect` most.
    if command == "serve":
        from .server import main as serve_main

        serve_main()
        return 0

    if command == "detect":
        from .toolchain import detect

        return _emit(detect().to_dict())

    if command == "paths":
        from . import report

        return _emit(report.paths())

    if command == "setup":
        from . import report

        return _emit(report.setup_advice())

    if command == "test":
        # unittest prints its own report, so this is the one subcommand that does
        # not emit JSON. Wrapping it would hide the failure detail that matters.
        import unittest

        tests_dir = config.tests_dir()
        if not tests_dir.is_dir():
            print(f"no tests directory at {tests_dir}", file=sys.stderr)
            return 2
        loader = unittest.TestLoader()
        if args.pattern:
            loader.testNamePatterns = [f"*{args.pattern}*"]
        suite = loader.discover(str(tests_dir), top_level_dir=str(tests_dir))
        runner = unittest.TextTestRunner(verbosity=2 if args.verbose else 1)
        return 0 if runner.run(suite).wasSuccessful() else 1

    if command in ("lint", "simulate"):
        from . import sim

        if command == "lint":
            return _emit(sim.lint(top=args.top))
        return _emit(sim.simulate(samples=args.samples, seed=args.seed))

    if command in ("synthesize", "clean"):
        from . import synth

        if command == "clean":
            return _emit(synth.clean())
        return _emit(synth.synthesize(timeout=args.timeout, pull=not args.no_pull))

    if command in ("flash", "cables"):
        from . import flash as flash_mod

        if command == "cables":
            return _emit(flash_mod.list_cables())
        return _emit(flash_mod.flash(bitstream=args.bitstream, sram=not args.persist))

    if command == "reference":
        from . import report

        return _emit(report.reference_distribution(_parse_logits(args.logits)))

    # Everything below needs the serial link.
    from . import sampling

    if command == "close":
        return _emit(sampling.close_link())
    if command == "info":
        return _emit(sampling.device_info(port=args.port, baud=args.baud))
    if command == "sequence":
        return _emit(
            sampling.sample_sequence(json.loads(args.steps), port=args.port, baud=args.baud)
        )
    if command == "sample":
        return _emit(
            sampling.sample_token(_parse_logits(args.logits), port=args.port, baud=args.baud)
        )
    if command == "verify":
        return _emit(
            sampling.verify_distribution(
                _parse_logits(args.logits), samples=args.samples, port=args.port, baud=args.baud
            )
        )
    if command == "entropy":
        return _emit(sampling.trng_entropy(n_bytes=args.n_bytes, port=args.port, baud=args.baud))
    if command == "self-test":
        return _emit(sampling.self_test(port=args.port, baud=args.baud, samples=args.samples))

    print(f"unhandled command: {command}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
