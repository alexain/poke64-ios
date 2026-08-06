#!/usr/bin/env python3
"""Patch a fetched vice-libretro tree for POKE64 graphical printer output."""

from __future__ import annotations

import argparse
import shutil
from pathlib import Path


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match in {path}, found {count}")
    path.write_text(text.replace(old, new, 1))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--replacement", required=True, type=Path)
    args = parser.parse_args()

    source = args.source.resolve()
    replacement = args.replacement.resolve()
    if not (source / ".git").is_dir():
        raise SystemExit(f"Not a vice-libretro checkout: {source}")
    if not replacement.is_file():
        raise SystemExit(f"Missing POKE64 output backend: {replacement}")

    # The upstream release build passes `-s` to Apple clang. On Darwin this
    # removes the symbol table entries needed by dlsym(), including POKE64's
    # private frontend bridge API. Strip local symbols only, preserving all
    # global dynamic symbols exported by the dylib. The explicit `-u` roots
    # below also prevent Apple ld from dead-stripping the three entry points
    # that are reached only through dlsym() by the iOS frontend.
    root_makefile = source / "Makefile"
    replace_once(
        root_makefile,
        "   LDFLAGS     += -s\n",
        "   LDFLAGS     += -Wl,-x\n"
        "   LDFLAGS     += -Wl,-u,_poke64_printer_set_output_directory\n"
        "   LDFLAGS     += -Wl,-u,_poke64_printer_snapshot\n"
        "   LDFLAGS     += -Wl,-u,_poke64_printer_configure_raw_capture\n",
        "Darwin runtime symbol preservation",
    )

    makefile = source / "Makefile.x64sc"
    replace_once(
        makefile,
        "    $(RETRODEP)/printerdrv/drv-mps803.c \\\n",
        "    $(EMU)/printerdrv/drv-mps803.c \\\n",
        "MPS-803 source selection",
    )

    shutil.copyfile(
        replacement,
        source / "vice/src/printerdrv/output-graphics.c",
    )

    driver_select = source / "vice/src/printerdrv/driver-select.c"
    replace_once(
        driver_select,
        '#include "util.h"\n',
        '#include "util.h"\n\n'
        'extern void poke64_printer_capture_byte(unsigned int prnr, uint8_t value);\n'
        'extern void poke64_printer_capture_formfeed(unsigned int prnr);\n',
        "raw capture declarations",
    )
    replace_once(
        driver_select,
        "int driver_select_putc(unsigned int prnr, unsigned int secondary, uint8_t b)\n"
        "{\n"
        "    return driver[prnr].drv_putc(prnr, secondary, b);\n"
        "}\n",
        "int driver_select_putc(unsigned int prnr, unsigned int secondary, uint8_t b)\n"
        "{\n"
        "    poke64_printer_capture_byte(prnr, b);\n"
        "    return driver[prnr].drv_putc(prnr, secondary, b);\n"
        "}\n",
        "raw capture byte hook",
    )
    replace_once(
        driver_select,
        "int driver_select_formfeed(unsigned int prnr)\n"
        "{\n",
        "int driver_select_formfeed(unsigned int prnr)\n"
        "{\n"
        "    poke64_printer_capture_formfeed(prnr);\n",
        "raw capture form-feed hook",
    )

    mps = source / "vice/src/printerdrv/drv-mps803.c"
    replace_once(
        mps,
        '    if (palette_load("mps803.vpl", "PRINTER", palette) < 0) {\n'
        '#ifndef __LIBRETRO__\n'
        '        log_error(drv803_log, "Cannot load palette file `%s\'.",\n'
        '                  "mps803.vpl");\n'
        '#endif\n'
        '        return -1;\n'
        '    }\n',
        '    if (palette_load("mps803.vpl", "PRINTER", palette) < 0) {\n'
        '#ifndef __LIBRETRO__\n'
        '        log_error(drv803_log, "Cannot load palette file `%s\'.",\n'
        '                  "mps803.vpl");\n'
        '        return -1;\n'
        '#endif\n'
        '    }\n',
        "libretro palette fallback",
    )

    print("Applied POKE64 MPS-803 and raster-output source patches.")


if __name__ == "__main__":
    main()
