"""Bitstream loading with openFPGALoader.

Runs on the host, not in Docker: forwarding the Arty's FTDI JTAG interface into
a container needs privileged USB passthrough, which does not work at all on
Docker Desktop for Windows/macOS.
"""

from __future__ import annotations

from pathlib import Path

from . import config
from .toolchain import probe_openfpgaloader, run


def flash(bitstream: str | None = None, sram: bool = True, timeout: float = 300.0) -> dict:
    """Load a bitstream onto the Arty A7-35T.

    `sram=True` is volatile (lost on power cycle) and is what you want while
    iterating; `sram=False` writes the SPI flash so the design survives a
    reboot but takes far longer and wears the flash.
    """
    loader = probe_openfpgaloader()
    if not loader.available:
        return {
            "ok": False,
            "stage": "tool",
            "error": loader.detail,
            "hint": (
                "Install openFPGALoader on the host (scoop/apt/brew or a release binary) "
                "and put it on PATH, or set OPENFPGALOADER_BIN."
            ),
        }

    bit = Path(bitstream) if bitstream else config.bitstream_path()
    if not bit.is_file():
        return {
            "ok": False,
            "stage": "bitstream",
            "error": f"no bitstream at {bit}",
            "hint": "Run fpga_synthesize first.",
        }

    cmd = [loader.path or "openFPGALoader", "-b", config.BOARD]
    if not sram:
        cmd.append("-f")
    cmd.append(str(bit))

    code, out, err = run(cmd, timeout=timeout)
    combined = (out + "\n" + err).strip()

    if code == -1:
        return {"ok": False, "stage": "tool", "error": combined}
    if code == -2:
        return {"ok": False, "stage": "flash", "error": combined, "hint": "Is the board powered and the JTAG cable connected?"}
    if code != 0:
        return {
            "ok": False,
            "stage": "flash",
            "error": f"openFPGALoader exited {code}",
            "output": combined[-4000:],
            "hint": (
                "Common causes: board not connected, another process holding the FTDI "
                "interface (close any serial terminal), or missing USB driver/udev rule."
            ),
        }

    return {
        "ok": True,
        "stage": "flash",
        "bitstream": str(bit),
        "mode": "sram" if sram else "spi-flash",
        "board": config.BOARD,
        "output": combined[-2000:],
    }


def list_cables(timeout: float = 60.0) -> dict:
    """Enumerate JTAG probes — the quickest way to tell a cable problem apart
    from a bitstream problem."""
    loader = probe_openfpgaloader()
    if not loader.available:
        return {"ok": False, "error": loader.detail}
    code, out, err = run([loader.path or "openFPGALoader", "--detect"], timeout=timeout)
    return {
        "ok": code == 0,
        "exit_code": code,
        "output": ((out + "\n" + err).strip())[-2000:],
    }
