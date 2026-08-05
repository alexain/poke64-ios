# POKE64 roadmap

POKE64 is currently designed for **iPadOS first**, with landscape iPad use as the primary interface target. iPhone and macOS adaptations are planned only after the core iPad experience is stable.

## 1. Core and firmware

- Validate the source-level external-firmware-only build on a pinned VICE revision.
- Improve startup and firmware diagnostics.
- Add standard, JiffyDOS, custom and open-firmware profiles.
- Offer an installable open-firmware fallback when the user does not own compatible ROM images.
- Disable True Drive Emulation when no compatible drive ROM is available.
- Add drive firmware slots and known-ROM identification.

## 2. Settings architecture

Provide an iPad settings modal with separate panels for:

- System
- Graphics
- Audio
- Tape
- Disk Drives
- Printer
- Firmware / ROMs
- Networking
- About

The navigation shell and placeholder panels are introduced in v0.3.0 and will be completed incrementally.

## 3. Toolbar and expansion devices

- Remove Start and Stop from the toolbar.
- Add Soft and Hard Reset.
- Add independent Joyport 1 and Joyport 2 assignment menus.
- Support None, one Virtual Joystick, physical controllers and Commodore mouse.
- Add Cartridge/REU, Drives, Tape, Library and Settings controls.

## 4. Library

Create a persistent content library for D64, D71, D81, G64, TAP, T64, PRG, CRT and supported related formats.

- Import once and select media later from Drive, Tape or Cartridge panels.
- Store title, format, size, import date, favorites and recent usage.
- Add user screenshots, custom notes and optional cover artwork.
- Display disk directories, free blocks and contained files.
- Preview BASIC listings where practical.
- Later associate hardware profiles, joyports, firmware, save states and multidisk sets with each entry.

## 5. Keyboard and input

- Dock the complete C64 keyboard at the bottom instead of presenting a sheet.
- Support adaptive iPad layouts and held modifiers.
- Display Shift and Commodore graphical legends dynamically.
- Improve Apple Magic Keyboard and other hardware-keyboard mapping.
- Add `GCController`, paddles and Commodore mouse support.
- Investigate Apple Pencil as a Commodore mouse, light pen or graphics pointer.

## 6. Drives and tape

- Support units 8–11, disk control and multidisk media.
- Add side-mounted drive activity LEDs beside the 4:3 display.
- Add synchronized 1541 mechanical sounds.
- Add complete datasette transport controls and status.

## 7. Graphics and audio

- Add Metal CRT shaders and presets inspired by compatible open RetroArch shader projects.
- Add scanlines, mask, curvature, bloom, vignette and phosphor persistence controls.
- Add VIC-II palette, crop and scaling options.
- Add SID model, emulation engine, filters and dual-SID settings.

## 8. Printer

- Emulate MPS-801, MPS-802 and MPS-803 output through VICE.
- Produce realistic dot-matrix multipage PDFs.
- Add continuous paper, ribbon, queue, preview, export and sound options.
- Investigate Okimate 20 protocol and color-print support later.

## 9. Networking and BBS

- Add Hayes modem emulation through RS-232/User Port.
- Support Telnet and raw TCP.
- Add a BBS directory, baud rate, connection state and activity indicators.

## 10. Hardware Link

Investigate integration with Ultimate 64 Elite-II and compatible current Commodore hardware exposing network APIs.

- Discover supported hardware on the LAN.
- Transfer PRG, D64, CRT and library items.
- Mount/eject media and remotely control reset or execution.
- Exchange memory and program data.
- Investigate audio/video streaming when supported by the hardware API.

## 11. Long-term and experimental work

### SuperCPU

- Investigate technical and licensing feasibility for CMD SuperCPU emulation.
- Evaluate 65C816, accelerated timing, SuperRAM and software compatibility requirements.

### Integrated development environment

- Add BASIC and 6502 assembler editors.
- Build or assemble locally or through an optional web-based editor component.
- Launch generated programs directly in the emulator.
- Add registers, accumulator, flags, program counter, stack, disassembly and memory inspection.
- Add breakpoints, single-step execution and memory watches through a VICE monitor/debug extension.

### Additional platforms

- Adapt the interface for iPhone after the iPad workflow is stable.
- Evaluate native macOS, Mac Catalyst or shared SwiftUI targets later.

## Development order

```text
external-firmware core
→ settings architecture
→ toolbar and joyports
→ Library MVP
→ bottom keyboard
→ drive/tape/cartridge management
→ controllers, mouse and multidisk
→ CRT and advanced audio
→ printer and networking
→ hardware link and experimental features
```
