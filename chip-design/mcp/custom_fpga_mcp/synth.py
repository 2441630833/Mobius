"""FPGA synthesis: native openXC7 on the host, Docker F4PGA as fallback.

Windows has no official F4PGA installer. Yosys comes from OSS CAD Suite;
nextpnr-xilinx + prjxray bitstream tools come from FPGAwars openXC7. Docker
is only used when that host toolchain is incomplete.
"""

from __future__ import annotations

import shutil
from pathlib import Path

from . import config
from .toolchain import probe_docker, run


def _posix(path: Path) -> str:
    """Container-side path. Docker wants forward slashes even from Windows."""
    return path.as_posix()


def synth_script(top: str = config.TOP_MODULE) -> str:
    """Yosys + nextpnr-xilinx script run inside the F4PGA container."""
    sources = " ".join(f"/work/rtl/{p.name}" for p in config.rtl_sources())
    xdc = "/work/constraints/arty_a7_35t.xdc"
    return f"""#!/usr/bin/env bash
set -euo pipefail

TOP={top}
PART={config.PART}
OUT=/work/build

mkdir -p "$OUT"
cd "$OUT"

echo "=== yosys synthesis ==="
# -flatten keeps nextpnr's job simple; the design is small enough that the
# lost hierarchy is not worth the placement quality.
yosys -p "
  read_verilog -DSYNTHESIS {sources};
  synth_xilinx -flatten -abc9 -nobram -arch xc7 -top $TOP;
  write_json $OUT/$TOP.json;
  stat;
" 2>&1 | tee "$OUT/yosys.log"

echo "=== nextpnr-xilinx place and route ==="
nextpnr-xilinx \\
  --chipdb "${{NEXTPNR_XILINX_DIR:-/usr/share/nextpnr}}/xilinx/xc7a35t.bin" \\
  --xdc {xdc} \\
  --json "$OUT/$TOP.json" \\
  --write "$OUT/$TOP.routed.json" \\
    --fasm "$OUT/$TOP.fasm" \\
  --freq 50 \\
  2>&1 | tee "$OUT/nextpnr.log"
  # 50 MHz target: the top divides the 100 MHz crystal by 2 and runs every
  # clocked cell on the resulting 50 MHz clk_sys (see sampler_uart_top). The
  # 100 MHz pin drives only a Q->~Q->D divide-by-2 flop, which closes far
  # inside either budget.

echo "=== fasm2frames + bitstream ==="
fasm2frames --part "$PART" --db-root "${{PRJXRAY_DB_DIR:-/usr/share/nextpnr/prjxray-db}}/artix7" \\
  "$OUT/$TOP.fasm" > "$OUT/$TOP.frames"
xc7frames2bit --part_file "${{PRJXRAY_DB_DIR:-/usr/share/nextpnr/prjxray-db}}/artix7/$PART/part.yaml" \\
  --part_name "$PART" \\
  --frm_file "$OUT/$TOP.frames" \\
  --output_file "$OUT/$TOP.bit"

echo "=== done: $OUT/$TOP.bit ==="
ls -l "$OUT/$TOP.bit"
"""


def native_synth_ready() -> dict | None:
    """Return a structured blocker if the host openXC7 flow is incomplete."""
    missing: list[str] = []
    yosys = config.find_tool("yosys", "YOSYS_BIN")
    pnr = config.find_tool("nextpnr-xilinx", "NEXTPNR_XILINX_BIN")
    frames2bit = config.find_tool("xc7frames2bit", "XC7FRAMES2BIT_BIN")
    if not yosys.available:
        missing.append("yosys (OSS CAD Suite)")
    if not pnr.available:
        missing.append("nextpnr-xilinx (openXC7)")
    if not frames2bit.available:
        missing.append("xc7frames2bit (openXC7)")
    if config.xc7_chipdb() is None:
        missing.append(f"chipdb for {config.PART}")
    if config.prjxray_db_root() is None:
        missing.append("prjxray-db (artix7)")
    if config.fasm2frames_command() is None:
        missing.append("fasm2frames")
    if missing:
        return {
            "ok": False,
            "stage": "native-toolchain",
            "error": "native Xilinx 7-series tools incomplete: " + ", ".join(missing),
            "hint": "Run: npm run chip:openxc7  (and npm run chip:cad-suite for Yosys). Docker is optional fallback.",
        }
    return None


def _write_yosys_script(build: Path, top: str) -> Path:
    sources = " ".join(str(p.resolve()) for p in config.rtl_sources())
    script = build / "synth.ys"
    script.write_text(
        "\n".join(
            [
                f"read_verilog -DSYNTHESIS {sources}",
                f"synth_xilinx -flatten -abc9 -nobram -arch xc7 -top {top}",
                f"write_json {build / f'{top}.json'}",
                "stat",
            ]
        )
        + "\n",
        encoding="utf-8",
        newline="\n",
    )
    return script


def _run_logged(cmd: list[str], log_path: Path, timeout: float, cwd: Path | None = None) -> tuple[int, str]:
    code, out, err = run(cmd, timeout=timeout, cwd=cwd)
    combined = (out + "\n" + err).strip()
    log_path.write_text(combined, encoding="utf-8", errors="replace")
    return code, combined


