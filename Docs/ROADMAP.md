# POKE64 roadmap

POKE64 is designed for **iPadOS first**, with landscape iPad use as the primary interface target. iPhone and macOS adaptations will be considered after the core iPad experience is stable.

This document lists only work that is still pending. Completed Library foundations, G64 support, duplicate handling, disk inspection, Library artwork/screenshots, multi-disk detection, keyboard, Devices, video, audio, Drive 8/9, REU, datasette transport and the first MPS-803 virtual-printer implementation have been removed.

## 1. Core, firmware and diagnostics

- Automate verification and release-note recording of the exact pinned VICE/libretro revision used by every release build.
- Make the external-firmware-only core build fully reproducible from a recorded revision and patch set.
- Improve startup, firmware, drive-ROM and media-operation diagnostics.
- Add known-ROM identification and clearly label standard, JiffyDOS and other recognized replacements.
- Add explicit per-model firmware profiles while preserving the VICE limitation that a model's ROM is shared by every unit using it.
- Verify pinned OpenROMs downloads with recorded hashes and surface upstream revision/license information in release material.

## 2. Remaining settings panels

- Add firmware profile selection, profile naming and known-ROM status.
- Implement Networking and modem settings.
- Add advanced options only where they can be applied safely without destabilizing the current core lifecycle.

## 3. Library and media management

- Add other disk formats after their drive and write-back requirements are handled reliably.
- Add an optional cover/grid view while retaining the detailed list.
- Preview BASIC listings where practical.
- Add manual multi-disk grouping and editing for sets that cannot be inferred reliably from filenames.
- Associate hardware profiles, joyports, firmware and save states with library entries.
- Add explicit export/share workflows for created or modified disk images.
- Add optional iCloud Drive and Google Drive backup/synchronization for the library, imported media and user-supplied firmware/ROM files, supporting recovery after app reinstallation and synchronization across multiple devices.

## 4. Keyboard and input

- Improve Apple Magic Keyboard and other hardware-keyboard mappings.
- Add paddle support.
- Test additional Commodore 1351 software and refine pointer sensitivity where needed.
- Investigate Apple Pencil as a Commodore mouse, light pen or graphics pointer.

## 5. Media and expansion devices

- Add optional drive units 10 and 11.
- Expose independent per-drive activity indicators by connecting to a VICE API that identifies the active unit; the current libretro LED is aggregate.
- Add safe writable TAP recording, explicit write-back and export before exposing the datasette RECORD control.
- Extend cartridge handling for supported expansion devices beyond basic CRT attachment.

## 6. Graphics and audio

- Add Metal CRT shaders and presets based on compatible openly licensed shader projects.
- Add scanlines, shadow mask, curvature, bloom, vignette and phosphor-persistence controls.
- Add reusable performance/quality presets for iPad hardware classes.
- Add SID filter controls, stereo output and supported dual-SID configurations.
- Add external-display mode for connected monitors/TVs: move the C64 video output to the external screen at full screen while keeping the iPad as the control surface for the keyboard, datasette, Devices and other emulator controls.
- Add an explicit move/return display action, preserve the running emulation while switching screens, and handle external-display connection/disconnection gracefully.

## 7. Printer

- Broaden virtual-printer compatibility testing beyond the validated BASIC text, direct bit-image and PrintMaster MPS-801 workflows, including PETSCII-heavy productivity software.
- Add MPS-801, MPS-802 and other VICE printer models after their firmware requirements are defined.
- Add a persistent print-job browser and optional continuous-paper presentation.
- Add printer mechanism sound and finer ribbon-wear simulation.
- Investigate Okimate 20 protocol and color-print support.

## 8. Networking and BBS

- Add Hayes modem emulation through RS-232/User Port.
- Support Telnet and raw TCP connections.
- Add a BBS directory, baud-rate selection, connection state and activity indicators.

## 9. Hardware Link

Investigate integration with Ultimate 64 Elite-II and compatible current Commodore hardware exposing network APIs.

- Discover supported hardware on the LAN.
- Transfer PRG, D64, D71, D81, CRT and library items where the target supports them.
- Mount or eject media and remotely control reset or execution.
- Exchange memory and program data.
- Investigate audio/video streaming where supported by the hardware API.

## 10. Distribution and release engineering

- Automate release builds and archive validation.
- Document the exact source revision and patches corresponding to every distributed core binary.
- Publish the complete corresponding VICE/libretro source and required license material for distributed builds.
- Verify that release packages contain no proprietary Commodore firmware, JiffyDOS or commercial media.
- Record third-party notices and OpenROMs revision/hash information in every release.
- Prepare App Store metadata, privacy declarations and review documentation.

## 11. Long-term and experimental work

### Core abstraction and direct VICE integration

- Keep libretro as the production backend while reducing direct dependencies on `LibretroSession` in new frontend features.
- Define POKE64-owned session interfaces for lifecycle, video, audio, input, media operations and device state so the frontend is not tied permanently to one core host.
- Investigate an experimental `ViceSession` backend that embeds VICE directly through a POKE64 platform/bridge layer, without the libretro translation layer.
- Allow `LibretroSession` and `ViceSession` to coexist during migration and compare compatibility, timing, performance, save states and peripheral behavior on real iPad hardware.
- Consider removing libretro only after the direct VICE backend has reached feature and compatibility parity and offers a clear maintenance or capability advantage.
- Treat a ground-up POKE64 C64 core as a separate research project rather than a planned migration target.
- Preserve and document all GPL/source-distribution obligations associated with VICE regardless of whether libretro remains in the stack.

### SuperCPU

- Investigate technical and licensing feasibility for CMD SuperCPU emulation.
- Evaluate 65C816 execution, accelerated timing, SuperRAM and software compatibility requirements.

### Integrated development environment

- Add BASIC and 6502 assembler editors.
- Build or assemble locally or through an optional web-based editor component.
- Launch generated programs directly in the emulator.
- Add registers, accumulator, flags, program counter, stack, disassembly and memory inspection.
- Add breakpoints, single-step execution and memory watches through a VICE monitor/debug extension.

### Additional platforms

- Adapt the interface for iPhone after the iPad workflow is stable.
- Evaluate native macOS, Mac Catalyst or shared SwiftUI targets.

## Development order

```text
Networking and Virtual Modem foundation
→ global profiles, firmware profiles and per-title overrides
→ advanced CRT graphics, SID options and external-display support
→ save states, manual multi-disk management and additional drives
→ printer validation and broader compatibility testing
→ release engineering and App Store preparation
→ hardware link and experimental features
```
