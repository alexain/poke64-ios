# POKE64

![POKE64 banner](Docs/Branding/poke64-banner.png)

POKE64 is an experimental native Commodore 64 emulator frontend for iPhone and iPad. It is built with SwiftUI, UIKit, Metal, AVFoundation, the libretro API, and the VICE `x64sc` core.

Version `0.2.6` fixes the generated-resource build path used by the source-level external-firmware workflow. The compiler include path for generated resources is preserved for VIC-II palettes, while only generated arrays that exactly match firmware payloads are neutralized before compilation. POKE64 does not include Commodore BASIC, KERNAL, character, or drive ROM images. Users import legally obtained firmware through the app, including compatible replacements such as JiffyDOS.

> POKE64 is an early development project. It is not affiliated with Commodore, the VICE project, RetroArch, or the libretro project.

## Current features

- Native iPhone and iPad application
- Integrated iOS App Icon asset catalog and repository branding
- Automatic C64 startup after required firmware has been configured
- Minimal libretro frontend implemented in Objective-C++
- VICE `x64sc` core loaded as an embedded and signed iOS dynamic library
- Source-level build patch that disables the libretro embedded-firmware path before compilation
- Read-only post-build verification that rejects a dylib containing exact upstream firmware payloads
- Startup diagnostics for VICE messages and `RETRO_ENVIRONMENT_SHUTDOWN`
- Metal framebuffer rendering
- Audio output through `AVAudioEngine` and a ring buffer
- File import through the iOS document picker
- Hardware keyboard input through a UIKit responder
- Commodore 64 on-screen keyboard
- Optional touch joystick and FIRE overlay
- Firmware management for BASIC, KERNAL, character, and optional 1541-II ROMs
- Support for compatible custom firmware, including JiffyDOS images
- Firmware size validation and SHA-256 diagnostics

## Firmware policy

This repository and its release archives do not contain Commodore firmware, games, disk images, tapes, or cartridges.

POKE64 currently requires:

| Firmware slot | Required size | Required |
|---|---:|:---:|
| C64 BASIC ROM | 8,192 bytes | Yes |
| C64 KERNAL ROM | 8,192 bytes | Yes |
| C64 character ROM | 4,096 bytes | Yes |
| 1541-II drive ROM | 16,384 bytes | No |

The KERNAL and drive slots accept compatible replacements. Validation checks file size but does not enforce a fixed hash, allowing patched or alternative firmware.

Imported files are copied into the application sandbox. Their original Files or iCloud location is not required after import.

## External-firmware-only core build

A standard `vice-libretro` build exposes required firmware as embedded data. The current libretro documentation therefore describes those files as optional. POKE64 intentionally uses a different local build workflow.

The `0.2.4` pipeline works before and after compilation:

1. fetch the selected `vice-libretro` revision;
2. reset the local source tree to a clean upstream state;
3. apply the iOS zlib compatibility fix;
4. run `prepare_external_firmware_core.py` against the source tree;
5. disable the embedded-firmware declarations and lookup branches in `vice/src/sysfile.c`;
6. override `embedded_check_file(...)` to return zero so existing call sites fall through to normal filesystem lookup;
7. preserve `include/embedded` because the same generated-resource directory also contains VIC-II palette headers required by `c64embedded.c`;
8. identify generated arrays that exactly match C64 or drive firmware files and replace only those source-array payloads with zero bytes;
9. compile `vice_x64sc_libretro_ios.dylib` normally;
10. scan the completed dylib without modifying it;
11. fail the build if an exact BASIC, KERNAL, character, or drive ROM payload is found.

The previous `scrub_embedded_firmware.py` approach has been removed. POKE64 never edits the linked Mach-O binary. Firmware arrays are neutralized in generated C headers before compilation, while palette and other non-firmware resources remain intact.

Local reports are written to:

```text
Vendor/Core/external-firmware-source-patch-report.json
Vendor/Core/external-firmware-verification-report.json
```

