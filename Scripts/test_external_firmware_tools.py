#!/usr/bin/env python3
"""Small self-contained tests for the POKE64 firmware build tools."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PREPARE = ROOT / "prepare_external_firmware_core.py"
VERIFY = ROOT / "verify_external_firmware_core.py"


def array_header(name: str, payload: bytes) -> str:
    values = ", ".join(f"0x{value:02x}" for value in payload)
    return f"static const unsigned char {name}[] = {{ {values} }};\n"


class ExternalFirmwareToolTests(unittest.TestCase):
    def source_tree(self, base: Path) -> Path:
        source = base / "source"
        (source / "vice/src").mkdir(parents=True)
        (source / "include/embedded").mkdir(parents=True)
        (source / "vice/data/C64").mkdir(parents=True)
        (source / "vice/data/DRIVES").mkdir(parents=True)

        basic = bytes([0x42]) * 8192
        kernal = bytes([0x4B]) * 8192
        chargen = bytes([0x43]) * 4096
        drive = bytes([0x44]) * 16384

        (source / "vice/data/C64/basic").write_bytes(basic)
        (source / "vice/data/C64/kernal").write_bytes(kernal)
        (source / "vice/data/C64/chargen").write_bytes(chargen)
        (source / "vice/data/DRIVES/dos1541").write_bytes(drive)

        (source / "vice/src/sysfile.c").write_text(
            '#include "vice.h"\n'
            '#ifdef __LIBRETRO__\n'
            '#include "c64-basic.h"\n'
            '#include "c64-kernal.h"\n'
            'static int embedded_lookup(void) { return c64_basic_rom[0]; }\n'
            '#endif\n'
            'int sysfile_load(void) { return embedded_check_file("kernal", 0, 0, 0); }\n'
        )
        (source / "include/embedded/c64-basic.h").write_text(
            array_header("c64_basic_rom", basic)
        )
        (source / "include/embedded/c64-kernal.h").write_text(
            array_header("c64_kernal_rom", kernal)
        )
        (source / "include/embedded/c64-chargen.h").write_text(
            array_header("c64_chargen_rom", chargen)
        )
        (source / "include/embedded/drive-1541.h").write_text(
            array_header("drive_1541_rom", drive)
        )
        (source / "include/embedded/vicii-palette.h").write_text(
            array_header("vicii_palette", bytes(range(16)))
        )
        (source / "Makefile.common").write_text(
            'INCFLAGS += \\\n'
            '\t-I$(CORE_DIR)/include \\\n'
            '\t-I$(CORE_DIR)/include/embedded \\\n'
            '\t-I$(EMU)\n'
        )
        return source

    def run_tool(self, *arguments: object, expected: int = 0) -> subprocess.CompletedProcess[str]:
        result = subprocess.run(
            [sys.executable, *(str(argument) for argument in arguments)],
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result

    def test_source_patch_preserves_palette_include_and_neutralizes_only_firmware(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = self.source_tree(root)
            palette_before = (source / "include/embedded/vicii-palette.h").read_text()
            report = root / "patch-report.json"
            self.run_tool(PREPARE, "--source", source, "--report", report)

            sysfile = (source / "vice/src/sysfile.c").read_text()
            makefile = (source / "Makefile.common").read_text()
            basic_header = (source / "include/embedded/c64-basic.h").read_text()
            palette_after = (source / "include/embedded/vicii-palette.h").read_text()

            self.assertIn("#define POKE64_EXTERNAL_FIRMWARE_ONLY 1", sysfile)
            self.assertIn("#define embedded_check_file(...) 0", sysfile)
            self.assertIn(
                "#if defined(__LIBRETRO__) && !defined(POKE64_EXTERNAL_FIRMWARE_ONLY)",
                sysfile,
            )
            self.assertIn("include/embedded", makefile)
            self.assertNotIn("0x42", basic_header)
            self.assertIn("0x00", basic_header)
            self.assertEqual(palette_after, palette_before)

            parsed = json.loads(report.read_text())
            self.assertEqual(parsed["sysfile"]["patched_guard_count"], 1)
            self.assertTrue(parsed["embedded_headers"]["embedded_include_path_preserved"])
            self.assertEqual(
                set(parsed["embedded_headers"]["detected_categories"]),
                {"basic", "kernal", "chargen", "drive"},
            )

    def test_verifier_passes_without_payload_and_does_not_modify_core(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = self.source_tree(root)
            core = root / "core.dylib"
            core.write_bytes(b"synthetic mach-o without firmware")
            before = core.read_bytes()
            report = root / "verification.json"
            self.run_tool(VERIFY, "--core", core, "--source", source, "--report", report)
            self.assertEqual(core.read_bytes(), before)
            self.assertEqual(json.loads(report.read_text())["verification"], "passed")

    def test_verifier_rejects_embedded_payload(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = self.source_tree(root)
            core = root / "core.dylib"
            core.write_bytes(b"prefix" + bytes([0x42]) * 8192 + b"suffix")
            report = root / "verification.json"
            self.run_tool(
                VERIFY,
                "--core",
                core,
                "--source",
                source,
                "--report",
                report,
                expected=1,
            )
            self.assertEqual(json.loads(report.read_text())["verification"], "failed")


if __name__ == "__main__":
    unittest.main()
