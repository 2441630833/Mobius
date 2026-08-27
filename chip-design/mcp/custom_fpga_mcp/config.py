"""Path and environment resolution for custom-fpga-mcp.

Every path is derived from the repo root rather than the process cwd, because
an MCP server is spawned by the IDE with an unpredictable working directory.
"""

from __future__ import annotations

import os
import shutil
import sys
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

# Docker image published by the F4PGA project. Pinned by tag so a synthesis run
# is reproducible; bump deliberately, not implicitly.
F4PGA_IMAGE = os.environ.get("F4PGA_IMAGE", "ghcr.io/chipsalliance/f4pga:latest")

# Arty A7-35T. openFPGALoader board name and the F4PGA part string.
BOARD = os.environ.get("FPGA_BOARD", "arty_a7_35t")
PART = os.environ.get("FPGA_PART", "xc7a35tcsg324-1")

DEFAULT_BAUD = int(os.environ.get("FPGA_BAUD", "115200"))
TOP_MODULE = "sampler_uart_top"


def _looks_like_repo_root(path: Path) -> bool:
    if (path / "chip-design" / "rtl").is_dir():
        return True
    pkg = path / "package.json"
    if pkg.is_file():
        try:
            import json

            return json.loads(pkg.read_text(encoding="utf-8")).get("name") == "Mobius"
        except Exception:
            return False
    return False


@lru_cache(maxsize=1)
def repo_root() -> Path:
    """Locate the Mobius checkout.

    Order: MOBIUS_ROOT, this file's ancestors, then cwd's ancestors. The
    ancestor walk is what makes the server work when the IDE spawns it from
    somewhere unrelated.
    """
    env = os.environ.get("MOBIUS_ROOT")
    if env:
        candidate = Path(env).expanduser().resolve()
        if candidate.is_dir():
            return candidate

    for start in (Path(__file__).resolve(), Path.cwd().resolve() / "_"):
        for parent in start.parents:
            if _looks_like_repo_root(parent):
                return parent

    # Fall back to the layout we know: <root>/chip-design/mcp/custom_fpga_mcp
    return Path(__file__).resolve().parents[3]


def chip_dir() -> Path:
    return repo_root() / "chip-design"


def rtl_dir() -> Path:
    return chip_dir() / "rtl"


def sim_dir() -> Path:
    return chip_dir() / "sim"


def soc_dir() -> Path:
    return chip_dir() / "soc"


def constraints_dir() -> Path:
    return chip_dir() / "constraints"


def tests_dir() -> Path:
    return chip_dir() / "tests"


def build_dir() -> Path:
    return chip_dir() / "build"


def vendor_dir() -> Path:
    return repo_root() / "vendor"


def toolchain_state_file() -> Path:
    """Written by scripts/setup-chip-design.ps1 with discovered tool paths."""
    return chip_dir() / ".toolchain.json"


def cad_suite_dir() -> Path | None:
    """YosysHQ OSS CAD Suite (bundled Verilator / Yosys / openFPGALoader)."""
    d = repo_root() / "tools" / "oss-cad-suite"
    if (d / "bin").is_dir():
        return d
    return None


def openxc7_dir() -> Path | None:
    """FPGAwars openXC7 (bundled nextpnr-xilinx / xc7frames2bit / prjxray-db)."""
    d = repo_root() / "tools" / "openxc7"
    if (d / "bin").is_dir():
        return d
    return None


def mingw_dir() -> Path | None:
    """Portable MinGW (w64devkit): GNU make + g++ for Verilator --build."""
    d = repo_root() / "tools" / "mingw"
    bindir = d / "bin"
    gxx = (bindir / "g++.exe").is_file() or (bindir / "g++").is_file()
    make = (
        (bindir / "make.exe").is_file()
        or (bindir / "mingw32-make.exe").is_file()
        or (bindir / "make").is_file()
    )
    return d if gxx and make else None


def _prepend_tool_dirs(dirs: list[Path]) -> dict[str, str]:
    parts: list[str] = []
    for d in dirs:
        for sub in ("bin", "lib", "libexec"):
            candidate = d / sub
            if candidate.is_dir():
                parts.append(str(candidate))
    if not parts:
        return {}
    path = os.environ.get("PATH", "")
    return {"PATH": os.pathsep.join([*parts, path])}


