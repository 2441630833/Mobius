"""Wire protocol for the FPGA token sampler.

Byte-for-byte mirror of ``chip-design/rtl/sampler_uart_top.v``. If you change
the framing in one place you must change it in the other and update
``chip-design/tests/test_protocol.py``.

Deliberately stdlib-only: this module is imported by the unit tests, which run
against a bare system interpreter with no venv and no pyserial.

Frame layout::

    host -> fpga:  0x5A CMD LEN_LO LEN_HI payload[LEN] CRC8
    fpga -> host:  0xA5 RSP LEN_LO LEN_HI payload[LEN] CRC8

CRC8 is CRC-8/ATM (poly 0x07, init 0x00, no reflection) over CMD..payload.
"""

from __future__ import annotations

import math
import struct
from dataclasses import dataclass, field
from typing import Iterable, Sequence

SOF_HOST = 0x5A
SOF_FPGA = 0xA5

CMD_PING = 0x50  # 'P'
CMD_SAMPLE = 0x4C  # 'L'
CMD_RAW = 0x52  # 'R'
CMD_STATUS = 0x53  # 'S'
RSP_TOKEN = 0x54  # 'T'
RSP_ERROR = 0x45  # 'E'

ERR_CRC = 0x01
ERR_UNKNOWN = 0x02
ERR_LENGTH = 0x03
ERR_BUSY = 0x04

ERROR_NAMES = {
    ERR_CRC: "bad CRC",
    ERR_UNKNOWN: "unknown command",
    ERR_LENGTH: "bad payload length",
    ERR_BUSY: "sampler busy",
}

FLAG_FALLBACK_ARGMAX = 0x01
FLAG_ENTROPY_FAIL = 0x02
FLAG_RX_FRAME_ERROR = 0x04

# Defaults must match the RTL parameters in sampler_uart_top.v.
DEFAULT_K = 32
DEFAULT_SC_LOG2 = 12
LOGIT_FRAC_BITS = 8  # signed Q8.8
RAW_MAX = 256

# exp(-2^(j-8)) in Q0.16, j = 0..15 -- the exp_const table in
# sc_softmax_sampler.v. Entries 12..15 are zero by rounding, so a candidate
# more than ~16 nats below the max is sampled with probability zero.
EXP_CONSTS: tuple[int, ...] = (
    65280, 65030, 64524, 63524,
    61569, 57841, 51035, 39749,
    24109, 8869, 1200, 22,
    0, 0, 0, 0,
)


class ProtocolError(Exception):
    """Malformed or unexpected frame."""


class DeviceError(ProtocolError):
    """The FPGA answered with an explicit 'E' error frame."""

    def __init__(self, code: int) -> None:
        self.code = code
        super().__init__(f"FPGA rejected the request: {ERROR_NAMES.get(code, hex(code))}")


def crc8(data: Iterable[int]) -> int:
    """CRC-8/ATM over ``data``."""
    crc = 0
    for byte in data:
        crc ^= byte & 0xFF
        for _ in range(8):
            crc = ((crc << 1) ^ 0x07) & 0xFF if crc & 0x80 else (crc << 1) & 0xFF
    return crc


def float_to_q88(value: float) -> int:
    """Clamp a logit to signed Q8.8.

    Values outside +-128 nats are clipped rather than wrapped: wrapping would
    turn a very negative logit into a very positive one and corrupt the sample.
    """
    if math.isnan(value):
        raise ValueError("logit is NaN")
    raw = int(round(value * (1 << LOGIT_FRAC_BITS)))
    return max(-32768, min(32767, raw))


def q88_to_float(raw: int) -> float:
    return raw / (1 << LOGIT_FRAC_BITS)


def build_frame(cmd: int, payload: bytes = b"") -> bytes:
    body = bytes([cmd]) + struct.pack("<H", len(payload)) + payload
    return bytes([SOF_HOST]) + body + bytes([crc8(body)])


def encode_ping() -> bytes:
    return build_frame(CMD_PING)


def encode_status() -> bytes:
    return build_frame(CMD_STATUS)


def encode_raw(n_bytes: int) -> bytes:
    if not 1 <= n_bytes <= RAW_MAX:
        raise ValueError(f"raw byte count must be 1..{RAW_MAX}, got {n_bytes}")
    return build_frame(CMD_RAW, struct.pack("<H", n_bytes))


def encode_sample(logits: Sequence[float], k: int = DEFAULT_K) -> bytes:
    """Encode exactly ``k`` logits.

    The RTL rejects any other length, so pad short vectors with a very negative
    logit (probability ~0) instead of letting the device answer ERR_LENGTH.
    """
    if len(logits) > k:
        raise ValueError(f"got {len(logits)} logits but the device window is {k}")
    padded = list(logits) + [-128.0] * (k - len(logits))
    payload = b"".join(struct.pack("<h", float_to_q88(v)) for v in padded)
    return build_frame(CMD_SAMPLE, payload)


@dataclass
class Frame:
    kind: int
    payload: bytes


def parse_frame(raw: bytes) -> Frame:
    """Parse one complete device->host frame.

    Raises DeviceError for an 'E' frame so callers do not have to special-case
    it, and ProtocolError for anything structurally wrong.
    """
    if len(raw) < 5:
        raise ProtocolError(f"frame too short ({len(raw)} bytes)")
    if raw[0] != SOF_FPGA:
        raise ProtocolError(f"bad start byte {raw[0]:#04x}, expected {SOF_FPGA:#04x}")
    length = struct.unpack_from("<H", raw, 2)[0]
    expected = 5 + length
    if len(raw) != expected:
        raise ProtocolError(f"frame length mismatch: header says {expected} bytes, got {len(raw)}")
    body = raw[1:-1]
    if crc8(body) != raw[-1]:
        raise ProtocolError(f"CRC mismatch: computed {crc8(body):#04x}, frame says {raw[-1]:#04x}")
    kind = raw[1]
    payload = raw[4:-1]
    if kind == RSP_ERROR:
        raise DeviceError(payload[0] if payload else 0)
    return Frame(kind=kind, payload=payload)


