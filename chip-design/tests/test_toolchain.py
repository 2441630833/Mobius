"""Graceful-degradation tests.

Almost every user of this feature is missing something: no Docker, no board, no
Verilator. The single most important behaviour in the whole package is that a
missing tool produces a structured, honest report instead of a traceback or --
worse -- a fabricated success.

These tests run with no hardware and no venv by design.
"""

from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "mcp"))

from custom_fpga_mcp import config, flash, report, sim, synth, toolchain  # noqa: E402


class TestRun(unittest.TestCase):
    def test_missing_binary_is_distinguishable_from_a_failure(self):
        # -1 means "not installed", which needs a different fix from "ran and
        # returned non-zero". Collapsing them is how you get a wrong hint.
        code, out, err = toolchain.run(["definitely-not-a-real-binary-xyzzy"])
        self.assertEqual(code, -1)
        self.assertIn("not found", err)

    def test_timeout_has_its_own_code(self):
        code, _, err = toolchain.run(
            [sys.executable, "-c", "import time; time.sleep(5)"], timeout=0.3
        )
        self.assertEqual(code, -2)
        self.assertIn("timed out", err)

    def test_captures_output_and_exit_code(self):
        code, out, _ = toolchain.run([sys.executable, "-c", "print('hi')"])
        self.assertEqual(code, 0)
        self.assertIn("hi", out)

    def test_non_zero_exit_is_returned_not_raised(self):
        code, _, _ = toolchain.run([sys.executable, "-c", "raise SystemExit(3)"])
        self.assertEqual(code, 3)


class TestProbes(unittest.TestCase):
    """Every probe must answer, on any machine, without raising."""

    def test_all_probes_return_a_structured_result(self):
        for probe_fn in (
            toolchain.probe_vendor,
            toolchain.probe_python_env,
            toolchain.probe_verilator,
            toolchain.probe_make,
            toolchain.probe_gxx,
            toolchain.probe_yosys,
            toolchain.probe_nextpnr_xilinx,
            toolchain.probe_docker,
            toolchain.probe_openfpgaloader,
            toolchain.probe_serial,
            toolchain.probe_bitstream,
        ):
            with self.subTest(probe=probe_fn.__name__):
                result = probe_fn().to_dict()
                self.assertIn("available", result)
                self.assertIsInstance(result["available"], bool)
                self.assertIn("detail", result)
                # An unavailable tool must explain itself; a bare False is
                # useless to the agent.
                if not result["available"]:
                    self.assertTrue(result["detail"], f"{probe_fn.__name__} gave no reason")

    def test_detect_reports_capabilities_and_blockers(self):
        data = toolchain.detect().to_dict()
        for key in ("lint", "lint_and_simulate", "simulate_build", "synthesize", "synthesize_native", "flash", "sample_tokens"):
            self.assertIn(key, data["capabilities"])
            self.assertIsInstance(data["capabilities"][key], bool)
        self.assertIsInstance(data["blockers"], list)
        self.assertEqual(data["repo_root"], str(config.repo_root()))

    def test_capabilities_agree_with_the_probes_they_depend_on(self):
        rep = toolchain.detect()
        data = rep.to_dict()

        def available(name: str) -> bool:
            probe = rep.get(name)
            return bool(probe and probe.available)

        self.assertEqual(data["capabilities"]["lint"], available("verilator"))
        self.assertEqual(
            data["capabilities"]["simulate_build"],
            available("verilator") and available("make") and available("g++"),
        )
        self.assertEqual(
            data["capabilities"]["lint_and_simulate"],
            data["capabilities"]["simulate_build"],
        )
        native = available("yosys") and available("nextpnr-xilinx")
        self.assertEqual(data["capabilities"]["synthesize_native"], native)
        self.assertEqual(
            data["capabilities"]["synthesize"],
            native or available("docker"),
        )
        self.assertEqual(data["capabilities"]["flash"], available("openFPGALoader"))


