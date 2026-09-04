"""Roofline model tests.

The Redwood lesson applied to this loop: write the theoretical ceiling down
*before* touching hardware, then let fpga_sample_sequence's measured
mean_ms_per_token calibrate it. These tests keep the model locked to the wire
format so a framing change moves the ceiling with it instead of silently
reporting a stale number.
"""

from __future__ import annotations

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "mcp"))

from custom_fpga_mcp import perf_model, protocol  # noqa: E402


class TestFrameBytes(unittest.TestCase):
    def test_sample_frame_is_five_plus_two_per_candidate(self):
        # The one assertion that ties the model to the codec: if framing ever
        # drifts, this fails loudly instead of the model quietly lying.
        for k in (1, 2, 8, 32, 64):
            frame = protocol.encode_sample([0.0] * k, k=k)
            self.assertEqual(len(frame), perf_model.sample_frame_bytes(k))
            self.assertEqual(len(frame), 5 + 2 * k)

    def test_k_bounds(self):
        for k in (0, 65, -3):
            with self.assertRaises(ValueError):
                perf_model.sample_frame_bytes(k)

    def test_token_reply_matches_codec(self):
        # Keep the reply width honest: parse_sample demands exactly 11 payload
        # bytes, so the model must charge for them.
        import struct

        payload = struct.pack("<HII", 0, 0, 0) + bytes([0])
        self.assertEqual(len(payload), 11)
        self.assertEqual(perf_model.TOKEN_REPLY_FRAME_BYTES, 5 + len(payload))


class TestStepBudget(unittest.TestCase):
    def test_defaults_match_device_protocol(self):
        b = perf_model.step_budget()
        self.assertEqual(b["k"], protocol.DEFAULT_K)
        self.assertEqual(b["sc_log2"], protocol.DEFAULT_SC_LOG2)

    def test_stages_are_serial(self):
        # No work hidden across operator boundaries: total == sum of stages.
        b = perf_model.step_budget(k=8, baud=115200, host_overhead_ms=1.0)
        expected = b["tx_ms"] + b["stream_ms"] + b["rx_ms"] + b["host_ms"]
        self.assertAlmostEqual(b["total_ms"], expected, places=6)
        self.assertTrue(b["serial_stages"])

    def test_uart_dominates_at_low_baud(self):
        b = perf_model.step_budget(k=64, baud=115200)
        self.assertEqual(b["bottleneck"], "uart_tx")

    def test_k_is_the_lever(self):
        # Halving K roughly halves the tx term, so the sweep's whole point is
        # that K trades tail probability for throughput.
        k64 = perf_model.step_budget(k=64, baud=115200)
        k8 = perf_model.step_budget(k=8, baud=115200)
        self.assertGreater(k64["tx_ms"], k8["tx_ms"] * 4)

    def test_fast_stream_makes_baud_king(self):
        # At default sc_log2 the stream is tiny; the model must say the UART
        # rules so nobody optimises the FPGA side first.
        b = perf_model.step_budget(k=32)
        self.assertIn(b["bottleneck"], ("uart_tx", "uart_rx"))

    def test_bad_baud_rejected(self):
        with self.assertRaises(ValueError):
            perf_model.step_budget(baud=0)
        with self.assertRaises(ValueError):
            perf_model.step_budget(baud=13_000_000)

    def test_estimate_is_flagged_not_measured(self):
        self.assertIn("Model estimate", perf_model.step_budget()["note"])


class TestTable(unittest.TestCase):
    def test_sweep_rows_cover_the_defaults(self):
        t = perf_model.table()
        self.assertEqual([r["k"] for r in t["rows"]], list(perf_model.TABLE_K_DEFAULT))

    def test_single_k_returns_one_row(self):
        t = perf_model.table(k=16)
        self.assertEqual(len(t["rows"]), 1)
        self.assertEqual(t["rows"][0]["k"], 16)

    def test_rows_are_stage_honest(self):
        for row in perf_model.table()["rows"]:
            self.assertAlmostEqual(
                row["total_ms"],
                row["tx_ms"] + row["stream_ms"] + row["rx_ms"] + row["host_ms"],
                places=6,
            )


if __name__ == "__main__":
    unittest.main()
