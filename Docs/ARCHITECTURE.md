# Architecture

## Objective

POKE64 is a C64-only native iPadOS emulator application. It does not embed RetroArch. It dynamically loads a locally built `vice_x64sc_libretro` core and implements the required libretro environment, video, audio, input, disk-control, LED and lifecycle callbacks.

## SwiftUI application layer

`ContentView` owns the main layout, centered toolbar, document importer, full-screen Library and Settings presentation, docked C64 keyboard, optional touch controls, Devices popover and shared media-action dialogs.

`EmulatorModel` exposes session state, blocks emulation startup until the required system firmware is valid, coordinates core restarts after configuration changes and tracks mounted media independently for Drive 8, Drive 9, datasette and cartridge.

`FirmwareStore` copies selected ROM images into Application Support, validates exact sizes, calculates SHA-256 values for diagnostics, manages the optional OpenROMs profile and generates `system/vice/vicerc` with absolute sandbox paths.

## Settings and configuration

Persistent settings are stored through `UserDefaults` and grouped into configuration fingerprints. Closing Settings restarts the VICE core only when a machine, video, audio, drive or firmware value has changed.

Implemented panels:

- System: C64/C64C and PAL/NTSC machine profiles;
- Graphics: aspect ratio, crop, palette, PAL filter and color controls;
- Audio: SID engine/model, ReSID sampling, output sample rate, VIC-II leak and datasette sound;
- Disk Drives: Drive 8, optional Drive 9, models, shared backend, write protection and mechanical sound;
- Firmware / ROMs: system and drive slots plus pinned OpenROMs installation.

Tape, Printer and Networking currently retain their navigation and placeholder structure.

## Media library

`LibraryStore` owns the persistent media catalog and stores imported files under Application Support in `POKE64/Library/Media`. Metadata is encoded atomically as JSON and includes title, original filename, format, size, import date, favorite state and last-opened date.

```text
Document picker
  → validate D64 / D71 / D81 / PRG / CRT / TAP / T64
  → copy to the application library using a stable UUID filename
  → update library.json atomically
  → select later from LibraryView
  → resolve the stored URL and execute a media-specific action
```

`LibraryView` provides All Media, Favorites and Recent filters, search, title editing and deletion. A mounted or running item is tracked by UUID and cannot be deleted until it is ejected or replaced.

The Library and Devices flows can also create D64, D71 or D81 images. A new image can be a formatted Commodore DOS disk with BAM and directory structures or a completely zero-filled image intended for later formatting by the emulated machine.

## Media and device workflow

Open and Library both produce a `MediaActionRequest`. Disk images can be inserted or autostarted in a compatible enabled drive; tapes can be inserted or autostarted in the datasette; cartridges can be attached with reset; PRG files run directly.

Runtime media changes are queued onto the core thread and use VICE-native attach, detach and autostart entry points. Replacement confirmation is shared between Open, Library and Devices.

Drive compatibility is checked before attachment:

- D64: 1541, 1541-II or 1571;
- D71: 1571;
- D81: 1581.

## External firmware flow

```text
User document picker or pinned OpenROMs download
  → validate exact slot size
  → preserve a restorable complete system-ROM profile when appropriate
  → copy into Application Support/System/vice/POKE64/Firmware
  → regenerate Application Support/System/vice/vicerc
  → restart the core only after the configuration fingerprint changes
```

Required system slots are BASIC (8 KiB), KERNAL (8 KiB) and character ROM (4 KiB). Optional drive slots are 1541 and 1541-II (16 KiB each), plus 1571 and 1581 (32 KiB each).

Drive ROMs are shared by model. Two enabled units using the same model therefore use the same firmware. Matching C64 KERNAL and drive-ROM replacements can be used for JiffyDOS-style configurations.

The OpenROMs profile downloads a pinned generic BASIC, KERNAL and character set from the upstream MEGA65 repository. It does not provide drive firmware.

