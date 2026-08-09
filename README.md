# POKE64

![POKE64 banner](Docs/Branding/poke64-banner.png)

POKE64 is an experimental, native **Commodore 64 emulator for iPad**. It uses SwiftUI, UIKit, Metal, AVFoundation, the libretro API and the VICE `x64sc` core.

POKE64 is an independent open-source project. It is not affiliated with Commodore, VICE, RetroArch, libretro or MEGA65.

## Current features

- Native iPadOS interface with a real C64 Power control, full-screen Library and Settings, and guided first-run firmware setup.
- VICE `x64sc` emulation for C64/C64C PAL and NTSC systems, with configurable VIC-II video and SID audio, including optional dual-SID addresses supported by the pinned core.
- C64 keyboard, virtual joystick, physical game controllers and Commodore 1351 mouse support from touch, trackpad or external mouse.
- Persistent Library for D64, D71, D81, G64, PRG, CRT, TAP and T64 media, including artwork, screenshots, disk inspection and automatic multi-disk sets.
- Drive 8 and optional Drive 9 with 1541/1541-II/1571/1581 models, an explicit Fast Virtual (VICE traps) or True Drive backend, optional True Drive load acceleration, plus datasette and cartridge controls; CRT cartridge auto-detection inherits VICE support including Prophet64 images.
- Commodore REU support from 128 KB to 16 MB, including persistent memory and external `.reu` images.
- User-managed Commodore and compatible firmware, one-step MEGA65 OpenROMs installation, and shared Firmware Profiles.
- Emulation Profiles for complete machine configurations, including a permanent editable `Default` profile and optional Power-on Profile behavior.
- Automatic **Previous Session** restore so the running C64 and its mounted media can survive normal app backgrounding and process termination.
- IEC virtual printer with MPS-803 rendering, paper preview and PDF/PNG/RAW output.
- Virtual Hayes modem over the C64 User Port with raw TCP/Telnet connections, BBS directory, native dialing and traffic monitoring.

Writable TAP recording, Library save states, manual multi-disk grouping, drives 10–11, additional printer models and RR-Net/Ethernet emulation remain pending.

## Firmware policy

This repository and its release archives do **not** contain original Commodore firmware, JiffyDOS, games, disk images, tapes, cartridges or other commercial content.

POKE64 accepts the following user-supplied firmware slots:

| Slot | Exact size | Purpose |
| --- | ---: | --- |
| BASIC ROM | 8,192 bytes | Required C64 BASIC firmware |
| KERNAL ROM | 8,192 bytes | Required C64 KERNAL or compatible replacement |
| Character ROM | 4,096 bytes | Required C64 character generator |
| 1541 drive ROM | 16,384 bytes | Optional True Drive firmware for the 1541 |
| 1541-II drive ROM | 16,384 bytes | Optional True Drive firmware for the 1541-II |
| 1571 drive ROM | 32,768 bytes | Optional True Drive firmware for the 1571 and D71 media |
| 1581 drive ROM | 32,768 bytes | Optional True Drive firmware for the 1581 and D81 media |
| MPS-803 printer ROM | 4,096 bytes | Optional character ROM required for graphical MPS-803 PDF/PNG output |

Drive firmware is shared **by model**, not by unit number. If Drive 8 and Drive 9 both use the same model, they must use the same ROM. Full JiffyDOS operation requires a compatible C64 KERNAL, the matching drive ROM and True Drive Emulation. The MPS-803 ROM must be imported by the user under its VICE filename `mps803-D7811G-111-U32053A.bin`; POKE64 never downloads or redistributes it. RAW printer capture remains usable without printer firmware.

POKE64 can download the generic BASIC, KERNAL and character files from a pinned revision of the MEGA65 OpenROMs project. Those files are downloaded at runtime and are not stored in this repository. OpenROMs has its own license and notices; see [Third-party notices](THIRD_PARTY_NOTICES.md).

Users and redistributors are responsible for ensuring that every imported or redistributed firmware and media file is lawfully obtained and used.

## Downloads