Both reports and the compiled dylib are excluded from Git.

The source patch deliberately fails if it cannot recognize the expected upstream structure. This is safer than silently producing an unverified core, but every newly selected VICE revision must still be tested on macOS and a physical iOS device before release.

## Startup diagnostics

Some libretro cores can request `RETRO_ENVIRONMENT_SHUTDOWN` during startup even when `retro_load_game()` has returned successfully. POKE64 now:

- records VICE log and frontend messages;
- checks for shutdown after core initialization and content loading;
- waits for the first emulated frame;
- reports the captured startup error instead of leaving a silent black screen.

## Architecture

```text
SwiftUI application
├── ContentView and EmulatorModel
├── FirmwareStore and FirmwareSettingsView
├── Hardware keyboard responder
├── C64 on-screen keyboard
├── Optional touch joystick overlay
│
├── Objective-C++ libretro host
│   ├── Environment callbacks
│   ├── Startup diagnostics
│   ├── Video callback
│   ├── Audio callback
│   ├── Keyboard and joypad input
│   └── Core and content lifecycle
│
├── Metal renderer
├── AVAudioEngine output
└── source-patched vice_x64sc_libretro_ios.dylib
```

POKE64 does not embed RetroArch. It implements the required libretro frontend callbacks directly.

## Requirements

- macOS
- A recent Xcode release with the iOS SDK
- Git, Make, Python 3, and Xcode command-line tools
- XcodeGen
- A physical arm64 iPhone or iPad
- An Apple Development Team configured in Xcode

The current core script targets iOS 17.0 or later and physical arm64 devices. The UI can be developed in the simulator, but the device-only VICE dylib cannot be loaded there.

## Prepare the project

Clone the repository and install XcodeGen:

```bash
git clone https://github.com/<your-account>/poke64-ios.git
cd poke64-ios
brew install xcodegen
```

### 1. Build the VICE core

```bash
./Scripts/build_vice_core.sh
```

The output is created at:

```text
Vendor/Core/vice_x64sc_libretro_ios.dylib
```

The source-patch and verification reports are created beside it. All three files remain local and are excluded from Git.

To build a specific branch, tag, or commit:

```bash
VICE_REF=<branch-tag-or-commit> ./Scripts/build_vice_core.sh
```

A verified commit should be pinned for public releases instead of relying on a moving `master` branch.

### 2. Generate the Xcode project

```bash
./Scripts/bootstrap.sh
```

This creates:

```text
POKE64.xcodeproj
```

`project.yml` is the source definition. The generated project may also be committed so contributors can open the repository immediately. Xcode user data, signing identities, and DerivedData remain excluded.

The App Icon asset catalog is located at:

```text
POKE64/Assets.xcassets/AppIcon.appiconset
```

### 3. Build on a device

```bash
open POKE64.xcodeproj
```

In Xcode:

1. select the `POKE64` target;
2. open **Signing & Capabilities**;
3. select your Apple Development Team;
4. change the bundle identifier if required;
5. select a physical iPhone or iPad;
6. build and run.

During the Xcode build, `Scripts/embed_core.sh` copies the local dylib into the app's `Frameworks` directory and signs it with the application identity.

## First launch and firmware import

When no firmware has been configured, POKE64 does not start the core. Open **Firmware** and import:

1. BASIC ROM;
2. KERNAL ROM;
3. character ROM;
4. optionally, a 1541-II drive ROM.

POKE64 writes:

```text
Application Support/System/vice/vicerc
```

and stores imported files under:

```text
Application Support/System/vice/POKE64/Firmware/
```

If a valid 1541-II ROM is installed, True Drive Emulation is enabled. Otherwise it remains disabled.

### JiffyDOS example

A typical JiffyDOS setup uses:

- a compatible BASIC ROM;
- a compatible character ROM;
- a JiffyDOS C64 KERNAL image in the KERNAL slot;
- a matching JiffyDOS 1541-II image in the drive slot.

