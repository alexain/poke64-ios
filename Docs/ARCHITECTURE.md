# Architecture

## Objective

POKE64 is a C64-only iOS frontend. It does not embed RetroArch. It dynamically loads a locally built `vice_x64sc_libretro` core and implements the required libretro environment, video, audio, input, and lifecycle callbacks.

## SwiftUI application layer

`ContentView` owns the main layout, toolbar, file importer, firmware settings sheet, C64 keyboard, and optional touch controls. `EmulatorModel` exposes session state and blocks startup until the required firmware set is valid.

`FirmwareStore` copies user-selected ROM images into Application Support, validates exact sizes, calculates SHA-256 values for diagnostics, and generates `system/vice/vicerc` with absolute sandbox paths.

## External firmware flow

```text
User document picker
  → validate exact slot size
  → copy into Application Support/System/vice/POKE64/Firmware
  → regenerate Application Support/System/vice/vicerc
  → stop existing session
  → restart core when BASIC + KERNAL + character ROMs are valid
```

The optional 1541-II slot controls whether True Drive Emulation is enabled in the generated configuration.

## Core build flow

```text
checkout vice-libretro
  → apply Apple Clang/zlib compatibility fix
  → build x64sc iOS arm64 dylib
  → scan exact firmware payloads from vice/data/C64 and vice/data/DRIVES
  → zero matching payloads in the unsigned dylib
  → verify expected categories and absence of exact payloads
  → embed and sign dylib during Xcode build
```

The post-link scrubber preserves the Mach-O file length. It refuses to complete when upstream changes prevent the expected payloads from being identified.

## Hardware input

`HardwareKeyboardCapture` is an invisible first-responder `UIView` that receives `UIPress` events. HID codes are translated to libretro keyboard values and sent as key-down and key-up events.

## Libretro host

`LibretroSession.mm` loads the dylib through `dlopen`, resolves `retro_*` symbols, provides system/save/assets directories, registers callbacks, and runs `retro_run()` on a dedicated thread.

## Video

VICE supplies a framebuffer through the video callback. `C64MetalView` uploads it to a Metal texture and presents it while preserving the emulated aspect ratio.

## Audio

Stereo 16-bit samples from the batch callback are written to a ring buffer consumed by `AVAudioEngine`.
