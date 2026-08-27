"""Protocol codec tests.

These guard the one contract that cannot be checked by a compiler: the host's
framing in ``protocol.py`` and the RTL's framing in ``sampler_uart_top.v`` must
agree byte for byte. A drift here does not crash -- it silently returns wrong
tokens.

Stdlib unittest and no venv required, so this suite runs on a bare interpreter:

    python -m unittest discover -s chip-design/tests -v
"""

from __future__ import annotations

import os
import struct
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "mcp"))

from custom_fpga_mcp import protocol  # noqa: E402


class TestCrc8(unittest.TestCase):
    """CRC-8/ATM, cross-checked against known vectors.

    The RTL implements this bit-serially in `crc8_step`; if these vectors ever
    disagree with the hardware, the Verilog function is what changed.
    """

    def test_known_vectors(self):
        # Canonical CRC-8/ATM (poly 0x07, init 0x00, no reflection) check value.
        self.assertEqual(protocol.crc8(b"123456789"), 0xF4)
        self.assertEqual(protocol.crc8(b""), 0x00)
        self.assertEqual(protocol.crc8(b"\x00"), 0x00)

    def test_matches_independent_table_implementation(self):
        # Table-driven reimplementation of the same polynomial. A copy-paste bug
        # in the bit-serial loop would agree with itself but not with this.
        table = []
        for value in range(256):
            crc = value
            for _ in range(8):
                crc = ((crc << 1) ^ 0x07) & 0xFF if crc & 0x80 else (crc << 1) & 0xFF
            table.append(crc)

        def crc8_table(data: bytes) -> int:
            crc = 0
            for byte in data:
                crc = table[crc ^ byte]
            return crc

        for payload in (b"", b"\x01", b"\xff\x00", bytes(range(64)), b"123456789"):
            self.assertEqual(protocol.crc8(payload), crc8_table(payload), payload)

    def test_detects_single_bit_flips(self):
        payload = bytes(range(32))
        base = protocol.crc8(payload)
        for index in range(len(payload)):
            for bit in range(8):
                corrupted = bytearray(payload)
                corrupted[index] ^= 1 << bit
                self.assertNotEqual(
                    protocol.crc8(bytes(corrupted)),
                    base,
                    f"CRC missed a flip at byte {index} bit {bit}",
                )


class TestFraming(unittest.TestCase):
    def test_ping_frame_layout(self):
        frame = protocol.encode_ping()
        self.assertEqual(frame[0], protocol.SOF_HOST)
        self.assertEqual(frame[1], protocol.CMD_PING)
        self.assertEqual(struct.unpack_from("<H", frame, 2)[0], 0)
        self.assertEqual(len(frame), 5)
        self.assertEqual(frame[-1], protocol.crc8(frame[1:-1]))

    def test_sample_frame_is_two_bytes_per_candidate(self):
        frame = protocol.encode_sample([0.0] * 32, k=32)
        self.assertEqual(len(frame), 5 + 64)
        self.assertEqual(struct.unpack_from("<H", frame, 2)[0], 64)

    def test_sample_pads_short_vectors_to_the_device_window(self):
        # The RTL answers ERR_LENGTH for anything but exactly 2*K bytes, so the
        # host must pad rather than send a short frame.
        frame = protocol.encode_sample([1.0, 2.0], k=32)
        self.assertEqual(struct.unpack_from("<H", frame, 2)[0], 64)
        payload = frame[4:-1]
        self.assertEqual(struct.unpack_from("<h", payload, 0)[0], 256)
        self.assertEqual(struct.unpack_from("<h", payload, 2)[0], 512)
        # Padding must be a logit the model maps to probability zero.
        pad = struct.unpack_from("<h", payload, 4)[0]
        self.assertEqual(pad, protocol.float_to_q88(-128.0))
        self.assertEqual(protocol.hardware_probability(512 - pad), 0.0)

    def test_sample_rejects_oversized_vectors(self):
        with self.assertRaises(ValueError):
            protocol.encode_sample([0.0] * 33, k=32)

    def test_logits_are_little_endian_signed(self):
        frame = protocol.encode_sample([-1.0], k=1)
        self.assertEqual(frame[4:6], struct.pack("<h", -256))

    def test_raw_request_bounds(self):
        with self.assertRaises(ValueError):
            protocol.encode_raw(0)
        with self.assertRaises(ValueError):
            protocol.encode_raw(protocol.RAW_MAX + 1)
        self.assertEqual(len(protocol.encode_raw(16)), 7)