def synthesize_native(top: str = config.TOP_MODULE, timeout: float = 1800.0) -> dict:
    """Host Yosys + nextpnr-xilinx + prjxray. No Docker."""
    blocker = native_synth_ready()
    if blocker:
        return blocker

    missing = [str(p) for p in config.rtl_sources() if not p.is_file()]
    if missing:
        return {"ok": False, "stage": "sources", "error": f"missing RTL: {missing}"}

    xdc = config.constraints_dir() / "arty_a7_35t.xdc"
    if not xdc.is_file():
        return {"ok": False, "stage": "sources", "error": f"missing constraints: {xdc}"}

    build = config.build_dir()
    build.mkdir(parents=True, exist_ok=True)
    logs: list[dict] = []

    yosys = config.find_tool("yosys", "YOSYS_BIN")
    ys = _write_yosys_script(build, top)
    yosys_log = build / "yosys.log"
    code, combined = _run_logged(
        [yosys.path or "yosys", "-l", str(yosys_log), "-s", str(ys)],
        yosys_log,
        timeout,
    )
    logs.append({"stage": "yosys", "exit_code": code, "tail": combined[-2000:]})
    if code != 0:
        return {
            "ok": False,
            "stage": "yosys",
            "error": f"yosys failed (exit {code})",
            "log_file": str(yosys_log),
            "logs": logs,
        }

    pnr = config.find_tool("nextpnr-xilinx", "NEXTPNR_XILINX_BIN")
    json_net = build / f"{top}.json"
    routed = build / f"{top}.routed.json"
    fasm = build / f"{top}.fasm"
    pnr_log = build / "nextpnr.log"
    chipdb = config.xc7_chipdb()
    assert chipdb is not None
    code, combined = _run_logged(
        [
            pnr.path or "nextpnr-xilinx",
            "--chipdb",
            str(chipdb),
            "--xdc",
            str(xdc),
            "--json",
            str(json_net),
            "--write",
            str(routed),
                        "--fasm",
            str(fasm),
            # 50 MHz target: the top divides the 100 MHz crystal by 2 and runs
            # all logic on clk_sys; the 100 MHz input drives only the divider
            # flop. See sampler_uart_top / arty_a7_35t.xdc.
            "--freq",
            "50",
        ],
        pnr_log,
        timeout,
    )
    logs.append({"stage": "nextpnr", "exit_code": code, "tail": combined[-2000:]})
    if code != 0:
        return {
            "ok": False,
            "stage": "nextpnr",
            "error": f"nextpnr-xilinx failed (exit {code})",
            "log_file": str(pnr_log),
            "logs": logs,
        }

    frames = build / f"{top}.frames"
    fasm_cmd = config.fasm2frames_command()
    assert fasm_cmd is not None
    db = config.prjxray_db_root()
    assert db is not None
    code, out, err = run(
        [*fasm_cmd, "--part", config.PART, "--db-root", str(db), str(fasm), str(frames)],
        timeout=timeout,
    )
    if code != 0 or not frames.is_file() or frames.stat().st_size == 0:
        # Some builds write frames to stdout instead of the last argument.
        code2, out2, err2 = run(
            [*fasm_cmd, "--part", config.PART, "--db-root", str(db), str(fasm)],
            timeout=timeout,
        )
        stdout = (out2 or out or "").strip()
        if code2 == 0 and stdout:
            frames.write_text(stdout, encoding="utf-8", errors="replace")
            code, out, err = code2, out2, err2
        else:
            combined = ((out or "") + "\n" + (err or "") + "\n" + (err2 or "")).strip()
            (build / "fasm2frames.log").write_text(combined, encoding="utf-8", errors="replace")
            logs.append({"stage": "fasm2frames", "exit_code": code, "tail": combined[-2000:]})
            return {
                "ok": False,
                "stage": "fasm2frames",
                "error": f"fasm2frames failed (exit {code})",
                "log_file": str(build / "fasm2frames.log"),
                "logs": logs,
            }
    (build / "fasm2frames.log").write_text((out + "\n" + err).strip(), encoding="utf-8", errors="replace")
    logs.append({"stage": "fasm2frames", "exit_code": 0, "tail": "ok"})

    frames2bit = config.find_tool("xc7frames2bit", "XC7FRAMES2BIT_BIN")
    part_yaml = db / config.PART / "part.yaml"
    if not part_yaml.is_file():
        return {
            "ok": False,
            "stage": "bitstream",
            "error": f"missing prjxray part file: {part_yaml}",
            "logs": logs,
        }
    bit = config.bitstream_path()
    bit_log = build / "xc7frames2bit.log"
    code, combined = _run_logged(
        [
            frames2bit.path or "xc7frames2bit",
            "--part_file",
            str(part_yaml),
            "--part_name",
            config.PART,
            "--frm_file",
            str(frames),
            "--output_file",
            str(bit),
        ],
        bit_log,
        timeout,
    )
    logs.append({"stage": "xc7frames2bit", "exit_code": code, "tail": combined[-2000:]})
    if code != 0 or not bit.is_file():
        return {
            "ok": False,
            "stage": "bitstream",
            "error": f"xc7frames2bit failed (exit {code})" if code != 0 else "no bitstream written",
            "log_file": str(bit_log),
            "logs": logs,
        }

    synth_log = build / "synth.log"
    synth_log.write_text(
        "\n".join(f"=== {entry['stage']} exit {entry['exit_code']} ===\n{entry.get('tail', '')}" for entry in logs),
        encoding="utf-8",
        errors="replace",
    )
    return {
        "ok": True,
        "stage": "synth",
        "backend": "openxc7",
        "bitstream": str(bit),
        "size_bytes": bit.stat().st_size,
        "utilisation": _parse_utilisation(build / "yosys.log"),
        "log_file": str(synth_log),
    }


