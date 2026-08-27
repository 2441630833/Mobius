"""Verilator lint and simulation.

Simulation matters more than usual here: the sampler is a *statistical*
circuit, so "it compiles" says nothing. The testbench drives real protocol
frames into the top level at an accelerated baud rate and checks that the
resulting token histogram matches the distribution the RTL is supposed to
implement. That catches CRC/framing bugs, logit-loading off-by-ones and
exponent-table errors before a board is ever involved.
"""

from __future__ import annotations

import os
import re
from pathlib import Path

from . import config
from .toolchain import probe_gxx, probe_make, probe_verilator, run

# Style warnings that are noise for hand-written RTL of this shape. Anything
# that can indicate a real bug (WIDTH, LATCH, CASEINCOMPLETE, BLKSEQ, ...) is
# deliberately left enabled.
LINT_WAIVERS = [
    "-Wno-DECLFILENAME",
    "-Wno-UNUSEDSIGNAL",
    "-Wno-UNUSEDPARAM",
    "-Wno-VARHIDDEN",
    "-Wno-PINCONNECTEMPTY",
]

# Accelerated UART for simulation: 4 clocks per bit instead of 868, which turns
# a multi-thousand-sample histogram from hours into seconds. The divider logic
# under test is identical.
SIM_BAUD = 25_000_000


def _make_path(p: Path | str) -> str:
    """Forward slashes so GNU make + sh.exe do not eat Windows backslashes."""
    return str(p).replace("\\", "/")


def _sources() -> list[str]:
    return [str(p) for p in config.rtl_sources()]


def lint(top: str = config.TOP_MODULE) -> dict:
    v = probe_verilator()
    if not v.available:
        return {
            "ok": False,
            "stage": "tool",
            "error": v.detail,
            "hint": "Run npm run chip:cad-suite (bundles YosysHQ OSS CAD Suite / Verilator) or set VERILATOR_BIN.",
        }

    missing = [s for s in _sources() if not Path(s).is_file()]
    if missing:
        return {"ok": False, "stage": "sources", "error": f"missing RTL: {missing}"}

    cmd = [
        v.path or "verilator",
        "--lint-only",
        "-Wall",
        "-Wno-fatal",
        *LINT_WAIVERS,
        "-DSIMULATION",
        "--top-module",
        top,
        *_sources(),
    ]
    code, out, err = run(cmd, timeout=300)
    combined = (out + "\n" + err).strip()

    errors = [l for l in combined.splitlines() if "%Error" in l and "Exiting due to" not in l]
    warnings = [l for l in combined.splitlines() if "%Warning" in l]

    return {
        "ok": code == 0 and not errors,
        "stage": "lint",
        "exit_code": code,
        "error_count": len(errors),
        "warning_count": len(warnings),
        "errors": errors[:40],
        "warnings": warnings[:40],
        "verilator": v.version,
    }


def simulate(samples: int = 2000, seed: int = 1, timeout: float = 900.0) -> dict:
    """Build and run the statistical testbench.

    Returns the histogram, the expected distribution and the measured deviation
    so the caller can judge the result instead of trusting a bare pass/fail.
    """
    v = probe_verilator()
    if not v.available:
        return {
            "ok": False,
            "stage": "tool",
            "error": v.detail,
            "hint": "Run npm run chip:cad-suite or set VERILATOR_BIN.",
        }

    make = probe_make()
    gxx = probe_gxx()
    if not make.available or not gxx.available:
        missing = [p.name for p in (make, gxx) if not p.available]
        return {
            "ok": False,
            "stage": "tool",
            "error": "verilator --build needs " + " and ".join(missing),
            "hint": "Run npm run chip:mingw (portable GNU make + g++ into tools/mingw/).",
            "make": make.to_dict(),
            "g++": gxx.to_dict(),
        }

    tb = config.sim_dir() / "tb_sampler.cpp"
    if not tb.is_file():
        return {"ok": False, "stage": "sources", "error": f"missing testbench: {tb}"}

    obj_dir = config.build_dir() / "verilator"
    obj_dir.mkdir(parents=True, exist_ok=True)

    exe_name = "tb_sampler.exe" if os.name == "nt" else "tb_sampler"
    build_cmd = [
        v.path or "verilator",
        "--cc",
        "--exe",
        "--build",
        "--compiler",
        "gcc",
        "-j",
        "0",
        "-DSIMULATION",
        f"-GBAUD={SIM_BAUD}",
        "--top-module",
        config.TOP_MODULE,
        "--Mdir",
        _make_path(obj_dir),
        "-o",
        "tb_sampler",
        *LINT_WAIVERS,
        "-Wno-fatal",
        *[_make_path(s) for s in _sources()],
        _make_path(tb),
    ]
    code, out, err = run(build_cmd, timeout=timeout, cwd=config.chip_dir())
    if code != 0:
        combined_build = (out + "\n" + err).strip()
        hint = None
        if "make" in combined_build.lower() and (
            "not recognized" in combined_build.lower()
            or "不是内部" in combined_build
            or "exited with 1" in combined_build.lower()
        ):
            hint = (
                "Verilator ran, but --cc --build still failed. "
                "Run npm run chip:mingw so make + g++ are on PATH, then retry fpga_simulate."
            )
        result = {
            "ok": False,
            "stage": "build",
            "error": f"verilator build failed (exit {code})",
            "output": combined_build[-4000:],
        }
        if hint:
            result["hint"] = hint
        return result

    exe = obj_dir / exe_name
    if not exe.is_file():
        alt = obj_dir / "tb_sampler"
        exe = alt if alt.is_file() else exe
    if not exe.is_file():
        return {"ok": False, "stage": "build", "error": f"simulator binary not found in {obj_dir}"}

    code, out, err = run([str(exe), str(samples), str(seed)], timeout=timeout, cwd=config.chip_dir())
    combined = (out + "\n" + err).strip()
    if code != 0:
        return {
            "ok": False,
            "stage": "run",
            "error": f"simulation exited {code}",
            "output": combined[-4000:],
        }

    return _parse_sim_output(combined, samples)


def _parse_sim_output(text: str, samples: int) -> dict:
    """Read the testbench's machine-readable lines.

    The TB prints its own verdict; we report the numbers alongside it so a
    marginal result is visible rather than hidden behind PASS/FAIL.
    """
    counts: dict[int, int] = {}
    expected: dict[int, float] = {}
    metrics: dict[str, float] = {}
    verdict = None

    for line in text.splitlines():
        line = line.strip()
        if m := re.match(r"^TOKEN_COUNT\s+(\d+)\s+(\d+)$", line):
            counts[int(m.group(1))] = int(m.group(2))
        elif m := re.match(r"^EXPECTED\s+(\d+)\s+([0-9.eE+-]+)$", line):
            expected[int(m.group(1))] = float(m.group(2))
        elif m := re.match(r"^(MAXDEV|CHI2|SAMPLES)\s+([0-9.eE+-]+)$", line):
            metrics[m.group(1).lower()] = float(m.group(2))
        elif m := re.match(r"^RESULT\s+(PASS|FAIL)$", line):
            verdict = m.group(1)

    return {
        "ok": verdict == "PASS",
        "stage": "run",
        "verdict": verdict or "UNKNOWN",
        "samples_requested": samples,
        "samples_observed": int(metrics.get("samples", 0)),
        "max_deviation": metrics.get("maxdev"),
        "chi_square": metrics.get("chi2"),
        "histogram": dict(sorted(counts.items())),
        "expected": dict(sorted(expected.items())),
        "output": text[-3000:],
    }