def cad_suite_env() -> dict[str, str]:
    """Env so verilator --cc --build finds g++/perl and VERILATOR_ROOT.

    OSS CAD Suite is prepended first so yosys.exe loads its own mingw DLLs.
    openXC7 comes after; ``tool_env`` puts the invoked binary's dir first so
    nextpnr-xilinx.exe still sees its own runtime.
    """
    env: dict[str, str] = {}
    d = cad_suite_dir()
    xc7 = openxc7_dir()
    mingw = mingw_dir()
    # OSS CAD Suite first so yosys.exe keeps its own mingw DLLs; MinGW last so
    # make/g++ are found without shadowing those DLLs.
    roots = [p for p in (d, xc7, mingw) if p is not None]
    env.update(_prepend_tool_dirs(roots))
    if d is not None:
        env["YOSYSHQ_ROOT"] = str(d)
        env["VERILATOR_ROOT"] = str(d / "share" / "verilator").replace("\\", "/")
    if xc7 is not None:
        env["OPENXC7_ROOT"] = str(xc7)
    gxx = _bundled_tool("g++")
    gcc = _bundled_tool("gcc")
    make = _bundled_tool("make")
    if gxx is not None:
        env["CXX"] = str(gxx)
    if gcc is not None:
        env["CC"] = str(gcc)
    elif gxx is not None:
        env["CC"] = str(gxx)
    if make is not None:
        env["MAKE"] = str(make)
    site = openxc7_pythonpath()
    if site:
        existing = os.environ.get("PYTHONPATH", "")
        env["PYTHONPATH"] = os.pathsep.join([site, existing]) if existing else site
    return env


# verilator_bin.exe is CreateProcess-safe on Windows; .cmd wrappers are not.
_BUNDLED_BINARIES: dict[str, tuple[str, ...]] = {
    "verilator": ("verilator_bin.exe", "verilator.exe", "verilator"),
    "openFPGALoader": ("openFPGALoader.exe", "openFPGALoader"),
    "yosys": ("yosys.exe", "yosys"),
    "nextpnr-xilinx": ("nextpnr-xilinx.exe", "nextpnr-xilinx"),
    "xc7frames2bit": ("xc7frames2bit.exe", "xc7frames2bit"),
    "g++": ("g++.exe", "g++"),
    "gcc": ("gcc.exe", "gcc"),
    "make": ("make.exe", "mingw32-make.exe", "gmake.exe", "make"),
}


def _bundled_roots() -> list[Path]:
    return [p for p in (mingw_dir(), openxc7_dir(), cad_suite_dir()) if p is not None]


def openxc7_pythonpath() -> str | None:
    """site-packages for fasm2frames / prjxray (shipped inside openXC7)."""
    xc7 = openxc7_dir()
    if xc7 is None:
        return None
    lib = xc7 / "lib"
    if not lib.is_dir():
        return None
    for ver in ("python3.12", "python3.11", "python3"):
        site = lib / ver / "site-packages"
        if site.is_dir():
            return str(site)
    matches = list(lib.glob("python*/site-packages"))
    return str(matches[0]) if matches else None


def tool_env(binary: str | None = None) -> dict[str, str]:
    """cad_suite_env plus the invoked binary's own bin/lib first (mingw DLL isolation)."""
    env = cad_suite_env()
    if not binary:
        return env
    try:
        bindir = Path(binary).resolve().parent
    except OSError:
        return env
    extras = [str(bindir)]
    root = bindir.parent
    for sub in ("lib", "libexec"):
        candidate = root / sub
        if candidate.is_dir():
            extras.append(str(candidate))
    path = env.get("PATH") or os.environ.get("PATH", "")
    env["PATH"] = os.pathsep.join([*extras, path])
    return env


def _bundled_tool(name: str) -> Path | None:
    filenames = _BUNDLED_BINARIES.get(name, (name,))
    for root in _bundled_roots():
        for sub in ("bin", "libexec"):
            for filename in filenames:
                candidate = root / sub / filename
                if candidate.is_file():
                    return candidate
    return None


def xc7_chipdb() -> Path | None:
    """nextpnr-xilinx chipdb for the Arty A7-35T (xc7a35tcsg324)."""
    roots = _bundled_roots()
    names = ("xc7a35tcsg324.bin", "xc7a35t.bin")
    relative = (
        ("chipdb",),
        ("share", "nextpnr"),
        ("share", "nextpnr", "xilinx"),
        ("share", "nextpnr", "external"),
    )
    for root in roots:
        for rel in relative:
            folder = root.joinpath(*rel)
            for name in names:
                candidate = folder / name
                if candidate.is_file():
                    return candidate
    xc7 = openxc7_dir()
    if xc7 is not None:
        for name in names:
            matches = list(xc7.rglob(name))
            if matches:
                return matches[0]
    return None