POKE64 does not provide or download those files.

## Loading content

After firmware is configured:

- **Open File** imports and starts supported media;
- **Keyboard** opens the current C64 on-screen keyboard;
- **Controls** shows or hides the touch joystick and FIRE button;
- **Reset** resets the current session;
- **Stop** and **Start** remain temporary development controls and are scheduled for removal.

Imported media is copied to:

```text
Documents/Imported/
```

## Hardware keyboard mapping

| Hardware keyboard | Commodore 64 key |
|---|---|
| `Esc` | RUN/STOP |
| `Page Up` | RESTORE |
| `Tab` | CTRL |
| Left `Control` | Commodore |
| `Caps Lock` | SHIFT LOCK |
| `Home` | CLR/HOME |
| `Backspace` | DEL |

The mapping is positional. The on-screen C64 keyboard is preferable for machine-specific symbols and keys.

## Roadmap

### 1. Core and firmware

- Complete and validate the source-level external-firmware-only build on a pinned VICE revision.
- Add clearer diagnostics for invalid or incompatible firmware combinations.
- Add named firmware profiles for standard ROMs, JiffyDOS, and custom sets.
- Offer an optional redistributable open-firmware profile when licensing and compatibility checks are complete.
- Disable True Drive Emulation automatically when no compatible drive ROM is available.
- Add further drive firmware slots and known-ROM identification without blocking custom firmware.

### 2. Settings architecture

Replace the current single Firmware sheet with a settings modal containing independent panels. Empty placeholders may be introduced before each feature is implemented.

- **System** — C64 model, CPU/6510 behavior, VIC-II model, PAL/NTSC, CIA and hardware options.
- **Graphics** — palette, color controls, border/crop, aspect ratio, integer scaling and CRT options.
- **Audio** — SID 6581/8580, emulation engine, filters, sampling and dual-SID configuration.
- **Tape** — datasette model, counters, autostart and tape behavior.
- **Disk Drives** — units 8–11, drive models, True Drive Emulation, write protection and drive sounds.
- **Printer** — MPS printer configuration and future Okimate 20 support.
- **Firmware / ROMs** — user firmware, JiffyDOS, open firmware and firmware profiles.
- **Networking** — virtual modem, Telnet/raw TCP and BBS settings.
- **About** — version, credits, licenses, source links and privacy information.

### 3. Top toolbar and expansion devices

- Remove the temporary Start and Stop controls.
- Replace Reset with a menu containing Soft Reset and Hard Reset.
- Add independent Joyport 1 and Joyport 2 menus.
- Allow each joyport to select None, Virtual Joystick, a connected physical controller, or a Commodore mouse.
- Allow the virtual joystick on only one joyport at a time.
- Add a Cartridge/Expansion panel for `.crt` files, REU configuration and future expansions.
- Add a Drives panel for inserting and ejecting media in units 8–11.
- Add a Tape panel with media selection and transport controls.

### 4. Keyboard and input

- Replace the current sheet with a full keyboard attached to the bottom edge, similar to the iOS software keyboard.
- Keep the whole C64 layout visible and adaptive across iPhone, iPad and rotation.
- Implement proper held modifiers, SHIFT LOCK, RESTORE, RUN/STOP, Commodore and CTRL behavior.
- Change visible key legends when Shift or Commodore is active so graphical symbols are shown.
- Add `GCController` support, controller mapping, paddles and Commodore mouse input.

### 5. Drives and tape

- Support configurable units 8, 9, 10 and 11 with compatible disk formats.
- Expose libretro Disk Control and multidisk/M3U operations.
- Add compact drive-status LEDs beside the 4:3 display, using otherwise unused side space.
- Show disabled, ready, inserted, read/write and error states; tapping a LED should open that drive.
- Add synchronized 1541 mechanical sounds with an independent volume control.
- Add full datasette controls for TAP/T64 media, including play, stop, rewind, fast-forward, eject, motor and counter state.

