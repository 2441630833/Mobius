"""Toolchain probing.

Every FPGA step here depends on something that is routinely missing: Docker,
a JTAG programmer, a Verilator build, an attached board. The agent has to be
able to tell "not installed" from "installed but broken", so detection returns
a structured report and never raises.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

from . import config


def run(
    cmd: list[str],
    timeout: float = 60.0,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
) -> tuple[int, str, str]:
    """Run a command, capturing output. Never raises for a non-zero exit.

    Returns (-1, "", reason) when the binary is missing and (-2, ...) on
    timeout, so callers can distinguish those from a real tool failure.
    """
    merged = {**os.environ, **config.tool_env(cmd[0] if cmd else None), **(env or {})}
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=str(cwd) if cwd else None,
            env=merged,
            encoding="utf-8",
            errors="replace",
        )
        return proc.returncode, proc.stdout or "", proc.stderr or ""
    except FileNotFoundError:
        return -1, "", f"{cmd[0]} not found on PATH"
    except subprocess.TimeoutExpired:
        return -2, "", f"{cmd[0]} timed out after {timeout:.0f}s"
    except OSError as exc:  # permission, exec format, ...
        return -1, "", f"{cmd[0]} could not be executed: {exc}"


def _first_line(text: str) -> str:
    for line in text.splitlines():
        line = line.strip()
        if line:
            return line
    return ""


@dataclass
class Probe:
    name: str
    available: bool
    detail: str = ""
    path: str | None = None
    version: str = ""
    optional: bool = False

    def to_dict(self) -> dict:
        data = {
            "name": self.name,
            "available": self.available,
            "path": self.path,
            "version": self.version,
            "detail": self.detail,
        }
        if self.optional:
            data["optional"] = True
        return data


def probe_python_env() -> Probe:
    """Is the chip-design venv built, and does it have what we need?"""
    vp = config.venv_python()
    if not vp.is_file():
        return Probe(
            "python-venv",
            False,
            detail=f"no venv at {config.venv_dir()} — run: npm run chip:setup",
        )
    code, out, err = run([str(vp), "-c", "import fastmcp, serial; print(fastmcp.__version__)"], timeout=60)
    if code != 0:
        missing = "fastmcp/pyserial"
        return Probe(
            "python-venv",
            False,
            path=str(vp),
            detail=f"venv exists but {missing} import failed — run: npm run chip:setup ({_first_line(err) or code})",
        )
    return Probe("python-venv", True, path=str(vp), version=_first_line(out), detail="fastmcp + pyserial importable")


def probe_docker() -> Probe:
    tool = config.find_tool("docker", "DOCKER_BIN")
    if not tool.available:
        return Probe(
            "docker",
            False,
            optional=True,
            detail="optional fallback — native openXC7 is preferred (npm run chip:openxc7)",
        )
    code, out, err = run([tool.path, "version", "--format", "{{.Server.Version}}"], timeout=30)
    if code != 0:
        return Probe(
            "docker",
            False,
            path=tool.path,
            optional=True,
            detail=f"docker CLI found but the daemon is not responding: {_first_line(err) or _first_line(out)}",
        )
    return Probe(
        "docker",
        True,
        path=tool.path,
        version=_first_line(out),
        optional=True,
        detail="daemon reachable (optional fallback)",
    )


def probe_f4pga_image() -> Probe:
    docker = probe_docker()
    if not docker.available:
        return Probe(
            "f4pga-image",
            False,
            optional=True,
            detail="optional Docker fallback — native openXC7 does not need this image",
        )
    code, out, _ = run([docker.path or "docker", "image", "inspect", config.F4PGA_IMAGE, "--format", "{{.Id}}"], timeout=60)
    if code == 0:
        return Probe("f4pga-image", True, version=config.F4PGA_IMAGE, detail=_first_line(out)[:19])
    return Probe(
        "f4pga-image",
        False,
        optional=True,
        detail=f"{config.F4PGA_IMAGE} not pulled yet — only used if native openXC7 is missing",
    )


def probe_openfpgaloader() -> Probe:
    tool = config.find_tool("openFPGALoader", "OPENFPGALOADER_BIN")
    if not tool.available and os.name == "nt":
        tool = config.find_tool("openFPGALoader.exe", "OPENFPGALOADER_BIN")
    if not tool.available:
        return Probe(
            "openFPGALoader",
            False,
            detail="host JTAG programmer missing — must run on the host, never inside Docker",
        )
    code, out, err = run([tool.path, "--Version"], timeout=30)
    if code != 0:
        code, out, err = run([tool.path, "--version"], timeout=30)
    if code != 0:
        return Probe("openFPGALoader", False, path=tool.path, detail=_first_line(err) or f"exit {code}")
    return Probe("openFPGALoader", True, path=tool.path, version=_first_line(out))


def probe_yosys() -> Probe:
    tool = config.find_tool("yosys", "YOSYS_BIN")
    if not tool.available:
        return Probe("yosys", False, detail="needed for fpga_synthesize — run: npm run chip:cad-suite")
    code, out, err = run([tool.path, "-V"], timeout=30)
    if code != 0:
        return Probe("yosys", False, path=tool.path, detail=_first_line(err) or f"exit {code}")
    return Probe("yosys", True, path=tool.path, version=_first_line(out))


def probe_nextpnr_xilinx() -> Probe:
    tool = config.find_tool("nextpnr-xilinx", "NEXTPNR_XILINX_BIN")
    if not tool.available:
        return Probe("nextpnr-xilinx", False, detail="needed for native synth — run: npm run chip:openxc7")
    chipdb = config.xc7_chipdb()
    db = config.prjxray_db_root()
    frames = config.find_tool("xc7frames2bit", "XC7FRAMES2BIT_BIN")
    fasm = config.fasm2frames_command()
    gaps = []
    if chipdb is None:
        gaps.append("xc7a35tcsg324 chipdb")
    if db is None:
        gaps.append("prjxray-db")
    if not frames.available:
        gaps.append("xc7frames2bit")
    if fasm is None:
        gaps.append("fasm2frames")
    code, out, err = run([tool.path, "--help"], timeout=30)
    version = _first_line(out) or _first_line(err)
    if gaps:
        return Probe(
            "nextpnr-xilinx",
            False,
            path=tool.path,
            version=version,
            detail="binary present but missing: " + ", ".join(gaps),
        )
    return Probe("nextpnr-xilinx", True, path=tool.path, version=version, detail=f"chipdb {chipdb.name}")


def probe_verilator() -> Probe:
    tool = config.find_tool("verilator", "VERILATOR_BIN")
    if not tool.available:
        return Probe("verilator", False, detail="optional — needed for fpga_lint / fpga_simulate; run: npm run chip:cad-suite")
    code, out, err = run([tool.path, "--version"], timeout=30)
    if code != 0:
        return Probe("verilator", False, path=tool.path, detail=_first_line(err) or f"exit {code}")
    return Probe("verilator", True, path=tool.path, version=_first_line(out))


def probe_make() -> Probe:
    tool = config.find_tool("make", "MAKE_BIN")
    if not tool.available:
        return Probe(
            "make",
            False,
            detail="needed for fpga_simulate --build — run: npm run chip:mingw",
        )
    code, out, err = run([tool.path, "--version"], timeout=15)
    version = _first_line(out) or _first_line(err)
    if code != 0 and not version:
        return Probe("make", False, path=tool.path, detail=_first_line(err) or f"exit {code}")
    return Probe("make", True, path=tool.path, version=version)


def probe_gxx() -> Probe:
    tool = config.find_tool("g++", "CXX_BIN")
    if not tool.available:
        return Probe(
            "g++",
            False,
            detail="needed for fpga_simulate --build — run: npm run chip:mingw",
        )
    code, out, err = run([tool.path, "--version"], timeout=15)
    version = _first_line(out) or _first_line(err)
    if code != 0 and not version:
        return Probe("g++", False, path=tool.path, detail=_first_line(err) or f"exit {code}")
    return Probe("g++", True, path=tool.path, version=version)


def probe_serial() -> Probe:
    """List candidate UART ports without importing pyserial into this process."""
    vp = config.venv_python()
    interpreter = str(vp) if vp.is_file() else None
    if interpreter is None:
        return Probe("serial-port", False, detail="needs the chip-design venv (pyserial)")

    script = (
        "import json;"
        "from serial.tools import list_ports;"
        "print(json.dumps([[p.device, p.description] for p in list_ports.comports()]))"
    )
    code, out, err = run([interpreter, "-c", script], timeout=30)
    if code != 0:
        return Probe("serial-port", False, detail=f"pyserial unavailable: {_first_line(err) or code}")

    try:
        import json

        ports = json.loads(_first_line(out) or "[]")
    except Exception:
        ports = []

    configured = config.serial_port()
    if configured:
        match = [p for p in ports if p and p[0] == configured]
        if match:
            return Probe("serial-port", True, path=configured, detail=match[0][1])
        return Probe(
            "serial-port",
            False,
            detail=f"FPGA_SERIAL_PORT={configured} is not present; visible ports: {[p[0] for p in ports] or 'none'}",
        )

    if not ports:
        return Probe("serial-port", False, detail="no serial ports visible — is the Arty A7 plugged in?")

    # The Arty exposes an FTDI bridge; prefer it but do not insist.
    ftdi = [p for p in ports if "FTDI" in (p[1] or "").upper() or "USB Serial" in (p[1] or "")]
    chosen = (ftdi or ports)[0]
    return Probe(
        "serial-port",
        True,
        path=chosen[0],
        detail=f"{chosen[1]} (auto-selected from {[p[0] for p in ports]})",
    )


def probe_vendor() -> Probe:
    """Are the vendored submodules checked out?"""
    vd = config.vendor_dir()
    if not vd.is_dir():
        return Probe("vendor", False, detail="vendor/ missing — run: npm run chip:setup")
    core = ["fastmcp", "mcp-python-sdk", "pyserial", "f4pga", "litex", "litex-boards", "trng", "scsynth"]
    # An uninitialised submodule leaves an empty directory behind, so "exists"
    # is not enough — check for content.
    problems = [
        name
        for name in core
        if not (vd / name).is_dir() or not any((vd / name).iterdir())
    ]
    if problems:
        return Probe(
            "vendor",
            False,
            path=str(vd),
            detail=f"not initialised: {', '.join(sorted(problems))} — run: git submodule update --init",
        )
    return Probe("vendor", True, path=str(vd), detail=f"{len(core)} core submodules present")


def probe_bitstream() -> Probe:
    bit = config.bitstream_path()
    if not bit.is_file():
        return Probe("bitstream", False, detail="not built yet — run fpga_synthesize")
    size = bit.stat().st_size
    return Probe("bitstream", True, path=str(bit), detail=f"{size} bytes")


@dataclass
class Report:
    probes: list[Probe] = field(default_factory=list)

    def get(self, name: str) -> Probe | None:
        return next((p for p in self.probes if p.name == name), None)

    @property
    def can_simulate(self) -> bool:
        p = self.get("verilator")
        return bool(p and p.available)

    @property
    def can_simulate_build(self) -> bool:
        """Verilator --cc --build needs GNU make + g++ as well as verilator_bin."""
        if not self.can_simulate:
            return False
        make = self.get("make")
        gxx = self.get("g++")
        return bool(make and make.available and gxx and gxx.available)

    @property
    def can_synthesize_native(self) -> bool:
        yosys = self.get("yosys")
        pnr = self.get("nextpnr-xilinx")
        return bool(yosys and yosys.available and pnr and pnr.available)

    @property
    def can_synthesize(self) -> bool:
        docker = self.get("docker")
        return self.can_synthesize_native or bool(docker and docker.available)

    @property
    def can_flash(self) -> bool:
        p = self.get("openFPGALoader")
        return bool(p and p.available)

    @property
    def can_sample(self) -> bool:
        venv = self.get("python-venv")
        port = self.get("serial-port")
        return bool(venv and venv.available and port and port.available)

    def to_dict(self) -> dict:
        blockers = [
            f"{p.name}: {p.detail}"
            for p in self.probes
            if not p.available and p.detail and not p.optional
        ]
        return {
            "repo_root": str(config.repo_root()),
            "chip_dir": str(config.chip_dir()),
            "board": config.BOARD,
            "part": config.PART,
            "f4pga_image": config.F4PGA_IMAGE,
            "capabilities": {
                "lint": self.can_simulate,
                "lint_and_simulate": self.can_simulate_build,
                "simulate_build": self.can_simulate_build,
                "synthesize": self.can_synthesize,
                "synthesize_native": self.can_synthesize_native,
                "flash": self.can_flash,
                "sample_tokens": self.can_sample,
            },
            "tools": [p.to_dict() for p in self.probes],
            "blockers": blockers,
        }


def detect() -> Report:
    """Probe everything the chain needs. Order is cheapest-first."""
    return Report(
        probes=[
            probe_vendor(),
            probe_python_env(),
            probe_verilator(),
            probe_make(),
            probe_gxx(),
            probe_yosys(),
            probe_nextpnr_xilinx(),
            probe_docker(),
            probe_f4pga_image(),
            probe_openfpgaloader(),
            probe_serial(),
            probe_bitstream(),
        ]
    )