class TestPathResolution(unittest.TestCase):
    def test_repo_root_is_found_from_the_package_location(self):
        # The IDE spawns the server with an arbitrary cwd, so resolution must not
        # depend on it.
        root = config.repo_root()
        self.assertTrue((root / "chip-design" / "rtl").is_dir(), root)

    def test_rtl_sources_exist_and_are_ordered_leaf_first(self):
        sources = config.rtl_sources()
        for path in sources:
            self.assertTrue(path.is_file(), f"missing RTL source: {path}")
        # The top level must come last so Verilator and Yosys see dependencies
        # before the module that uses them.
        self.assertEqual(sources[-1].name, f"{config.TOP_MODULE}.v")

    def test_constraints_file_exists(self):
        self.assertTrue((config.constraints_dir() / "arty_a7_35t.xdc").is_file())

    def test_testbench_exists(self):
        self.assertTrue((config.sim_dir() / "tb_sampler.cpp").is_file())

    def test_paths_report_is_serialisable(self):
        data = report.paths()
        self.assertEqual(data["top_module"], config.TOP_MODULE)
        self.assertEqual(data["board"], config.BOARD)
        for value in data.values():
            self.assertIsInstance(value, (str, int, list))

    def test_paths_include_mingw_when_present(self):
        data = report.paths()
        self.assertIn("mingw", data)
        bundled = config.mingw_dir()
        if bundled is None:
            self.assertEqual(data["mingw"], "")
        else:
            self.assertEqual(data["mingw"], str(bundled))


class TestMingw(unittest.TestCase):
    """Portable make/g++ kit is optional; resolution must not crash."""

    def test_mingw_dir_is_none_or_has_compilers(self):
        d = config.mingw_dir()
        self.assertTrue(d is None or (d / "bin").is_dir())

    def test_cad_suite_env_sets_cxx_when_mingw_present(self):
        if config.mingw_dir() is None:
            self.skipTest("tools/mingw not installed")
        env = config.cad_suite_env()
        self.assertIn("CXX", env)
        self.assertTrue(Path(env["CXX"]).is_file(), env["CXX"])
        self.assertIn("MAKE", env)
        self.assertTrue(Path(env["MAKE"]).is_file(), env["MAKE"])
        gxx = config.find_tool("g++")
        make = config.find_tool("make")
        self.assertTrue(gxx.available, gxx)
        self.assertTrue(make.available, make)
        mingw = str(config.mingw_dir()).replace("\\", "/").lower()
        self.assertIn("mingw", (gxx.path or "").replace("\\", "/").lower())
        self.assertIn("mingw", mingw)

    def test_make_path_uses_forward_slashes(self):
        raw = r"E:\MobiusCode\Mobius\chip-design\sim\tb_sampler.cpp"
        self.assertEqual(
            sim._make_path(raw),
            "E:/MobiusCode/Mobius/chip-design/sim/tb_sampler.cpp",
        )
        self.assertNotIn("\\", sim._make_path(config.sim_dir() / "tb_sampler.cpp"))


class TestDegradation(unittest.TestCase):
    """Operations that need absent hardware must fail as data, not exceptions."""

    def _assert_structured_failure(self, result: dict) -> None:
        self.assertIsInstance(result, dict)
        self.assertIn("ok", result)
        if not result["ok"]:
            self.assertTrue(
                result.get("error") or result.get("stage"),
                f"failure with no explanation: {result}",
            )

    def test_lint_without_verilator(self):
        self._assert_structured_failure(sim.lint())

    def test_simulate_without_verilator(self):
        if toolchain.probe_verilator().available:
            self.skipTest("verilator present; this case is the missing-tool path")
        self._assert_structured_failure(sim.simulate(samples=1))

    def test_synthesize_without_native_or_docker(self):
        self._assert_structured_failure(synth.synthesize(pull=False, timeout=5.0))

    def test_flash_without_a_loader_or_bitstream(self):
        result = flash.flash(timeout=5.0)
        self._assert_structured_failure(result)
        # Whichever is missing, the caller gets an actionable next step.
        if not result["ok"]:
            self.assertIn(result["stage"], ("tool", "bitstream", "flash"))

    def test_flash_reports_a_missing_bitstream_path_specifically(self):
        result = flash.flash(bitstream="does-not-exist.bit", timeout=5.0)
        self.assertFalse(result["ok"])
        # A nonexistent file must be named as such rather than reported as a
        # JTAG error, but a missing programmer is checked first.
        self.assertIn(result["stage"], ("tool", "bitstream"))

    def test_setup_advice_names_a_command_for_every_gap(self):
        advice = report.setup_advice()
        self.assertIn("outstanding", advice)
        for item in advice["outstanding"]:
            self.assertTrue(item["why"], item)
            self.assertTrue(item["run"], item)
        self.assertEqual(advice["ok"], not advice["outstanding"])


