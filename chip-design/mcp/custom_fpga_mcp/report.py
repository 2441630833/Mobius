"""Hardware-free reports shared by the MCP server and the CLI.

Kept out of ``server.py`` on purpose: importing that module requires fastmcp,
and these are exactly the things you need when the venv is what is broken.
Stdlib only, no serial, no Docker.
"""

from __future__ import annotations

from typing import Sequence

from . import config, protocol, toolchain


def paths() -> dict:
    """Resolved project paths and board settings."""
    return {
        "repo_root": str(config.repo_root()),
        "chip_dir": str(config.chip_dir()),
        "rtl_dir": str(config.rtl_dir()),
        "rtl_sources": [str(p) for p in config.rtl_sources()],
        "sim_dir": str(config.sim_dir()),
        "soc_dir": str(config.soc_dir()),
        "constraints_dir": str(config.constraints_dir()),
        "build_dir": str(config.build_dir()),
        "vendor_dir": str(config.vendor_dir()),
        "venv_python": str(config.venv_python()),
        "bitstream": str(config.bitstream_path()),
        "cad_suite": str(config.cad_suite_dir() or ""),
        "openxc7": str(config.openxc7_dir() or ""),
        "mingw": str(config.mingw_dir() or ""),
        "board": config.BOARD,
        "part": config.PART,
        "f4pga_image": config.F4PGA_IMAGE,
        "top_module": config.TOP_MODULE,
        "baud": config.DEFAULT_BAUD,
    }


def setup_advice() -> dict:
    """What is still missing, and the exact command that fixes each item.

    Deliberately advisory: pulling a multi-GB image or building a venv from
    inside a tool call would block for minutes with no progress output.
    """
    report = toolchain.detect()
    data = report.to_dict()

    def have(name: str) -> bool:
        probe = report.get(name)
        return bool(probe and probe.available)

    commands: list[dict] = []
    if not have("vendor"):
        commands.append(
            {
                "why": "vendored upstream sources are not checked out",
                "run": "git submodule update --init --recursive --depth 1",
            }
        )
    if not have("python-venv"):
        commands.append(
            {
                "why": "the Python venv with fastmcp + pyserial is missing or incomplete",
                "run": "npm run chip:setup",
            }
        )
    if not have("yosys"):
        commands.append(
            {
                "why": "native synthesis needs Yosys (OSS CAD Suite)",
                "run": "npm run chip:cad-suite",
            }
        )
    if not have("nextpnr-xilinx"):
        commands.append(
            {
                "why": "native Xilinx 7-series P&R needs openXC7 (nextpnr-xilinx + chipdb). Docker is not required.",
                "run": "npm run chip:openxc7",
            }
        )
    if not have("openFPGALoader"):
        commands.append(
            {
                "why": "JTAG programming must run on the host, not in Docker",
                "run": "npm run chip:cad-suite (bundles openFPGALoader) or set OPENFPGALOADER_BIN",
            }
        )
    if not have("verilator"):
        commands.append(
            {
                "why": "lint and simulation need Verilator (this is how you work without a board)",
                "run": "npm run chip:cad-suite (or set VERILATOR_BIN)",
            }
        )
    if have("verilator") and (not have("make") or not have("g++")):
        commands.append(
            {
                "why": "fpga_simulate --build needs GNU make + g++ (Windows OSS CAD Suite does not ship them)",
                "run": "npm run chip:mingw",
            }
        )

    return {
        "ok": not commands,
        "outstanding": commands,
        "capabilities": data["capabilities"],
        "blockers": data["blockers"],
    }


def reference_distribution(logits: Sequence[float]) -> dict:
    """The distribution the hardware implements, next to exact softmax.

    Quantifies what Q8.8 logits and the Q0.16 exponent table cost, so
    approximation error is not mistaken for a hardware fault.
    """
    values = list(logits)
    if not values:
        return {"ok": False, "error": "logits vector is empty"}

    model = protocol.reference_distribution(values)
    exact = protocol.softmax(values)
    deviations = [abs(a - b) for a, b in zip(model, exact)]
    return {
        "ok": True,
        "candidate_window": protocol.DEFAULT_K,
        "quantised_q88_logits": [protocol.float_to_q88(v) for v in values],
        "hardware_model": [round(p, 8) for p in model],
        "exact_softmax": [round(p, 8) for p in exact],
        "max_abs_deviation": round(max(deviations), 8) if deviations else 0.0,
        "total_variation_distance": round(sum(deviations) / 2, 8),
        "unreachable_candidates": [i for i, p in enumerate(model) if p == 0.0],
        "note": (
            "Candidates more than ~16 nats below the maximum have probability "
            "exactly 0 in hardware: the Q0.16 exponent constants round to zero "
            "there. Rescale the logits if that matters."
        ),
    }
