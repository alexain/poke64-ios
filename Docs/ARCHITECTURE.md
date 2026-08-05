# Architecture

## Objective

POKE64 is a C64-only native iOS emulator application. It does not embed RetroArch. It dynamically loads a locally built `vice_x64sc_libretro` core and implements the required libretro environment, video, audio, input, and lifecycle callbacks.

## SwiftUI application layer

`ContentView` owns the main layout, toolbar, media importer, Library and Settings presentation, C64 keyboard, and optional touch controls. `EmulatorModel` exposes session state, blocks emulation startup until the required firmware set is valid, and coordinates media loading, reset and cartridge ejection actions.

`FirmwareStore` copies user-selected ROM images into Application Support, validates exact sizes, calculates SHA-256 values for diagnostics, and generates `system/vice/vicerc` with absolute sandbox paths.

## Media library

`LibraryStore` owns the persistent media catalog and stores imported files under Application Support in `POKE64/Library/Media`. Metadata is encoded atomically as JSON and includes the title, original filename, format, size, import date, favorite state and last-opened date.

```text
Document picker
  → validate D64 / PRG / CRT / TAP / T64
  → copy to the application library using a stable UUID filename
  → update library.json atomically
  → select later from LibraryView
  → resolve the stored URL and load it through EmulatorModel
```

`LibraryView` provides All Media, Favorites and Recent filters, search, title editing and deletion. A running item is tracked by UUID and cannot be deleted until it is ejected or replaced.

## External firmware flow

```text
User document picker
  → validate exact slot size
  → copy into Application Support/System/vice/POKE64/Firmware
  → regenerate Application Support/System/vice/vicerc
  → stop existing session
  → restart core when BASIC + KERNAL + character ROMs are valid
```

The optional 1541-II slot is retained for the future Disk Drives implementation. The current development version forces Virtual Device Traps on and True Drive Emulation off because the libretro core applies drive options after reading `vicerc`; this compatibility mode prevents device 8 from becoming unavailable during D64 autostart.

## Core build flow

```text
checkout vice-libretro
  → apply Apple Clang/zlib compatibility fix
  → patch sysfile.c before compilation
  → disable libretro embedded-firmware lookup branches
  → preserve include/embedded for VIC-II palettes and generated resources
  → neutralize only generated arrays that exactly match firmware payloads
  → build x64sc iOS arm64 dylib normally
  → verify the linked dylib without modifying it
  → embed and sign dylib during Xcode build
```

The source patch fails closed when the expected upstream structure or required firmware categories cannot be recognized. The generated-resource include path remains available because `c64embedded.c` also uses palette headers from that directory. The post-build verifier scans the completed dylib for exact firmware payloads and never modifies the Mach-O file.

## Hardware input

`HardwareKeyboardCapture` is an invisible first-responder `UIView` that receives `UIPress` events. HID codes are translated to libretro keyboard values and sent as key-down and key-up events.

The virtual joystick enters libretro through frontend controller port 0. POKE64 updates the VICE `vice_joyport` core option to route that controller to C64 port 1 or port 2. Selecting the virtual joystick on one toolbar port automatically disconnects it from the other; selecting None disables the input callback and hides the overlay.

## Libretro host

`LibretroSession.mm` loads the dylib through `dlopen`, resolves `retro_*` symbols, provides system/save/assets directories, registers callbacks, and runs `retro_run()` on a dedicated thread. It also captures VICE messages and treats startup shutdown requests as explicit errors instead of leaving a silent black screen.

## Video

VICE supplies a framebuffer through the video callback. `C64MetalView` uploads it to a Metal texture and presents it while preserving the emulated aspect ratio.

## Audio

Stereo 16-bit samples from the batch callback are written to a ring buffer consumed by `AVAudioEngine`.

## Reset and cartridge lifecycle

Soft Reset and Hard Reset operate on the current emulated hardware state. An attached CRT remains inserted across both operations, as it would on physical hardware.

**Eject Cartridge and Reset** stops the current libretro session, clears the loaded cartridge reference, and starts an empty C64 session so that the machine returns to BASIC.

## Documentation split

Build prerequisites, commands, signing and repository hygiene are documented in [BUILDING.md](BUILDING.md). Planned features and development order are maintained in [ROADMAP.md](ROADMAP.md).