@dataclass
class DeviceInfo:
    version_major: int
    version_minor: int
    k: int
    logit_width: int
    sc_log2: int
    flags: int

    @property
    def version(self) -> str:
        return f"{self.version_major}.{self.version_minor}"

    @property
    def entropy_ok(self) -> bool:
        return not self.flags & FLAG_ENTROPY_FAIL


def parse_ping(frame: Frame) -> DeviceInfo:
    if frame.kind != CMD_PING:
        raise ProtocolError(f"expected a ping reply, got {frame.kind:#04x}")
    if len(frame.payload) != 6:
        raise ProtocolError(f"ping reply should be 6 bytes, got {len(frame.payload)}")
    ver = struct.unpack_from("<H", frame.payload, 0)[0]
    return DeviceInfo(
        version_major=(ver >> 8) & 0xFF,
        version_minor=ver & 0xFF,
        k=frame.payload[2],
        logit_width=frame.payload[3],
        sc_log2=frame.payload[4],
        flags=frame.payload[5],
    )


@dataclass
class SampleResult:
    token_id: int
    draw_u: int
    total_weight: int
    flags: int
    reference_weights: list[int] = field(default_factory=list)

    @property
    def fallback_argmax(self) -> bool:
        return bool(self.flags & FLAG_FALLBACK_ARGMAX)

    @property
    def entropy_fail(self) -> bool:
        return bool(self.flags & FLAG_ENTROPY_FAIL)

    def to_dict(self) -> dict:
        return {
            "token_id": self.token_id,
            "draw_u": self.draw_u,
            "total_weight": self.total_weight,
            "fallback_argmax": self.fallback_argmax,
            "entropy_fail": self.entropy_fail,
        }


def parse_sample(frame: Frame) -> SampleResult:
    if frame.kind != RSP_TOKEN:
        raise ProtocolError(f"expected a token reply, got {frame.kind:#04x}")
    if len(frame.payload) != 11:
        raise ProtocolError(f"token reply should be 11 bytes, got {len(frame.payload)}")
    token, draw_u, total = struct.unpack_from("<HII", frame.payload, 0)
    return SampleResult(
        token_id=token,
        draw_u=draw_u,
        total_weight=total,
        flags=frame.payload[10],
    )


@dataclass
class StatusResult:
    flags: int
    last_token: int
    rx_errors: int

    def to_dict(self) -> dict:
        return {
            "last_token": self.last_token,
            "rx_errors": self.rx_errors,
            "fallback_argmax": bool(self.flags & FLAG_FALLBACK_ARGMAX),
            "entropy_fail": bool(self.flags & FLAG_ENTROPY_FAIL),
            "rx_frame_error": bool(self.flags & FLAG_RX_FRAME_ERROR),
        }


def parse_status(frame: Frame) -> StatusResult:
    if frame.kind != CMD_STATUS:
        raise ProtocolError(f"expected a status reply, got {frame.kind:#04x}")
    if len(frame.payload) != 4:
        raise ProtocolError(f"status reply should be 4 bytes, got {len(frame.payload)}")
    return StatusResult(
        flags=frame.payload[0],
        last_token=struct.unpack_from("<H", frame.payload, 1)[0],
        rx_errors=frame.payload[3],
    )


# ---------------------------------------------------------------------------
# Reference model
# ---------------------------------------------------------------------------

def hardware_probability(deficit_q88: int) -> float:
    """Probability the RTL's AND-reduce fires for a given deficit.

    Reproduces ``fire = &(cbit | ~deficit)`` exactly: the product of the Q0.16
    constants selected by the set bits of the deficit. Used to predict the
    device's distribution and to quantify the error against true softmax.
    """
    if deficit_q88 <= 0:
        return 1.0
    p = 1.0
    for j in range(16):
        if deficit_q88 & (1 << j):
            p *= EXP_CONSTS[j] / 65536.0
    return p


def reference_distribution(
    logits: Sequence[float], k: int = DEFAULT_K
) -> list[float]:
    """The categorical distribution the FPGA actually samples from.

    This is *not* exact softmax: it is softmax as quantised by Q8.8 logits and
    the Q0.16 exponential constants. Comparing hardware histograms against this
    is how we tell a wiring bug from expected quantisation error.
    """
    if not logits:
        return []
    raw = [float_to_q88(v) for v in logits[:k]]
    lmax = max(raw)
    weights = [hardware_probability(lmax - r) for r in raw]
    total = sum(weights)
    if total <= 0.0:
        out = [0.0] * len(weights)
        out[raw.index(lmax)] = 1.0
        return out
    return [w / total for w in weights]


def softmax(logits: Sequence[float]) -> list[float]:
    """Plain float softmax, for measuring the hardware's approximation error."""
    if not logits:
        return []
    m = max(logits)
    exps = [math.exp(v - m) for v in logits]
    total = sum(exps)
    return [e / total for e in exps]


def inverse_cdf_pick(counts: Sequence[int], draw_u: int) -> int:
    """Host-side mirror of the sampler's S_SCAN state.

    First index whose prefix sum is strictly greater than ``draw_u`` wins.
    """
    acc = 0
    for i, c in enumerate(counts):
        acc += c
        if acc > draw_u:
            return i
    return max(0, len(counts) - 1)
