"""Token sampling against the physical device.

This is the layer the agent actually uses in the generation loop. It owns the
serial link's lifetime, converts host logits into device frames, and -- most
importantly -- reports what the hardware did *next to* what the reference model
says it should have done.

That comparison is the whole point. A token id on its own is unfalsifiable: a
sampler with a dead entropy source returns argmax every time and looks perfect.
Returning the model probability of the drawn token, the entropy health flags,
and (for a batch) a goodness-of-fit p-value is what makes the result checkable.
"""

from __future__ import annotations

import time
from typing import Sequence

from . import config, protocol, stats
from .protocol import DeviceError, ProtocolError
from .uart import SamplerLink, TransportError, open_link

# A cached link, because reopening a serial port costs ~100 ms and a generation
# loop calls this once per token. The cache is validated before reuse rather
# than trusted: a board can be unplugged between calls.
_link: SamplerLink | None = None
_link_port: str | None = None


def close_link() -> dict:
    """Drop the cached serial link. Safe to call when nothing is open."""
    global _link, _link_port
    was = _link_port
    if _link is not None:
        _link.close()
    _link = None
    _link_port = None
    return {"ok": True, "closed": was}


def _open(port: str | None, baud: int | None, timeout: float) -> SamplerLink:
    global _link, _link_port
    link = open_link(port=port, baud=baud, timeout=timeout)
    _link = link
    _link_port = link.port
    return link


def get_link(
    port: str | None = None,
    baud: int | None = None,
    timeout: float = 5.0,
    reuse: bool = True,
) -> SamplerLink:
    """Return a live link, reopening if the cached one has gone away.

    Reuse is validated with a ping, not assumed. If the ping fails the port is
    closed and reopened once; a second failure is a real blocker and is raised.
    """
    global _link
    if not reuse:
        close_link()
        return _open(port, baud, timeout)

    if _link is not None and (port is None or port == _link_port):
        try:
            _link.ping()
            return _link
        except (TransportError, ProtocolError, OSError):
            close_link()

    return _open(port, baud, timeout)


def _device_window(link: SamplerLink) -> int:
    """K as reported by the bitstream, not as assumed by the host.

    A mismatched K is a silent corruption: the device would read our logits at
    the wrong stride. Asking is cheap.
    """
    try:
        return link.ping().k or protocol.DEFAULT_K
    except (TransportError, ProtocolError):
        return protocol.DEFAULT_K


def _blocked(exc: Exception, stage: str) -> dict:
    hints = {
        TransportError: (
            "Check the USB cable and that no serial terminal is holding the port. "
            "Run fpga_detect to see which ports are visible."
        ),
        DeviceError: (
            "The bitstream rejected the frame. If this is ERR_LENGTH the host and "
            "device disagree on K -- re-run fpga_synthesize and fpga_flash."
        ),
        ProtocolError: (
            "Frame decode failed. Usually a baud mismatch or a stale bitstream; "
            "re-flash and retry."
        ),
    }
    return {
        "ok": False,
        "stage": stage,
        "error": str(exc),
        "error_type": type(exc).__name__,
        "hint": hints.get(type(exc), "Run fpga_detect for a full toolchain report."),
    }


def device_info(port: str | None = None, baud: int | None = None) -> dict:
    """Identify the running bitstream."""
    try:
        link = get_link(port=port, baud=baud)
        info = link.ping()
        status = link.status()
    except (TransportError, ProtocolError) as exc:
        return _blocked(exc, "connect")

    return {
        "ok": True,
        "port": link.port,
        "baud": link.baud,
        "firmware_version": info.version,
        "candidate_window": info.k,
        "logit_width_bits": info.logit_width,
        "stochastic_stream_log2": info.sc_log2,
        "stochastic_stream_cycles": 1 << info.sc_log2,
        "entropy_ok": info.entropy_ok,
        "status": status.to_dict(),
    }


def sample_token(
    logits: Sequence[float],
    port: str | None = None,
    baud: int | None = None,
    timeout: float = 10.0,
) -> dict:
    """Draw one token from the FPGA.

    Returns the token together with the reference model's probability for it, so
    a wrong answer is visible rather than plausible.
    """
    if not logits:
        return {"ok": False, "stage": "input", "error": "logits vector is empty"}

    try:
        link = get_link(port=port, baud=baud, timeout=timeout)
        k = _device_window(link)
        if len(logits) > k:
            return {
                "ok": False,
                "stage": "input",
                "error": (
                    f"{len(logits)} logits exceed the device window K={k}. "
                    "Send a top-K slice and map the index back on the host."
                ),
            }
        started = time.monotonic()
        result = link.sample(logits, k=k)
        elapsed = time.monotonic() - started
    except (TransportError, ProtocolError) as exc:
        return _blocked(exc, "sample")

    if result.token_id >= len(logits):
        # The device padded the window with -128.0 logits, which the model
        # gives probability ~0. Landing there means something is wrong.
        return {
            "ok": False,
            "stage": "sample",
            "error": (
                f"device returned token {result.token_id} but only {len(logits)} "
                "logits were supplied — it sampled a padding slot"
            ),
            "raw": result.to_dict(),
        }

    reference = protocol.reference_distribution(logits, k=k)
    exact = protocol.softmax(logits)
    return {
        "ok": True,
        "stage": "sample",
        "token_id": result.token_id,
        "token_probability_model": round(reference[result.token_id], 8),
        "token_probability_softmax": round(exact[result.token_id], 8),
        "draw_u": result.draw_u,
        "total_weight": result.total_weight,
        "fallback_argmax": result.fallback_argmax,
        "entropy_fail": result.entropy_fail,
        "latency_ms": round(elapsed * 1000, 2),
        "port": link.port,
        "warnings": _warnings(result, reference),
    }