### 6. Graphics and audio

- Add a Metal CRT pipeline with scanlines, masks, curvature, bloom, vignette, persistence and presets.
- Evaluate RetroArch shader implementations individually for license compatibility and Metal performance.
- Add VIC-II palette, crop, scaling and model controls.
- Add SID model, emulation engine, filters and dual-SID settings.

### 7. Printer emulation

- Integrate VICE MPS-801, MPS-802 and MPS-803 output.
- Convert raster printer output into multipage PDF documents.
- Simulate dot-matrix appearance, ribbon intensity, continuous paper, alignment variation and optional printer sounds.
- Add print queue, preview, share/export and manual form feed.
- Investigate a dedicated Okimate 20 interpreter in a later phase.

### 8. Networking and BBS

- Add a virtual Hayes-compatible modem through RS-232/User Port emulation.
- Support Telnet and raw TCP connections for BBS software.
- Add host/port configuration, baud rate, connection status, activity indicators and a BBS address book.

### Development order

```text
external-firmware core
→ settings architecture
→ toolbar and joyports
→ bottom keyboard
→ drive/tape/cartridge management
→ CRT and audio controls
→ printer and networking
```

## Repository layout

```text
POKE64/
├── App/
├── Assets.xcassets/
├── LibretroHost/
├── Rendering/
└── Shaders/

Scripts/
├── build_vice_core.sh
├── prepare_external_firmware_core.py
├── verify_external_firmware_core.py
├── test_external_firmware_tools.py
├── bootstrap.sh
├── embed_core.sh
├── check_integrated_sources.sh
└── publish_github.sh

Vendor/Core/
Docs/Branding/
project.yml
```

## Files that must not be committed

The included `.gitignore` excludes:

```text
Vendor/Core/*.dylib
Vendor/Core/external-firmware-source-patch-report.json
Vendor/Core/external-firmware-verification-report.json
Vendor/vice-libretro-src/
DerivedData/
xcuserdata/
*.xcuserstate
```

Do not add firmware images, games, content archives, provisioning profiles, or signing certificates to the repository.

## Update an existing GitHub repository

After testing the new build locally:

```bash
git add .
git commit -m "POKE64 0.2.3 external firmware core fix"
git push origin main
```

Create the release tag only after a successful clean build and device test:

```bash
git tag -a v0.2.3 -m "POKE64 0.2.3"
git push origin v0.2.3
```

Additional test instructions are available in [Docs/TESTING_EXTERNAL_FIRMWARE.md](Docs/TESTING_EXTERNAL_FIRMWARE.md).

## Known limitations

- The source-level patch is intentionally coupled to recognizable `vice-libretro` source structure and must be retested when upstream changes.
- An open-firmware profile is planned but not yet included.
- The C64 on-screen keyboard is still displayed as a sheet.
- Only one active firmware set and one optional 1541-II ROM slot are currently exposed.
- Save states, multidisk management, physical controllers, mouse, printer and networking are not yet exposed in the UI.
- Audio/video synchronization remains basic.

## Licensing

The original POKE64 frontend code is distributed under the license in [LICENSE](LICENSE).

VICE and `vice-libretro` are separate GPL-licensed components. Anyone distributing an application containing the built core is responsible for the applicable corresponding-source, notice and license obligations.

No Commodore firmware or commercial content is licensed or distributed by POKE64. Users and distributors are responsible for ensuring that they are authorized to use imported firmware and content.

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## References

- [libretro/vice-libretro](https://github.com/libretro/vice-libretro)
- [VICE core documentation](https://docs.libretro.com/library/vice/)
- [Libretro core development](https://docs.libretro.com/development/cores/developing-cores/)
- [Libretro iOS compilation guide](https://docs.libretro.com/development/retroarch/compilation/ios/)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
