# VICE/libretro revision used by POKE64 0.7.5

POKE64 0.7.5 builds its `vice_x64sc` libretro core from the following
upstream `vice-libretro` revision:

```text
c8c242db75a559246d6d51017e6dd4ecd75d6a9f
```

`Scripts/build_vice_core.sh` checks out this exact revision before
applying the local POKE64 patches, including:

- external-firmware-only enforcement;
- restoration of the VICE MPS-803 printer driver;
- the sandbox-safe POKE64 raster-printer backend;
- iOS compatibility changes;
- retention and verification of the exported printer bridge symbols;
- iOS VICE RS-232-over-TCP support without enabling VICE netplay;
- the POKE64 Virtual Hayes modem with raw TCP/Telnet handling, modem state/telemetry, native dialing and diagnostic traffic exports.

The build does not contain proprietary Commodore firmware. Commodore
system ROMs, drive ROMs and the MPS-803 printer ROM must be supplied
separately by the user.

The VICE-derived core and the raster-printer backend compiled into it
are GPL-2.0-or-later components. The Swift and Objective-C application
layer remains covered by the repository MIT License.
