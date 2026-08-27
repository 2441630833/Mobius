"""Tests for the statistical machinery.

The sampler's correctness verdict rests entirely on these functions, so they
need to be right in both directions: they must accept a correct sampler (no
flaky CI) and reject a wrong one (no false confidence). Each test below pins one
of those two properties.
"""

from __future__ import annotations

import math
import os
import random
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "mcp"))

from custom_fpga_mcp import stats  # noqa: E402


class TestChiSquareTail(unittest.TestCase):
    """chi2_sf replaces scipy, so it has to be checked against known values."""

    def test_known_critical_values(self):
        # Standard 5% critical points; the tail there is 0.05 by definition.
        for df, critical in ((1, 3.8415), (2, 5.9915), (5, 11.0705), (10, 18.3070)):
            self.assertAlmostEqual(stats.chi2_sf(critical, df), 0.05, delta=1e-3, msg=f"df={df}")

    def test_one_percent_critical_values(self):
        for df, critical in ((1, 6.6349), (5, 15.0863), (20, 37.5662)):
            self.assertAlmostEqual(stats.chi2_sf(critical, df), 0.01, delta=1e-3, msg=f"df={df}")

    def test_monotonic_decreasing(self):
        previous = 1.0
        for x in [i * 0.5 for i in range(1, 80)]:
            p = stats.chi2_sf(x, 4)
            self.assertLessEqual(p, previous + 1e-12)
            previous = p

    def test_bounds(self):
        self.assertEqual(stats.chi2_sf(0.0, 5), 1.0)
        self.assertEqual(stats.chi2_sf(-1.0, 5), 1.0)
        self.assertLess(stats.chi2_sf(500.0, 5), 1e-12)

    def test_degenerate_df_is_not_a_failure(self):
        # Nothing to test must read as "no evidence of a problem".
        self.assertEqual(stats.chi2_sf(10.0, 0), 1.0)

    def test_normal_tail(self):
        self.assertAlmostEqual(stats.normal_sf(1.959964), 0.05, delta=1e-5)
        self.assertAlmostEqual(stats.normal_sf(2.575829), 0.01, delta=1e-5)
        self.assertAlmostEqual(stats.normal_sf(0.0), 1.0, delta=1e-12)


class TestGoodnessOfFit(unittest.TestCase):
    def test_accepts_samples_from_the_model(self):
        # A correct sampler must not be flagged. Fixed seed keeps CI stable.
        rng = random.Random(20260825)
        probs = [0.4, 0.3, 0.2, 0.1]
        counts = [0] * 4
        for _ in range(4000):
            counts[rng.choices(range(4), weights=probs)[0]] += 1
        fit = stats.goodness_of_fit(counts, probs)
        self.assertTrue(fit.consistent, fit.to_dict())
        self.assertGreater(fit.p_value, 0.001)
        self.assertLess(fit.total_variation, 0.05)

    def test_rejects_a_shifted_distribution(self):
        # The classic bug this must catch: an off-by-one shifts the whole
        # histogram by one candidate.
        rng = random.Random(7)
        probs = [0.4, 0.3, 0.2, 0.1]
        shifted = [0.1, 0.4, 0.3, 0.2]
        counts = [0] * 4
        for _ in range(4000):
            counts[rng.choices(range(4), weights=shifted)[0]] += 1
        fit = stats.goodness_of_fit(counts, probs)
        self.assertFalse(fit.consistent, fit.to_dict())

    def test_rejects_a_stuck_sampler(self):
        # A dead entropy source returns argmax every time. Functionally fine,
        # statistically catastrophic.
        counts = [1000, 0, 0, 0]
        fit = stats.goodness_of_fit(counts, [0.4, 0.3, 0.2, 0.1])
        self.assertFalse(fit.consistent)
        self.assertAlmostEqual(fit.total_variation, 0.6, places=6)

    def test_mass_in_an_impossible_bin_is_a_hard_failure(self):
        # The model says probability 0 but the device produced tokens there.
        # Pooling rare bins must not let this slip through as "small expected".
        counts = [900, 100]
        fit = stats.goodness_of_fit(counts, [1.0, 0.0])
        self.assertFalse(fit.consistent)
        self.assertEqual(fit.p_value, 0.0)
        self.assertEqual(fit.chi_square, float("inf"))

    def test_empty_impossible_bin_is_a_perfect_match(self):
        counts = [1000, 0]
        fit = stats.goodness_of_fit(counts, [1.0, 0.0])
        self.assertTrue(fit.consistent)

    def test_rare_bins_are_pooled_not_dropped(self):
        probs = [0.5, 0.5] + [0.0] * 8
        counts = [500, 500] + [0] * 8
        fit = stats.goodness_of_fit(counts, probs)
        self.assertEqual(fit.pooled_bins, 8)
        self.assertTrue(fit.consistent)

    def test_no_samples_is_not_a_verdict(self):
        fit = stats.goodness_of_fit([0, 0, 0], [0.5, 0.3, 0.2])
        self.assertEqual(fit.n, 0)
        self.assertEqual(fit.degrees_of_freedom, 0)
        self.assertTrue(fit.consistent)

    def test_single_reachable_candidate_has_no_degrees_of_freedom(self):
        fit = stats.goodness_of_fit([500], [1.0])
        self.assertEqual(fit.degrees_of_freedom, 0)
        self.assertTrue(fit.consistent)

    def test_max_deviation_is_reported(self):
        fit = stats.goodness_of_fit([600, 400], [0.5, 0.5])
        self.assertAlmostEqual(fit.max_abs_deviation, 0.1, places=9)


