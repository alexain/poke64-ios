# Building POKE64

This document describes how to build the current iPadOS development version from a clean clone.

## Requirements

- macOS with a recent Xcode and iPadOS SDK
- Xcode command-line tools
- Git, Make and Python 3
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- a physical arm64 iPad
- an Apple Development Team configured in Xcode

The current deployment target is iPadOS 17.0 or later. The interface can be developed in the simulator, but the device-only VICE dylib cannot run there.

## Clone and prepare

```bash
git clone https://github.com/<your-account>/poke64-ios.git
cd poke64-ios
brew install xcodegen
```

## Build the VICE core

```bash
./Scripts/build_vice_core.sh
```

The script fetches the selected `vice-libretro` revision, applies the external-firmware source patch and iOS compatibility changes, builds `x64sc` for iOS arm64, and verifies the resulting dylib without modifying the Mach-O binary.

Local outputs:

```text
Vendor/Core/vice_x64sc_libretro_ios.dylib
Vendor/Core/external-firmware-source-patch-report.json
Vendor/Core/external-firmware-verification-report.json
```

These files are excluded from Git.

For a reproducible build, select a verified commit:

```bash
VICE_REF=<verified-commit> ./Scripts/build_vice_core.sh
```

## Generate the Xcode project

```bash
./Scripts/bootstrap.sh
```

This generates `POKE64.xcodeproj` from `project.yml`.

## Build on iPad

```bash
open POKE64.xcodeproj
```

In Xcode:

1. select the `POKE64` target;
2. open **Signing & Capabilities**;
3. select your Apple Development Team;
4. verify the bundle identifier `it.alexain.poke64`, or use a unique identifier for your own build;
5. select a physical iPad;
6. build and run.

`Scripts/embed_core.sh` copies the local dylib into the app bundle and signs it with the application identity during the Xcode build.

## First launch

POKE64 opens Firmware / ROMs when the required system firmware is missing. Import BASIC, KERNAL and character ROM images; the 1541-II slot is optional.

Imported firmware is stored under:

```text
Application Support/System/vice/POKE64/Firmware/
```

The generated VICE configuration is:

```text
Application Support/System/vice/vicerc
```

The `x64sc` resources are written under `[C64SC]`.

## Current drive compatibility mode

The development build currently forces:

```text
Virtual Device Traps: enabled
True Drive Emulation: disabled
Drive sound: disabled
```

This avoids libretro core defaults overriding the generated `vicerc` and leaving device 8 unavailable during D64 autostart. Imported 1541-II firmware is retained for the future Disk Drives implementation.

## Repository checks

Before committing:

```bash
./Scripts/check_integrated_sources.sh
git status --short
```

Do not commit:

```text
Vendor/Core/*.dylib
Vendor/Core/external-firmware-source-patch-report.json
Vendor/Core/external-firmware-verification-report.json
Vendor/vice-libretro-src/
DerivedData/
xcuserdata/
*.xcuserstate
```

Do not add firmware images, games, media images, provisioning profiles or signing certificates.

## Basic test checklist

1. Start the app with valid BASIC, KERNAL and character ROMs.
2. Confirm that the C64 reaches the BASIC screen.
3. Load a D64 and verify that device 8 is available.
4. Load a CRT and verify that Soft and Hard Reset keep the cartridge inserted.
5. Use **Eject Cartridge and Reset** and verify that the app returns to BASIC.
6. Open and close Settings without modifying firmware and confirm that the C64 session is not restarted.