def _warnings(result: protocol.SampleResult, reference: Sequence[float]) -> list[str]:
    out: list[str] = []
    if result.entropy_fail:
        out.append(
            "TRNG health check failed: the ring oscillators look stuck, so this "
            "token is not physically random. Power-cycle the board and re-run "
            "fpga_trng_entropy."
        )
    if result.fallback_argmax:
        out.append(
            "Sampler fell back to argmax: the accumulated weight was zero, which "
            "happens when every candidate is far below the max logit. Sharpen or "
            "rescale the logits."
        )
    if result.total_weight == 0:
        out.append("total_weight is 0 — the stochastic accumulation produced nothing.")
    p = reference[result.token_id] if result.token_id < len(reference) else 0.0
    if p == 0.0:
        out.append(
            "The reference model assigns this token probability 0. Host and device "
            "disagree; suspect a stale bitstream or a protocol change."
        )
    return out


def sample_sequence(
    steps: Sequence[Sequence[float]],
    port: str | None = None,
    baud: int | None = None,
    timeout: float = 10.0,
    stop_on_error: bool = True,
) -> dict:
    """Draw one token per step over a single open link.

    Intended for the generate loop: the host produces logits for step t, the
    FPGA samples, the host appends and produces step t+1. Reusing the link
    matters -- reopening the port per token dominates the latency.
    """
    if not steps:
        return {"ok": False, "stage": "input", "error": "no logit steps supplied"}

    tokens: list[int] = []
    records: list[dict] = []
    started = time.monotonic()

    for index, logits in enumerate(steps):
        record = sample_token(logits, port=port, baud=baud, timeout=timeout)
        record["step"] = index
        records.append(record)
        if not record.get("ok"):
            if stop_on_error:
                return {
                    "ok": False,
                    "stage": "sample",
                    "error": f"step {index} failed: {record.get('error')}",
                    "tokens": tokens,
                    "steps": records,
                }
            continue
        tokens.append(record["token_id"])

    elapsed = time.monotonic() - started
    return {
        "ok": all(r.get("ok") for r in records),
        "stage": "sample",
        "tokens": tokens,
        "steps": records,
        "count": len(tokens),
        "total_ms": round(elapsed * 1000, 2),
        "mean_ms_per_token": round(elapsed * 1000 / max(1, len(tokens)), 2),
    }


def verify_distribution(
    logits: Sequence[float],
    samples: int = 400,
    port: str | None = None,
    baud: int | None = None,
    timeout: float = 10.0,
) -> dict:
    """Draw repeatedly from one fixed logit vector and test the histogram.

    This is the acceptance test for a freshly flashed bitstream. A functional
    check ("it answered") passes even when the sampler is systematically wrong;
    this does not.
    """
    if not logits:
        return {"ok": False, "stage": "input", "error": "logits vector is empty"}
    if samples < 30:
        return {
            "ok": False,
            "stage": "input",
            "error": f"{samples} samples is too few to test a distribution; use >= 30",
        }

    try:
        link = get_link(port=port, baud=baud, timeout=timeout)
        k = _device_window(link)
    except (TransportError, ProtocolError) as exc:
        return _blocked(exc, "connect")

    counts = [0] * len(logits)
    failures: list[str] = []
    entropy_fail_seen = False
    fallback_seen = 0
    started = time.monotonic()

    for i in range(samples):
        try:
            result = link.sample(logits, k=k)
        except (TransportError, ProtocolError) as exc:
            failures.append(f"sample {i}: {exc}")
            if len(failures) > 5:
                break
            continue
        entropy_fail_seen = entropy_fail_seen or result.entropy_fail
        fallback_seen += 1 if result.fallback_argmax else 0
        if result.token_id < len(counts):
            counts[result.token_id] += 1
        else:
            failures.append(f"sample {i}: token {result.token_id} outside the logit vector")

    elapsed = time.monotonic() - started
    expected = protocol.reference_distribution(logits, k=k)
    fit = stats.goodness_of_fit(counts, expected)

    observed_total = sum(counts)
    return {
        # "Consistent with the model" is the pass condition, not "no errors".
        "ok": fit.consistent and not failures and observed_total > 0,
        "stage": "verify",
        "port": link.port,
        "samples_requested": samples,
        "samples_collected": observed_total,
        "histogram": {i: c for i, c in enumerate(counts) if c},
        "expected_distribution": {
            i: round(p, 6) for i, p in enumerate(expected) if p > 1e-9
        },
        "fit": fit.to_dict(),
        "entropy_fail_seen": entropy_fail_seen,
        "fallback_argmax_count": fallback_seen,
        "failures": failures,
        "elapsed_s": round(elapsed, 2),
        "interpretation": _fit_interpretation(fit, entropy_fail_seen, fallback_seen),
    }


