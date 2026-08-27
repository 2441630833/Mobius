"""Statistical tests for a probabilistic circuit.

The point of this hardware is that its output is random, which makes "does it
work?" a statistical question rather than a functional one. A sampler with a
swapped logit byte or a dead oscillator still answers every frame; only a
distribution test notices.

Stdlib only, deliberately: these functions are imported by the unit tests,
which run against a bare system interpreter with no venv. That rules out
scipy, so the incomplete gamma function is implemented here.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Sequence

# ---------------------------------------------------------------------------
# Chi-square tail probability
# ---------------------------------------------------------------------------

_MAX_ITER = 300
_EPS = 3.0e-12


def _gamma_series(a: float, x: float) -> float:
    """Lower regularized incomplete gamma P(a, x) by series expansion."""
    term = 1.0 / a
    total = term
    ap = a
    for _ in range(_MAX_ITER):
        ap += 1.0
        term *= x / ap
        total += term
        if abs(term) < abs(total) * _EPS:
            break
    return total * math.exp(-x + a * math.log(x) - math.lgamma(a))


def _gamma_cf(a: float, x: float) -> float:
    """Upper regularized incomplete gamma Q(a, x) by continued fraction."""
    tiny = 1.0e-300
    b = x + 1.0 - a
    c = 1.0 / tiny
    d = 1.0 / b
    h = d
    for i in range(1, _MAX_ITER + 1):
        an = -i * (i - a)
        b += 2.0
        d = an * d + b
        if abs(d) < tiny:
            d = tiny
        c = b + an / c
        if abs(c) < tiny:
            c = tiny
        d = 1.0 / d
        delta = d * c
        h *= delta
        if abs(delta - 1.0) < _EPS:
            break
    return h * math.exp(-x + a * math.log(x) - math.lgamma(a))


def chi2_sf(x: float, df: int) -> float:
    """P(chi-square with `df` degrees of freedom > x).

    Returns 1.0 for a degenerate test (df <= 0) so callers treat "nothing to
    test" as "no evidence of a problem" rather than as a failure.
    """
    if df <= 0:
        return 1.0
    if x <= 0.0:
        return 1.0
    a = df / 2.0
    z = x / 2.0
    if z < a + 1.0:
        return max(0.0, min(1.0, 1.0 - _gamma_series(a, z)))
    return max(0.0, min(1.0, _gamma_cf(a, z)))


def normal_sf(z: float) -> float:
    """Two-sided tail probability for a standard normal deviate."""
    return math.erfc(abs(z) / math.sqrt(2.0))


# ---------------------------------------------------------------------------
# Distribution comparison
# ---------------------------------------------------------------------------


@dataclass
class GoodnessOfFit:
    n: int
    chi_square: float
    degrees_of_freedom: int
    p_value: float
    max_abs_deviation: float
    total_variation: float
    pooled_bins: int
    tested_bins: int

    @property
    def consistent(self) -> bool:
        """True when the observed counts are consistent with the model.

        p >= 0.001 is deliberately permissive: this gate exists to catch a
        wrong distribution (wired-up bug), not to certify randomness quality.
        A tighter threshold would flake on legitimate runs.
        """
        return self.degrees_of_freedom <= 0 or self.p_value >= 0.001

    def to_dict(self) -> dict:
        return {
            "samples": self.n,
            "chi_square": round(self.chi_square, 4),
            "degrees_of_freedom": self.degrees_of_freedom,
            "p_value": round(self.p_value, 6),
            "max_abs_deviation": round(self.max_abs_deviation, 6),
            "total_variation_distance": round(self.total_variation, 6),
            "bins_tested": self.tested_bins,
            "bins_pooled_as_rare": self.pooled_bins,
            "consistent_with_model": self.consistent,
        }


def goodness_of_fit(
    counts: Sequence[int], expected_probs: Sequence[float]
) -> GoodnessOfFit:
    """Pearson chi-square of observed counts against a reference distribution.

    Bins whose expected count is below 5 are pooled into a single residual bin
    instead of being dropped. Dropping them is the common shortcut and it hides
    exactly the failure we care about: probability mass leaking into candidates
    the model says are unreachable.
    """
    n = sum(counts)
    k = min(len(counts), len(expected_probs))
    if n == 0 or k == 0:
        return GoodnessOfFit(n, 0.0, 0, 1.0, 0.0, 0.0, 0, 0)

    chi2 = 0.0
    tested = 0
    pooled_obs = 0
    pooled_exp = 0.0
    max_dev = 0.0
    tv = 0.0

    for i in range(k):
        observed = counts[i]
        p = expected_probs[i]
        exp_count = p * n
        max_dev = max(max_dev, abs(observed / n - p))
        tv += abs(observed / n - p)
        if exp_count >= 5.0:
            chi2 += (observed - exp_count) ** 2 / exp_count
            tested += 1
        else:
            pooled_obs += observed
            pooled_exp += exp_count

    pooled_bins = k - tested
    if pooled_bins:
        # An empty rare-bin group with zero observations is a perfect match,
        # not a division by zero.
        if pooled_exp > 0.0:
            chi2 += (pooled_obs - pooled_exp) ** 2 / pooled_exp
        elif pooled_obs > 0:
            # The model assigns zero probability but the device produced tokens
            # there. That is a hard contradiction, not a rounding artefact.
            chi2 = float("inf")
        tested += 1

    # One constraint is lost to normalising the counts.
    df = max(0, tested - 1)
    p_value = 0.0 if chi2 == float("inf") else chi2_sf(chi2, df)

    return GoodnessOfFit(
        n=n,
        chi_square=chi2,
        degrees_of_freedom=df,
        p_value=p_value,
        max_abs_deviation=max_dev,
        total_variation=tv / 2.0,
        pooled_bins=pooled_bins,
        tested_bins=tested,
    )


# ---------------------------------------------------------------------------
# Entropy source tests
# ---------------------------------------------------------------------------


def _longest_run(bits: Sequence[int]) -> int:
    best = run = 0
    prev = -1
    for b in bits:
        run = run + 1 if b == prev else 1
        prev = b
        best = max(best, run)
    return best


def entropy_report(data: bytes) -> dict:
    """Health tests on a raw TRNG byte stream.

    These are the cheap online tests, not a certification suite. They catch a
    stuck oscillator, a broken debiaser and gross correlation -- the failure
    modes that actually happen -- and the report says so rather than implying
    the source passed NIST SP 800-90B.
    """
    n_bytes = len(data)
    if n_bytes == 0:
        return {"ok": False, "error": "no entropy bytes captured"}

    bits = [(byte >> i) & 1 for byte in data for i in range(8)]
    n = len(bits)
    ones = sum(bits)

    # Monobit: under H0 the count is Binomial(n, 1/2).
    z_mono = (ones - n / 2) / math.sqrt(n / 4) if n else 0.0
    p_mono = normal_sf(z_mono)

    # Serial correlation between adjacent bits catches a source that is
    # oscillating rather than random -- a pattern monobit is blind to.
    transitions = sum(1 for a, b in zip(bits, bits[1:]) if a != b)
    expected_tr = (n - 1) / 2
    z_serial = (
        (transitions - expected_tr) / math.sqrt((n - 1) / 4) if n > 1 else 0.0
    )
    p_serial = normal_sf(z_serial)

    # Byte-frequency chi-square. Only meaningful once every bin can expect a
    # handful of hits, so it is reported as skipped rather than as a pass.
    hist = [0] * 256
    for byte in data:
        hist[byte] += 1
    byte_test: dict = {"applicable": n_bytes >= 2560}
    if byte_test["applicable"]:
        exp = n_bytes / 256.0
        chi2 = sum((h - exp) ** 2 / exp for h in hist)
        byte_test.update(
            chi_square=round(chi2, 3),
            degrees_of_freedom=255,
            p_value=round(chi2_sf(chi2, 255), 6),
        )
    else:
        byte_test["note"] = (
            f"need >= 2560 bytes for a 256-bin test, have {n_bytes}"
        )

    # Shannon entropy of the byte distribution, plus the min-entropy implied by
    # the observed bit bias. Min-entropy is the conservative figure and the one
    # that matters for sampling quality.
    shannon = 0.0
    for h in hist:
        if h:
            p = h / n_bytes
            shannon -= p * math.log2(p)
    p_bias = max(ones / n, 1 - ones / n)
    min_entropy_per_bit = -math.log2(p_bias)

    longest = _longest_run(bits)
    # P(no run >= L) is well approximated by this bound; a debiased source
    # should not produce long runs.
    run_limit = int(math.ceil(math.log2(n))) + 6

    checks = {
        "monobit": p_mono >= 0.001,
        "serial_correlation": p_serial >= 0.001,
        "longest_run": longest <= run_limit,
    }
    if byte_test["applicable"]:
        checks["byte_frequency"] = byte_test["p_value"] >= 0.001

    return {
        "ok": all(checks.values()),
        "bytes": n_bytes,
        "bits": n,
        "ones_fraction": round(ones / n, 6),
        "monobit": {"z": round(z_mono, 4), "p_value": round(p_mono, 6)},
        "serial_correlation": {
            "transition_fraction": round(transitions / max(1, n - 1), 6),
            "z": round(z_serial, 4),
            "p_value": round(p_serial, 6),
        },
        "byte_frequency": byte_test,
        "shannon_bits_per_byte": round(shannon, 4),
        "min_entropy_bits_per_bit": round(min_entropy_per_bit, 4),
        "longest_run": longest,
        "longest_run_limit": run_limit,
        "checks": checks,
        "note": (
            "Online health tests only (monobit, serial correlation, run length). "
            "Not a NIST SP 800-90B assessment -- that needs a much larger capture "
            "and the reference tool."
        ),
    }