Prebuilt release artifacts are published on the [GitHub Releases](https://github.com/alexain/poke64-ios/releases) page.

When an **unsigned IPA** is provided, it is intended for sideloading on a physical iPhone or iPad. The IPA is not signed by Apple and cannot be installed directly from iPadOS; it must first be signed and installed with a compatible sideloading solution. Release archives do not include Commodore ROMs, commercial firmware, games or other copyrighted media.

## Development status

POKE64 is under active development and currently targets iPadOS 17 or later. iPhone and macOS adaptations are planned for a later stage.

System, Graphics, Audio, Disk Drives, Tape, Printer, Networking and Firmware / ROMs have persistent functional settings. Emulation Profiles capture the machine configuration, while Firmware Profiles keep ROM sets shared between configurations. Closing Settings restarts the core only when required.

POKE64 maintains an automatic Previous Session checkpoint for normal app backgrounding and cold-launch restoration. A deliberate C64 Power OFF ends that resumable machine state; Power ON performs a fresh boot using the current profile or the optional Power-on Profile.

Drive 8 is always available. Drive 9 can be enabled independently. **Fast Virtual** is the trap-based backend: selecting it disables True Drive and the pinned VICE/libretro core automatically enables the corresponding Drive 8/9 Virtual Device Traps. **True Drive** executes the selected drive ROMs for all enabled drives and enables hardware-level timing, compatible drive-side firmware and mechanical sound; optional Automatic or Maximum load acceleration can speed up this compatibility path. There is intentionally no separate drive-trap toggle in POKE64.

Current drive-status limitations:

- the libretro LED interface exposes one aggregate floppy-activity signal, so POKE64 cannot yet show independent Drive 8 and Drive 9 activity LEDs;
- drive firmware variants are selected per model, not separately per unit;
- drive units 10 and 11 are not exposed yet;
- D64, D71, D81 and G64 are supported; automatic multi-disk detection and swapping are available, while manual set grouping/editing remains pending.

A cartridge, disk or tape remains mounted across Soft and Hard Reset, matching physical-device behavior. Use **Reset → Eject All Media and Reset** to detach all media and return to an empty C64 session.

## Documentation

- [Build and development guide](Docs/BUILDING.md)
- [VICE revision used by v0.8.0](Docs/VICE_REVISION.md)
- [Architecture](Docs/ARCHITECTURE.md)
- [Roadmap](Docs/ROADMAP.md)
- [External-firmware testing](Docs/TESTING_EXTERNAL_FIRMWARE.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)

## Credits

Created by [Alessandro Capano](https://www.alexain.it/poke64) in 2026.

## Licensing

The POKE64 application code in this repository is licensed under the MIT License. See the [LICENSE](LICENSE) file for the full text.

The software license applies to the POKE64 source code, not to the project identity. The **POKE64** name, logo, application icon, banner and associated visual branding are reserved to the project owner unless permission is granted separately. Redistribution or modification of the source code does not by itself grant permission to present a derivative application as **POKE64**, as an official POKE64 build, or using POKE64 branding in a way that may imply such an association.

Original POKE64 visual assets, including the logo, application icon, banner and other project artwork, remain separately protected by copyright unless an individual asset explicitly states a different license.

Forks and derivative applications should therefore use their own name, icon and visual identity. References to POKE64 for attribution, compatibility information or a factual description of the project's origin are not intended to be restricted by this notice.

VICE and `vice-libretro` are separate GPL-2.0-or-later components, subject to the notices in the exact source revision used for a build. A distributor shipping a VICE-derived core must satisfy the corresponding GPL requirements, including providing the applicable license notices and complete corresponding source in an allowed form.

The libretro API header subset used by POKE64 is MIT-licensed. OpenROMs, XcodeGen and other third-party components retain their own licenses. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

POKE64 does not license or distribute proprietary Commodore firmware, including the MPS-803 printer ROM, JiffyDOS or commercial media.


### Virtual-printer licensing

The POKE64 raster-printer backend stored under `Scripts/vice-patches` is compiled into the VICE-derived core and is licensed GPL-2.0-or-later. It is not covered by the MIT License used by the application frontend.