class TestEntropyReport(unittest.TestCase):
    def test_accepts_good_randomness(self):
        rng = random.Random(1234)
        data = bytes(rng.getrandbits(8) for _ in range(512))
        report = stats.entropy_report(data)
        self.assertTrue(report["ok"], report)
        self.assertGreater(report["min_entropy_bits_per_bit"], 0.9)
        self.assertAlmostEqual(report["ones_fraction"], 0.5, delta=0.05)

    def test_rejects_all_zeros(self):
        # A stuck oscillator: the exact failure mode the health check exists for.
        report = stats.entropy_report(bytes(256))
        self.assertFalse(report["ok"])
        self.assertFalse(report["checks"]["monobit"])
        self.assertEqual(report["ones_fraction"], 0.0)
        self.assertEqual(report["min_entropy_bits_per_bit"], 0.0)

    def test_rejects_all_ones(self):
        report = stats.entropy_report(b"\xff" * 256)
        self.assertFalse(report["ok"])
        self.assertFalse(report["checks"]["monobit"])

    def test_rejects_alternating_bits(self):
        # Perfectly balanced, so monobit passes -- only the serial-correlation
        # test catches an oscillating source.
        report = stats.entropy_report(b"\xaa" * 256)
        self.assertAlmostEqual(report["ones_fraction"], 0.5, delta=1e-9)
        self.assertTrue(report["checks"]["monobit"])
        self.assertFalse(report["checks"]["serial_correlation"])
        self.assertFalse(report["ok"])

    def test_rejects_a_long_constant_run(self):
        rng = random.Random(99)
        data = bytearray(rng.getrandbits(8) for _ in range(256))
        data[64:112] = bytes(48)  # 384 identical bits
        report = stats.entropy_report(bytes(data))
        self.assertFalse(report["checks"]["longest_run"])
        self.assertFalse(report["ok"])

    def test_byte_frequency_test_is_skipped_when_undersampled(self):
        # 256 bytes over 256 bins is meaningless; the report must say skipped
        # rather than claim a pass.
        rng = random.Random(5)
        report = stats.entropy_report(bytes(rng.getrandbits(8) for _ in range(256)))
        self.assertFalse(report["byte_frequency"]["applicable"])
        self.assertNotIn("byte_frequency", report["checks"])
        self.assertIn("note", report["byte_frequency"])

    def test_byte_frequency_test_runs_when_large_enough(self):
        rng = random.Random(6)
        report = stats.entropy_report(bytes(rng.getrandbits(8) for _ in range(4096)))
        self.assertTrue(report["byte_frequency"]["applicable"])
        self.assertIn("byte_frequency", report["checks"])
        self.assertTrue(report["ok"], report)

    def test_empty_input_is_an_error_not_a_pass(self):
        report = stats.entropy_report(b"")
        self.assertFalse(report["ok"])
        self.assertIn("error", report)

    def test_does_not_claim_nist_compliance(self):
        # The report is used verbatim by the agent, so its own caveat matters.
        report = stats.entropy_report(bytes(range(256)))
        self.assertIn("800-90B", report["note"])

    def test_shannon_entropy_of_uniform_bytes(self):
        # Every byte value exactly once => exactly 8 bits per byte.
        report = stats.entropy_report(bytes(range(256)))
        self.assertAlmostEqual(report["shannon_bits_per_byte"], 8.0, places=6)


class TestSamplingErrorScale(unittest.TestCase):
    """Sanity-check the tolerance the testbench and verifier rely on.

    Both use ~4/sqrt(n) as a max-deviation bound. If that were tighter than the
    true sampling error, every honest run would fail.
    """

    def test_four_sigma_bound_holds_for_a_correct_sampler(self):
        rng = random.Random(31337)
        probs = [0.45, 0.28, 0.17, 0.10]
        n = 2000
        for trial in range(20):
            counts = [0] * 4
            for _ in range(n):
                counts[rng.choices(range(4), weights=probs)[0]] += 1
            max_dev = max(abs(c / n - p) for c, p in zip(counts, probs))
            self.assertLess(max_dev, 4.0 / math.sqrt(n), f"trial {trial}")


if __name__ == "__main__":
    unittest.main()