def _device_frame(kind: int, payload: bytes) -> bytes:
    body = bytes([kind]) + struct.pack("<H", len(payload)) + payload
    return bytes([protocol.SOF_FPGA]) + body + bytes([protocol.crc8(body)])


class TestParsing(unittest.TestCase):
    def test_round_trip_token_reply(self):
        payload = struct.pack("<HII", 7, 1234, 5678) + bytes([0])
        result = protocol.parse_sample(protocol.parse_frame(_device_frame(protocol.RSP_TOKEN, payload)))
        self.assertEqual(result.token_id, 7)
        self.assertEqual(result.draw_u, 1234)
        self.assertEqual(result.total_weight, 5678)
        self.assertFalse(result.fallback_argmax)
        self.assertFalse(result.entropy_fail)

    def test_token_reply_decodes_flags(self):
        flags = protocol.FLAG_FALLBACK_ARGMAX | protocol.FLAG_ENTROPY_FAIL
        payload = struct.pack("<HII", 0, 0, 0) + bytes([flags])
        result = protocol.parse_sample(protocol.parse_frame(_device_frame(protocol.RSP_TOKEN, payload)))
        self.assertTrue(result.fallback_argmax)
        self.assertTrue(result.entropy_fail)

    def test_ping_reply(self):
        payload = bytes([0x00, 0x01, 32, 16, 12, 0])
        info = protocol.parse_ping(protocol.parse_frame(_device_frame(protocol.CMD_PING, payload)))
        self.assertEqual(info.version, "1.0")
        self.assertEqual(info.k, 32)
        self.assertEqual(info.logit_width, 16)
        self.assertEqual(info.sc_log2, 12)
        self.assertTrue(info.entropy_ok)

    def test_status_reply(self):
        payload = bytes([protocol.FLAG_RX_FRAME_ERROR]) + struct.pack("<H", 5) + bytes([3])
        status = protocol.parse_status(protocol.parse_frame(_device_frame(protocol.CMD_STATUS, payload)))
        self.assertEqual(status.last_token, 5)
        self.assertEqual(status.rx_errors, 3)
        self.assertTrue(status.to_dict()["rx_frame_error"])

    def test_error_frame_raises_device_error(self):
        frame = _device_frame(protocol.RSP_ERROR, bytes([protocol.ERR_LENGTH]))
        with self.assertRaises(protocol.DeviceError) as ctx:
            protocol.parse_frame(frame)
        self.assertEqual(ctx.exception.code, protocol.ERR_LENGTH)
        self.assertIn("length", str(ctx.exception))

    def test_corrupt_crc_is_rejected(self):
        frame = bytearray(_device_frame(protocol.CMD_PING, bytes(6)))
        frame[-1] ^= 0xFF
        with self.assertRaises(protocol.ProtocolError):
            protocol.parse_frame(bytes(frame))

    def test_bad_start_byte_is_rejected(self):
        frame = bytearray(_device_frame(protocol.CMD_PING, bytes(6)))
        frame[0] = 0x00
        with self.assertRaises(protocol.ProtocolError):
            protocol.parse_frame(bytes(frame))

    def test_length_mismatch_is_rejected(self):
        frame = _device_frame(protocol.CMD_PING, bytes(6))
        with self.assertRaises(protocol.ProtocolError):
            protocol.parse_frame(frame[:-1])

    def test_wrong_reply_kind_is_rejected(self):
        # A status payload arriving where a token was expected must not be
        # silently reinterpreted.
        frame = _device_frame(protocol.CMD_STATUS, bytes(4))
        with self.assertRaises(protocol.ProtocolError):
            protocol.parse_sample(protocol.parse_frame(frame))