class TestCadSuite(unittest.TestCase):
    """Bundled YosysHQ OSS CAD Suite is optional; resolution must not crash."""

    def test_cad_suite_env_is_a_dict(self):
        env = config.cad_suite_env()
        self.assertIsInstance(env, dict)
        if config.cad_suite_dir() is not None:
            self.assertIn("PATH", env)
            self.assertIn("VERILATOR_ROOT", env)
            self.assertIn("YOSYSHQ_ROOT", env)

    def test_tool_env_puts_binary_dir_first(self):
        env = config.tool_env(sys.executable)
        self.assertIn("PATH", env)
        first = env["PATH"].split(os.pathsep)[0]
        self.assertEqual(first, str(Path(sys.executable).resolve().parent))

    def test_find_tool_uses_bundle_when_present(self):
        if config.cad_suite_dir() is None:
            self.skipTest("tools/oss-cad-suite not installed")
        tool = config.find_tool("verilator")
        self.assertTrue(tool.available, tool)
        self.assertTrue(tool.path)
        self.assertTrue(
            "oss-cad-suite" in (tool.detail or "") or "oss-cad-suite" in (tool.path or ""),
            tool,
        )


class TestOpenXc7(unittest.TestCase):
    """Bundled FPGAwars openXC7 is optional; resolution must not crash."""

    def test_openxc7_helpers_do_not_raise(self):
        d = config.openxc7_dir()
        self.assertTrue(d is None or (d / "bin").is_dir())
        chipdb = config.xc7_chipdb()
        self.assertTrue(chipdb is None or chipdb.is_file())
        db = config.prjxray_db_root()
        self.assertTrue(db is None or db.is_dir())
        cmd = config.fasm2frames_command()
        self.assertTrue(cmd is None or (isinstance(cmd, list) and cmd))

    def test_native_synth_ready_is_structured(self):
        blocker = synth.native_synth_ready()
        if blocker is None:
            yosys = config.find_tool("yosys")
            pnr = config.find_tool("nextpnr-xilinx")
            self.assertTrue(yosys.available)
            self.assertTrue(pnr.available)
            return
        self.assertFalse(blocker["ok"])
        self.assertIn("openxc7", blocker.get("hint", "").lower())

    def test_find_nextpnr_when_bundled(self):
        if config.openxc7_dir() is None:
            self.skipTest("tools/openxc7 not installed")
        tool = config.find_tool("nextpnr-xilinx")
        self.assertTrue(tool.available, tool)
        self.assertTrue(tool.path)
        self.assertTrue("openxc7" in (tool.path or "").replace("\\", "/").lower(), tool)


class TestSamplingWithoutHardware(unittest.TestCase):
    """The sampling layer needs pyserial, which is not installed system-wide.

    It must therefore be importable-or-explained, never a hard crash at import
    time -- `fpga_detect` has to keep working when pyserial is the missing piece.
    """

    def test_import_does_not_require_pyserial(self):
        from custom_fpga_mcp import uart  # noqa: F401  (import is the assertion)

    def test_transport_error_is_raised_not_import_error(self):
        from custom_fpga_mcp import uart

        try:
            import serial  # noqa: F401

            self.skipTest("pyserial is installed in this interpreter")
        except ImportError:
            pass

        with self.assertRaises(uart.TransportError) as ctx:
            uart.list_serial_ports()
        self.assertIn("pyserial", str(ctx.exception))

    def test_sampling_reports_a_blocker_instead_of_raising(self):
        from custom_fpga_mcp import sampling

        result = sampling.sample_token([1.0, 2.0, 3.0])
        self.assertFalse(result["ok"])
        self.assertTrue(result.get("hint"))

    def test_empty_logits_are_rejected_before_touching_the_port(self):
        from custom_fpga_mcp import sampling

        result = sampling.sample_token([])
        self.assertFalse(result["ok"])
        self.assertEqual(result["stage"], "input")

    def test_verify_rejects_too_few_samples_up_front(self):
        from custom_fpga_mcp import sampling

        result = sampling.verify_distribution([1.0, 2.0], samples=5)
        self.assertFalse(result["ok"])
        self.assertEqual(result["stage"], "input")

    def test_close_link_is_safe_when_nothing_is_open(self):
        from custom_fpga_mcp import sampling

        self.assertTrue(sampling.close_link()["ok"])


class TestReferenceReport(unittest.TestCase):
    def test_reference_distribution_works_with_no_hardware(self):
        data = report.reference_distribution([2.0, 1.0, 0.0])
        self.assertTrue(data["ok"])
        self.assertAlmostEqual(sum(data["hardware_model"]), 1.0, places=6)
        self.assertLess(data["max_abs_deviation"], 1e-4)

    def test_reference_distribution_rejects_empty_input(self):
        self.assertFalse(report.reference_distribution([])["ok"])

    def test_unreachable_candidates_are_listed(self):
        data = report.reference_distribution([0.0, -40.0, -50.0])
        self.assertEqual(data["unreachable_candidates"], [1, 2])


if __name__ == "__main__":
    unittest.main()