## Drive emulation

Drive 8 is always enabled. Drive 9 is optional and has an independent model and mounted image.

The emulation backend is global:

- Fast Virtual Drive enables VICE virtual-device traps for every enabled drive;
- True Drive Emulation loads the selected drive ROMs, activates the configured hardware models and disables the corresponding traps.

Drive model and ROM resources are established during core initialization. Runtime insertion ensures the selected ROM and drive type are active before attaching the image.

Mechanical drive sound is applied through VICE resources for compatible 1541-family and 1571 models. The libretro LED callback provides power and one aggregate floppy-activity state; it does not identify which drive generated the activity.

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

The docked C64 keyboard has Compact and Full layouts. Shift and Commodore operate as momentary touch modifiers, while Shift Lock persists until released.

The virtual joystick enters libretro through frontend controller port 0. POKE64 updates the VICE `vice_joyport` core option to route that controller to C64 port 1 or port 2. Selecting it on one toolbar port disconnects it from the other.

Physical controllers are discovered through Game Controller. Commodore 1351 input can come from the iPad touchscreen, external mouse or trackpad.

## Libretro host

`LibretroSession.mm` loads the dylib through `dlopen`, resolves `retro_*` symbols and selected VICE runtime symbols, provides system/save/assets directories, registers callbacks and runs `retro_run()` on a dedicated thread. It captures VICE messages and treats startup shutdown requests as explicit errors instead of leaving a silent black screen.

## Core abstraction and long-term VICE direction

The current supported runtime remains the VICE `x64sc` libretro core. New frontend features should, where practical, depend on POKE64-owned abstractions rather than calling libretro-specific APIs directly. Video presentation, audio output, input routing, media actions, device state and lifecycle control should remain separable from the concrete core host.

A possible long-term architecture is to introduce an `EmulatorSession`-style boundary with the existing `LibretroSession` as one implementation and an experimental `ViceSession` as another. `ViceSession` would embed and drive VICE directly through a POKE64 platform/bridge layer, removing the libretro translation layer while retaining VICE as the emulation engine.

The migration, if pursued, should be staged:

```text
POKE64 UI / Library / Devices
  → POKE64 session and device abstractions
      → LibretroSession (current production backend)
      → ViceSession     (future experimental backend)
```

Before any backend switch, the direct-VICE implementation must match or exceed the current build in compatibility, timing, audio/video behavior, media handling, save-state reliability and performance. Libretro should only be removed after a direct backend is proven on real iPad hardware and the migration has a clear maintenance benefit.

A ground-up POKE64 C64 emulation core is not a planned replacement path. Reimplementing the 6510, VIC-II, SID, CIAs, IEC bus, drive hardware, GCR behavior and cycle-level compatibility would be a separate emulator project with substantially greater scope than embedding VICE directly.

Direct VICE integration would not remove VICE licensing obligations. Any future distribution model must continue to satisfy the applicable GPL requirements for the VICE-derived component and document the boundary between that component and POKE64-owned application code.

## Video

VICE supplies a framebuffer through the video callback. `C64MetalView` uploads it to a Metal texture and presents it using the aspect ratio reported by the core and the selected crop and geometry options.

## Audio

Stereo 16-bit samples from the batch callback are written to a ring buffer consumed by `AVAudioEngine`. SID, sample-rate and peripheral-audio options are applied through libretro core variables and VICE runtime resources where required.

## Reset and media lifecycle

Soft Reset and Hard Reset operate on the current emulated hardware state and keep mounted disks, tapes and cartridges attached.

**Eject All Media and Reset** detaches Drive 8, Drive 9, datasette and cartridge media, clears temporary media and starts an empty C64 session.

## Documentation split

Build prerequisites, commands, signing and repository hygiene are documented in [BUILDING.md](BUILDING.md). Planned work is maintained in [ROADMAP.md](ROADMAP.md).