def synthesize_docker(top: str = config.TOP_MODULE, timeout: float = 1800.0, pull: bool = True) -> dict:
    """Linux F4PGA image. Used only when native openXC7 is incomplete."""
    docker = probe_docker()
    if not docker.available:
        return {
            "ok": False,
            "stage": "docker",
            "error": docker.detail,
            "hint": "Install native tools with npm run chip:openxc7 (preferred on Windows), or install Docker Desktop.",
        }

    missing = [str(p) for p in config.rtl_sources() if not p.is_file()]
    if missing:
        return {"ok": False, "stage": "sources", "error": f"missing RTL: {missing}"}

    xdc = config.constraints_dir() / "arty_a7_35t.xdc"
    if not xdc.is_file():
        return {"ok": False, "stage": "sources", "error": f"missing constraints: {xdc}"}

    build = config.build_dir()
    build.mkdir(parents=True, exist_ok=True)
    script_path = build / "synth.sh"
    script_path.write_text(synth_script(top), encoding="utf-8", newline="\n")

    logs: list[dict] = []

    if pull:
        code, out, err = run([docker.path or "docker", "image", "inspect", config.F4PGA_IMAGE], timeout=60)
        if code != 0:
            pull_code, pull_out, pull_err = run(
                [docker.path or "docker", "pull", config.F4PGA_IMAGE], timeout=timeout
            )
            logs.append({"stage": "pull", "exit_code": pull_code, "tail": (pull_err or pull_out)[-2000:]})
            if pull_code != 0:
                return {
                    "ok": False,
                    "stage": "pull",
                    "error": f"could not pull {config.F4PGA_IMAGE}",
                    "logs": logs,
                }

    cmd = [
        docker.path or "docker",
        "run",
        "--rm",
        "-v",
        f"{_posix(config.chip_dir())}:/work",
        "-w",
        "/work",
        config.F4PGA_IMAGE,
        "bash",
        "/work/build/synth.sh",
    ]
    code, out, err = run(cmd, timeout=timeout)
    combined = (out + "\n" + err).strip()
    (build / "synth.log").write_text(combined, encoding="utf-8", errors="replace")
    logs.append({"stage": "synth", "exit_code": code, "tail": combined[-4000:]})

    bit = config.bitstream_path()
    if code != 0 or not bit.is_file():
        return {
            "ok": False,
            "stage": "synth",
            "error": f"synthesis failed (exit {code})" if code != 0 else "synthesis reported success but produced no bitstream",
            "log_file": str(build / "synth.log"),
            "logs": logs,
        }

    return {
        "ok": True,
        "stage": "synth",
        "backend": "docker-f4pga",
        "bitstream": str(bit),
        "size_bytes": bit.stat().st_size,
        "utilisation": _parse_utilisation(build / "yosys.log"),
        "log_file": str(build / "synth.log"),
    }


def synthesize(top: str = config.TOP_MODULE, timeout: float = 1800.0, pull: bool = True) -> dict:
    """Synthesize the RTL to a bitstream. Native openXC7 first, Docker fallback.

    Never raises: a missing toolchain is a normal, reportable state.
    """
    native = native_synth_ready()
    if native is None:
        return synthesize_native(top=top, timeout=timeout)
    docker = probe_docker()
    if docker.available:
        return synthesize_docker(top=top, timeout=timeout, pull=pull)
    return native


def _parse_utilisation(log: Path) -> dict:
    """Pull cell counts out of the yosys `stat` output.

    Reported verbatim; never estimated. If the log is absent the caller gets an
    empty dict rather than invented numbers.
    """
    if not log.is_file():
        return {}
    interesting = ("LUT", "FDRE", "CARRY4", "RAMB", "DSP")
    out: dict[str, int] = {}
    try:
        for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
            parts = line.split()
            if len(parts) == 2 and parts[0].isupper() and parts[1].isdigit():
                if any(tag in parts[0] for tag in interesting):
                    out[parts[0]] = int(parts[1])
    except OSError:
        return {}
    return out


def clean() -> dict:
    build = config.build_dir()
    if build.is_dir():
        shutil.rmtree(build, ignore_errors=True)
    return {"ok": True, "removed": str(build)}
