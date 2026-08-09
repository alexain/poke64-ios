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

This generates `POKE64.xcodeproj` from `project.yml`. Run it after cloning or after changing `project.yml` or the source-file layout. Normal source edits do not require regeneration.

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

## First launch and firmware

POKE64 opens Firmware / ROMs when the required system set is missing. Choose one of these paths:

- install the pinned MEGA65 OpenROMs BASIC, KERNAL and character profile from the application; or
- import legally obtained custom BASIC, KERNAL and character ROM files.

Required sizes:

```text
BASIC ROM       8192 bytes
KERNAL ROM      8192 bytes
Character ROM   4096 bytes
```

Optional True Drive slots:

```text
1541 ROM       16384 bytes
1541-II ROM    16384 bytes
1571 ROM       32768 bytes
1581 ROM       32768 bytes
```

Imported firmware is stored under:

```text
Application Support/System/vice/POKE64/Firmware/
```

The generated VICE configuration is:

```text
Application Support/System/vice/vicerc
```

The `x64sc` resources are written under `[C64SC]`.

OpenROMs supplies only the C64 system set. True Drive Emulation still requires an appropriate user-supplied drive ROM for every enabled drive model.

## Drive modes

Drive 8 is always enabled. Drive 9 is optional and can use a different model.

**Fast Virtual — Traps** applies to all enabled units. POKE64 selects it by setting `vice_drive_true_emulation=disabled`; the pinned vice-libretro core then automatically enables the Drive 8/9 Virtual Device Traps. It does not execute drive firmware and has no separate trap toggle in the app.

**True Drive — Hardware** also applies to all enabled units. It requires a valid ROM for every selected model and enables hardware-level drive timing, compatible drive-side replacement firmware and mechanical sound. Its **True Drive acceleration** setting can remain Off, use **Automatic** load warp while disk activity is present and no C64 audio is detected, or use **Maximum** to ignore audio detection and enable VICE Warp Boost.

Fast Virtual does not use Automatic Load Warp because the Drive 8/9 traps are already its acceleration mechanism. In this pinned libretro revision, `vice_virtual_device_traps` is used separately for printer device 4; do not add it as an independent disk-backend control without first changing the core behavior.

Available model slots:

```text
1541      D64
1541-II   D64
1571      D64 and D71
1581      D81
```

Drive ROMs are shared by model. Drive 8 and Drive 9 cannot use different ROM variants when both are configured as the same model.

## Repository checks

Before committing:

```bash
./Scripts/check_integrated_sources.sh
git diff --check
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

Do not add proprietary firmware images, JiffyDOS, games, media images, provisioning profiles or signing certificates.

## Basic test checklist

1. Start with valid BASIC, KERNAL and character ROMs and confirm that the C64 reaches BASIC.
2. Change between C64/C64C and PAL/NTSC profiles and confirm that closing Settings restarts the core.
3. Open and close Settings without changing a value and confirm that the current session is not restarted.
4. Import or open D64, D71, D81, PRG, CRT, TAP and T64 media and verify the expected media-specific actions.
5. Create formatted and completely blank D64, D71 and D81 images and confirm that they are added to the Library.
6. Select **Fast Virtual — Traps**, load a compatible disk in Drive 8 and verify directory access and fast KERNAL loading; for an REU-heavy test, ReadyOS should detect the configured REU and preload applications through the trap path.
7. Install the matching drive ROM, select **True Drive — Hardware** and verify disk access, mechanical sound and the activity indicator.
8. With True Drive active, test **True Drive acceleration** in Off, Automatic and Maximum modes. Verify that Automatic/Maximum enter fast-forward only while the drive is active and return to normal speed after disk access completes.
9. Enable Drive 9, mount different compatible images in units 8 and 9 and verify independent load and eject operations.
10. Verify that incompatible combinations such as D71 with a 1541-II or D81 with a 1571 are rejected before mount.
11. Load a CRT and verify that Soft and Hard Reset keep it inserted.
12. Use **Eject All Media and Reset** and verify that every mounted device returns to an empty state.