def prjxray_db_root() -> Path | None:
    """Directory that contains artix7/<part>/part.yaml (prjxray-db)."""
    search_roots = [p for p in (openxc7_dir(), cad_suite_dir()) if p is not None]
    for root in search_roots:
        for rel in (
            ("share", "nextpnr", "external", "prjxray-db"),
            ("share", "prjxray-db"),
            ("prjxray-db"),
        ):
            artix = root.joinpath(*rel, "artix7")
            if (artix / PART / "part.yaml").is_file() or artix.is_dir():
                return artix
    xc7 = openxc7_dir()
    if xc7 is not None:
        for artix in xc7.rglob("artix7"):
            if (artix / PART / "part.yaml").is_file():
                return artix
    return None


def fasm2frames_command() -> list[str] | None:
    """How to invoke fasm2frames (native exe, or Python script)."""
    py = _bundled_python()
    for root in _bundled_roots():
        for rel, name in (
            (("bin",), "fasm2frames.exe"),
            (("libexec",), "fasm2frames"),
            (("libexec",), "fasm2frames.py"),
            (("bin",), "fasm2frames"),
        ):
            candidate = root.joinpath(*rel, name)
            if not candidate.is_file():
                continue
            if candidate.suffix.lower() == ".exe":
                return [str(candidate)]
            if py:
                return [py, str(candidate)]
            return [str(candidate)]
    found = shutil.which("fasm2frames")
    return [found] if found else None


def _bundled_python() -> str | None:
    for root in _bundled_roots():
        for name in ("python.exe", "python3.exe", "python3"):
            candidate = root / "bin" / name
            if candidate.is_file():
                return str(candidate)
    vp = venv_python()
    if vp.is_file():
        return str(vp)
    return sys.executable if sys.executable else None


def venv_dir() -> Path:
    return chip_dir() / ".venv"


def venv_python() -> Path:
    if os.name == "nt":
        return venv_dir() / "Scripts" / "python.exe"
    return venv_dir() / "bin" / "python"


def rtl_sources() -> list[Path]:
    """RTL in dependency order — leaf modules first, top last."""
    names = [
        "sc_core.v",
        "trng_ring_osc.v",
        "sc_softmax_sampler.v",
        "uart_rx.v",
        "uart_tx.v",
        "sampler_uart_top.v",
    ]
    return [rtl_dir() / n for n in names]


def bitstream_path() -> Path:
    return build_dir() / f"{TOP_MODULE}.bit"


@dataclass
class ToolPath:
    name: str
    path: str | None
    detail: str = ""

    @property
    def available(self) -> bool:
        return self.path is not None

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "available": self.available,
            "path": self.path,
            "detail": self.detail,
        }


def _state() -> dict:
    """Tool paths recorded by the setup script, if it has run."""
    state_file = toolchain_state_file()
    if not state_file.is_file():
        return {}
    try:
        import json

        data = json.loads(state_file.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def find_tool(name: str, env_var: str | None = None) -> ToolPath:
    """Resolve an external binary.

    Ladder: explicit env var, then the setup script's recorded path, then the
    bundled OSS CAD Suite under tools/oss-cad-suite, then PATH.
    Each rung is validated before it is trusted -- a recorded path from a
    previous machine must not shadow a working one on PATH.
    """
    if env_var:
        override = os.environ.get(env_var)
        if override and Path(override).is_file():
            return ToolPath(name, str(Path(override).resolve()), f"from ${env_var}")

    recorded = _state().get(name)
    if isinstance(recorded, str) and Path(recorded).is_file():
        return ToolPath(name, str(Path(recorded).resolve()), "from .toolchain.json")

    bundled = _bundled_tool(name)
    if bundled is not None:
        return ToolPath(name, str(bundled.resolve()), "bundled toolchain")

    found = shutil.which(name)
    if found:
        return ToolPath(name, str(Path(found).resolve()), "from PATH")

    return ToolPath(name, None, "not found")


def serial_port() -> str | None:
    """Configured UART port, if any. Auto-detection lives in uart.py."""
    return os.environ.get("FPGA_SERIAL_PORT") or _state().get("serial_port") or None


def python_executable() -> str:
    """Interpreter for spawning LiteX / helper scripts."""
    vp = venv_python()
    return str(vp) if vp.is_file() else sys.executable