def _fit_interpretation(
    fit: stats.GoodnessOfFit, entropy_fail: bool, fallback: int
) -> str:
    if entropy_fail:
        return (
            "TRNG health check tripped during the run. Any agreement here is "
            "meaningless — fix the entropy source first."
        )
    if fallback:
        return (
            f"{fallback} draws fell back to argmax, so the histogram is biased "
            "toward the top logit by construction."
        )
    if fit.degrees_of_freedom <= 0:
        return (
            "Only one candidate had meaningful probability, so there is nothing "
            "to test. Use a flatter logit vector."
        )
    if fit.consistent:
        return (
            f"Histogram matches the quantised-softmax model (p={fit.p_value:.4f}, "
            f"TVD={fit.total_variation:.4f}). The sampler is behaving correctly."
        )
    return (
        f"Histogram does NOT match the model (p={fit.p_value:.6f}, "
        f"TVD={fit.total_variation:.4f}). Suspect logit byte order, a stale "
        "bitstream, or a changed exponent table."
    )


def trng_entropy(
    n_bytes: int = 256,
    port: str | None = None,
    baud: int | None = None,
    timeout: float = 20.0,
) -> dict:
    """Capture whitened TRNG bytes and run the online health tests."""
    n_bytes = max(1, min(n_bytes, protocol.RAW_MAX))
    try:
        link = get_link(port=port, baud=baud, timeout=timeout)
        started = time.monotonic()
        data = link.raw_entropy(n_bytes)
        elapsed = time.monotonic() - started
        status = link.status()
    except (TransportError, ProtocolError) as exc:
        return _blocked(exc, "entropy")

    report = stats.entropy_report(data)
    report.update(
        stage="entropy",
        port=link.port,
        requested_bytes=n_bytes,
        throughput_bytes_per_s=round(len(data) / elapsed, 1) if elapsed > 0 else None,
        device_status=status.to_dict(),
        sample_hex=data[:32].hex(),
    )
    # The device's own sticky health flag outranks our sample-based tests.
    if status.to_dict().get("entropy_fail"):
        report["ok"] = False
        report["error"] = (
            "Device reports entropy_fail. The ring oscillators are not producing "
            "varying bits; the LFSR simulation model may be compiled in instead "
            "of real fabric rings."
        )
    return report


def self_test(
    port: str | None = None, baud: int | None = None, samples: int = 200
) -> dict:
    """End-to-end check of an attached board.

    Runs the chain in dependency order and stops at the first hard failure, so
    the report names the actual blocker instead of a cascade of symptoms.
    """
    steps: list[dict] = []

    info = device_info(port=port, baud=baud)
    steps.append({"step": "identify", **info})
    if not info.get("ok"):
        return {"ok": False, "stage": "identify", "steps": steps}

    entropy = trng_entropy(128, port=port, baud=baud)
    steps.append({"step": "entropy", **entropy})

    # A deliberately uneven vector: one clear favourite, a few contenders, and a
    # tail the exponent table rounds to zero. A flat vector would pass even with
    # the logit bytes swapped.
    logits = [0.0] * info["candidate_window"]
    for i, value in ((0, 2.0), (1, 1.25), (2, 0.75), (3, 0.25)):
        if i < len(logits):
            logits[i] = value
    for i in range(4, len(logits)):
        logits[i] = -20.0

    single = sample_token(logits, port=port, baud=baud)
    steps.append({"step": "single_sample", **single})
    if not single.get("ok"):
        return {"ok": False, "stage": "single_sample", "steps": steps}

    verify = verify_distribution(logits, samples=samples, port=port, baud=baud)
    steps.append({"step": "distribution", **verify})

    ok = bool(info.get("ok") and single.get("ok") and verify.get("ok") and entropy.get("ok"))
    return {
        "ok": ok,
        "stage": "self_test",
        "summary": (
            "Board identified, entropy healthy, and the sampled distribution "
            "matches the model."
            if ok
            else "See the failing step below; each one reports its own blocker."
        ),
        "steps": steps,
    }