class TestFixedPoint(unittest.TestCase):
    def test_q88_round_trip(self):
        for value in (0.0, 1.0, -1.0, 2.5, -3.25, 0.00390625):
            self.assertAlmostEqual(
                protocol.q88_to_float(protocol.float_to_q88(value)), value, places=6
            )

    def test_q88_clamps_instead_of_wrapping(self):
        # Wrapping would turn a very negative logit into a very positive one and
        # make the sampler pick the least likely token.
        self.assertEqual(protocol.float_to_q88(1e9), 32767)
        self.assertEqual(protocol.float_to_q88(-1e9), -32768)

    def test_nan_is_rejected(self):
        with self.assertRaises(ValueError):
            protocol.float_to_q88(float("nan"))


class TestReferenceModel(unittest.TestCase):
    def test_matches_float_softmax_closely(self):
        # Q8.8 logits plus the Q0.16 exponent table should cost well under 1e-4
        # of probability. Anything larger means the constants table is wrong.
        logits = [2.0, 1.5, 1.0, 0.5, 0.25, 0.0]
        model = protocol.reference_distribution(logits, k=len(logits))
        exact = protocol.softmax(logits)
        for got, want in zip(model, exact):
            self.assertAlmostEqual(got, want, delta=1e-4)

    def test_normalised(self):
        model = protocol.reference_distribution([3.0, 1.0, 0.0, -2.0], k=4)
        self.assertAlmostEqual(sum(model), 1.0, places=9)

    def test_far_below_max_is_exactly_unreachable(self):
        # exp(-16) underflows the Q0.16 table, so the hardware can never draw it.
        model = protocol.reference_distribution([0.0, -40.0], k=2)
        self.assertEqual(model[1], 0.0)
        self.assertEqual(model[0], 1.0)

    def test_uniform_logits_give_uniform_distribution(self):
        model = protocol.reference_distribution([1.0] * 8, k=8)
        for p in model:
            self.assertAlmostEqual(p, 1 / 8, places=9)

    def test_all_zero_weights_falls_back_to_argmax(self):
        # Mirrors the RTL's fallback_argmax path rather than dividing by zero.
        model = protocol.reference_distribution([0.0], k=1)
        self.assertEqual(model, [1.0])

    def test_hardware_probability_is_monotonic_in_deficit(self):
        previous = 1.0
        for deficit in range(0, 4096, 64):
            p = protocol.hardware_probability(deficit)
            self.assertLessEqual(p, previous + 1e-12)
            previous = p


class TestInverseCdf(unittest.TestCase):
    """Host mirror of the sampler's S_SCAN state.

    Off-by-one here is the classic categorical-sampling bug: it biases toward
    either the first or the last candidate depending on which way you slip.
    """

    def test_picks_first_prefix_greater_than_u(self):
        counts = [3, 2, 5]
        self.assertEqual(protocol.inverse_cdf_pick(counts, 0), 0)
        self.assertEqual(protocol.inverse_cdf_pick(counts, 2), 0)
        self.assertEqual(protocol.inverse_cdf_pick(counts, 3), 1)
        self.assertEqual(protocol.inverse_cdf_pick(counts, 4), 1)
        self.assertEqual(protocol.inverse_cdf_pick(counts, 5), 2)
        self.assertEqual(protocol.inverse_cdf_pick(counts, 9), 2)

    def test_zero_weight_candidates_are_never_chosen(self):
        counts = [2, 0, 3]
        chosen = {protocol.inverse_cdf_pick(counts, u) for u in range(sum(counts))}
        self.assertNotIn(1, chosen)

    def test_frequency_matches_weights(self):
        counts = [1, 4, 5]
        total = sum(counts)
        hist = [0, 0, 0]
        for u in range(total):
            hist[protocol.inverse_cdf_pick(counts, u)] += 1
        self.assertEqual(hist, counts)


if __name__ == "__main__":
    unittest.main()
