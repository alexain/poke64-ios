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

## Libretro host

`LibretroSession.mm` loads the dylib through `dlopen`, resolves `retro_*` symbols, provides system/save/assets directories, registers callbacks, and runs `retro_run()` on a dedicated thread. It also captures VICE messages and treats startup shutdown requests as explicit errors instead of leaving a silent black screen.

## Video

VICE supplies a framebuffer through the video callback. `C64MetalView` uploads it to a Metal texture and presents it while preserving the emulated aspect ratio.

## Audio

Stereo 16-bit samples from the batch callback are written to a ring buffer consumed by `AVAudioEngine`.
