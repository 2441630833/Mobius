"""pyserial transport for the sampler protocol.

pyserial is imported lazily so that importing this module (and therefore the
whole package) still works on a machine with no venv — `fpga_detect` has to be
able to report the missing dependency rather than crash on import.
"""

from __future__ import annotations

import struct
import time
from dataclasses import dataclass
from typing import Sequence

from . import config, protocol
from .protocol import DeviceInfo, Frame, ProtocolError, SampleResult, StatusResult


class TransportError(RuntimeError):
    """Port could not be opened, or the device stopped answering."""


def _import_serial():
    try:
        import serial  # type: ignore
        from serial.tools import list_ports  # type: ignore
    except ImportError as exc:  # pragma: no cover - depends on venv
        raise TransportError(
            "pyserial is not installed in this interpreter. Run `npm run chip:setup` "
            "and make sure the MCP server starts from chip-design/.venv."
        ) from exc
    return serial, list_ports


def list_serial_ports() -> list[dict]:
    _, list_ports = _import_serial()
    return [
        {"device": p.device, "description": p.description, "hwid": p.hwid}
        for p in list_ports.comports()
    ]


def autodetect_port() -> str:
    """Pick a port, preferring the Arty's FTDI bridge.

    Raises rather than guessing when nothing is attached, so the caller reports
    a real blocker instead of timing out on a nonexistent device.
    """
    configured = config.serial_port()
    ports = list_serial_ports()
    if configured:
        if any(p["device"] == configured for p in ports):
            return configured
        raise TransportError(
            f"FPGA_SERIAL_PORT={configured} is not present. Visible ports: "
            f"{[p['device'] for p in ports] or 'none'}"
        )
    if not ports:
        raise TransportError("No serial ports found. Is the Arty A7 connected and powered?")
    ftdi = [p for p in ports if "FTDI" in (p["description"] or "").upper()]
    return (ftdi or ports)[0]["device"]


@dataclass
class SamplerLink:
    """Request/response link to the FPGA.

    The device answers exactly one frame per command, so reads are framed by
    the length field rather than by a timeout guess.
    """

    port: str
    baud: int = config.DEFAULT_BAUD
    timeout: float = 5.0

    def __post_init__(self) -> None:
        serial, _ = _import_serial()
        try:
            self._ser = serial.Serial(
                self.port, self.baud, timeout=self.timeout, write_timeout=self.timeout
            )
        except Exception as exc:
            raise TransportError(f"could not open {self.port} at {self.baud} baud: {exc}") from exc
        # The FPGA may have half a frame buffered from a previous run.
        time.sleep(0.05)
        self._ser.reset_input_buffer()
        self._ser.reset_output_buffer()

    def close(self) -> None:
        try:
            self._ser.close()
        except Exception:
            pass

    def __enter__(self) -> "SamplerLink":
        return self

    def __exit__(self, *_exc) -> None:
        self.close()

    # -- framing ----------------------------------------------------------
    def _read_exact(self, n: int, deadline: float) -> bytes:
        buf = bytearray()
        while len(buf) < n:
            if time.monotonic() > deadline:
                raise TransportError(
                    f"timed out reading {n} bytes from {self.port} (got {len(buf)})"
                )
            chunk = self._ser.read(n - len(buf))
            if chunk:
                buf.extend(chunk)
        return bytes(buf)

    def _exchange(self, request: bytes, timeout: float | None = None) -> Frame:
        budget = timeout if timeout is not None else self.timeout
        deadline = time.monotonic() + budget
        self._ser.write(request)
        self._ser.flush()

        # Resynchronise on the start byte: a previous aborted read can leave
        # stray bytes in the pipe, and silently parsing them as a header is how
        # you get a phantom 60 KB length.
        while True:
            if time.monotonic() > deadline:
                raise TransportError(f"no response start byte from {self.port} within {budget:.1f}s")
            byte = self._ser.read(1)
            if not byte:
                continue
            if byte[0] == protocol.SOF_FPGA:
                break

        header = self._read_exact(3, deadline)
        length = struct.unpack_from("<H", header, 1)[0]
        if length > 4096:
            raise ProtocolError(f"implausible payload length {length} — link out of sync")
        rest = self._read_exact(length + 1, deadline)
        return protocol.parse_frame(bytes([protocol.SOF_FPGA]) + header + rest)

    # -- commands ---------------------------------------------------------
    def ping(self) -> DeviceInfo:
        return protocol.parse_ping(self._exchange(protocol.encode_ping()))

    def status(self) -> StatusResult:
        return protocol.parse_status(self._exchange(protocol.encode_status()))

    def raw_entropy(self, n_bytes: int = 256) -> bytes:
        # Von Neumann debiasing throws away most raw bits, so a full 256-byte
        # request is far slower than a normal command exchange.
        frame = self._exchange(protocol.encode_raw(n_bytes), timeout=max(self.timeout, 15.0))
        if frame.kind != protocol.CMD_RAW:
            raise ProtocolError(f"expected a raw-entropy reply, got {frame.kind:#04x}")
        return frame.payload

    def sample(self, logits: Sequence[float], k: int = protocol.DEFAULT_K) -> SampleResult:
        frame = self._exchange(
            protocol.encode_sample(logits, k=k), timeout=max(self.timeout, 10.0)
        )
        return protocol.parse_sample(frame)


def open_link(port: str | None = None, baud: int | None = None, timeout: float = 5.0) -> SamplerLink:
    return SamplerLink(
        port=port or autodetect_port(),
        baud=baud or config.DEFAULT_BAUD,
        timeout=timeout,
    )
