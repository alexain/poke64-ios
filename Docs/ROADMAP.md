# POKE64 roadmap

POKE64 is designed for **iPadOS first**, with landscape iPad use as the primary interface target. iPhone and macOS adaptations will be considered after the core iPad experience is stable.

This document lists only work that is still pending.

## 1. Core and firmware

- Pin the exact VICE/libretro revision used by release builds.
- Make the external-firmware-only core build fully reproducible.
- Improve startup, firmware and media-loading diagnostics.
- Add firmware profiles for standard ROMs, JiffyDOS, custom ROMs and redistributable open firmware.
- Offer an optional open-firmware fallback for users without compatible ROM images.
- Add drive firmware slots, known-ROM identification and compatible drive-model selection.

## 2. Settings panels

Complete the existing settings sections with persistent options and live application where supported:

- System and machine profiles.
- Graphics and VIC-II options.
- Audio, SID model and filter options.
- Tape and datasette options.
- Disk drive configuration.
- Printer configuration.
- Firmware profile management.
- Networking and modem options.

## 3. Library

Expand the initial persistent D64, PRG, CRT, TAP and T64 library:

- Add D71, D81, G64 and other formats after their drive requirements are handled reliably.
- Add file replacement and duplicate detection.
- Add screenshots, notes and optional cover artwork.
- Display disk directories, free blocks and contained files.
- Preview BASIC listings where practical.
- Associate hardware profiles, joyports, firmware, save states and multidisk sets with library entries.

## 4. Keyboard and input

- Dock the complete C64 keyboard at the bottom instead of presenting it as a sheet.
- Add adaptive iPad layouts and reliable held modifiers.
- Display Shift and Commodore graphical legends dynamically.
- Improve Apple Magic Keyboard and other hardware-keyboard mappings.
- Add paddle support.
- Validate Commodore 1351 mouse behavior with representative software and tune pointer sensitivity.
- Investigate Apple Pencil as a Commodore mouse, light pen or graphics pointer.

## 5. Media and expansion devices

- Add dedicated Drives, Tape and Cartridge/REU controls.
- Support drive units 8–11 and selectable drive models.
- Add disk control, mount/eject operations and multidisk sets.
- Add side-mounted drive activity LEDs beside the 4:3 display.
- Add synchronized 1541 mechanical sounds when true drive emulation is available.
- Add complete datasette transport controls and status.
- Add cartridge management beyond initial loading and ejection.
- Add REU configuration and supported expansion options.

## 6. Graphics and audio

- Add Metal CRT shaders and presets based on compatible openly licensed shader projects.
- Add scanlines, shadow mask, curvature, bloom, vignette and phosphor-persistence controls.
- Add VIC-II palette, crop, aspect-ratio and scaling options.
- Add SID model, emulation engine, filters, stereo and dual-SID settings.

## 7. Printer

- Emulate MPS-801, MPS-802 and MPS-803 output through VICE.
- Produce realistic dot-matrix multipage PDFs.
- Add continuous paper, ribbon intensity, queue, preview, export and sound options.
- Investigate Okimate 20 protocol and color-print support.

## 8. Networking and BBS

- Add Hayes modem emulation through RS-232/User Port.
- Support Telnet and raw TCP connections.
- Add a BBS directory, baud-rate selection, connection state and activity indicators.

## 9. Hardware Link

Investigate integration with Ultimate 64 Elite-II and compatible current Commodore hardware exposing network APIs.

- Discover supported hardware on the LAN.
- Transfer PRG, D64, CRT and library items.
- Mount or eject media and remotely control reset or execution.
- Exchange memory and program data.
- Investigate audio/video streaming where supported by the hardware API.

## 10. Distribution and release engineering

- Automate release builds and archive validation.
- Document the exact source revision and patches corresponding to every distributed core binary.
- Publish the required VICE/libretro source and license material for distributed builds.
- Verify that release packages contain no proprietary Commodore firmware or commercial media.
- Prepare App Store metadata, privacy declarations and review documentation.

## 11. Long-term and experimental work

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
Commodore mouse validation
→ bottom C64 keyboard
→ library metadata and media inspection
→ drive, tape, cartridge and REU management
→ complete settings panels
→ CRT graphics and advanced audio
→ printer and networking
→ release engineering and App Store preparation
→ hardware link and experimental features
```
