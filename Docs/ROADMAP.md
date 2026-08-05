# POKE64 roadmap

## 1. Core and firmware

- Validate the source-level external-firmware-only build on a pinned VICE revision.
- Improve startup and firmware diagnostics.
- Add standard, JiffyDOS, custom and open-firmware profiles.
- Disable True Drive Emulation when no compatible drive ROM is available.
- Add drive firmware slots and known-ROM identification.

## 2. Settings architecture

Create a settings modal with separate panels for:

- System
- Graphics
- Audio
- Tape
- Disk Drives
- Printer
- Firmware / ROMs
- Networking
- About

Panels may initially be placeholders and will be completed incrementally.

## 3. Toolbar and expansion devices

- Remove Start and Stop.
- Add Soft/Hard Reset.
- Add independent Joyport 1 and Joyport 2 assignment menus.
- Support None, one Virtual Joystick, physical controllers and Commodore mouse.
- Add Cartridge/REU, Drives and Tape panels.

## 4. Keyboard and input

- Dock the complete C64 keyboard at the bottom.
- Support adaptive layouts and held modifiers.
- Display Shift and Commodore graphical legends dynamically.
- Add `GCController`, paddles and mouse support.

## 5. Drives and tape

- Support units 8–11, disk control and multidisk media.
- Add side-mounted drive activity LEDs beside the 4:3 display.
- Add synchronized 1541 mechanical sounds.
- Add complete datasette transport controls and status.

## 6. Graphics and audio

- Add Metal CRT shaders and presets.
- Add VIC-II palette, crop and scaling options.
- Add SID model, emulation engine, filters and dual-SID settings.

## 7. Printer

- Emulate MPS-801/802/803 output through VICE.
- Produce realistic dot-matrix multipage PDFs.
- Add continuous paper, ribbon, queue, preview, export and sound options.
- Investigate Okimate 20 support later.

## 8. Networking and BBS

- Add Hayes modem emulation through RS-232/User Port.
- Support Telnet and raw TCP.
- Add BBS directory, baud rate, connection state and activity indicators.

## Development order

```text
external-firmware core
→ settings architecture
→ toolbar and joyports
→ bottom keyboard
→ drive/tape/cartridge management
→ CRT and audio controls
→ printer and networking
```
