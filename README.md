# POKE64

![POKE64 banner](Docs/Branding/poke64-banner.png)

POKE64 is an experimental, native Commodore 64 emulator frontend for iPhone and iPad. It is built with SwiftUI, UIKit, Metal, AVFoundation, the libretro API, and the VICE `x64sc` core.

Version `0.2.1` continues the **external-firmware-only workflow** and adds the first integrated branding assets, including the app icon set and README banner. POKE64 does not include Commodore BASIC, KERNAL, character, or drive ROM images. Users import legally obtained firmware through the app, including compatible replacements such as JiffyDOS.

> POKE64 is an early development project. It is not affiliated with Commodore, the VICE project, RetroArch, or the libretro project.

## Current features

- App icon asset catalog included and ready to use in Xcode

- Native iPhone and iPad application
- Automatic C64 startup after required firmware has been configured
- Minimal libretro frontend implemented in Objective-C++
- VICE `x64sc` core loaded as an embedded and signed iOS dynamic library
- Metal framebuffer rendering
- Audio output through `AVAudioEngine` and a ring buffer
- File import through the iOS document picker
- Hardware keyboard input through a UIKit responder
- Commodore 64 on-screen keyboard
- Optional touch joystick and FIRE overlay
- Firmware management page for BASIC, KERNAL, character, and 1541-II ROMs
- Support for custom KERNAL and drive firmware, including JiffyDOS-compatible images
- Firmware size validation and SHA-256 diagnostics

## Firmware policy

This repository and its release archives do not contain Commodore firmware, games, disk images, tapes, or cartridges.

POKE64 requires these files before the C64 can start:

| Firmware slot | Required size | Required |
|---|---:|:---:|
| C64 BASIC ROM | 8,192 bytes | Yes |
| C64 KERNAL ROM | 8,192 bytes | Yes |
| C64 character ROM | 4,096 bytes | Yes |
| 1541-II drive ROM | 16,384 bytes | No |

The KERNAL and drive slots accept compatible custom replacements. POKE64 validates file size but does not restrict imports to a fixed hash, so patched or replacement firmware can be used.

Imported files are copied into the application sandbox. Their original Files/iCloud location is not required after import.

## External-firmware-only core build

A normal `vice-libretro` build embeds standard machine and drive firmware. POKE64's build pipeline performs an additional verification step before the dylib is signed:

1. build `vice_x64sc_libretro_ios.dylib` from the selected upstream revision;
2. scan the dylib for exact byte-for-byte firmware payloads found in `vice/data/C64` and `vice/data/DRIVES`;
3. replace detected payloads with zero-filled data of the same length;
4. fail the build unless BASIC, KERNAL, character, and drive payload categories were detected;
5. verify that no scanned exact payload remains in the generated dylib;
6. write a local verification report to `Vendor/Core/firmware-scrub-report.json`.

The report and compiled dylib are excluded from Git. This mechanism is a technical safeguard, not a legal opinion or a substitute for an independent distribution review.

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
│   ├── Video callback
│   ├── Audio callback
│   ├── Keyboard and joypad input
│   └── Core and content lifecycle
│
├── Metal renderer
├── AVAudioEngine output
└── scrubbed vice_x64sc_libretro_ios.dylib
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

Extract or clone the repository, then install XcodeGen:

```bash
brew install xcodegen
cd poke64-ios
```

### 1. Build the VICE core

```bash
./Scripts/build_vice_core.sh
```

The output is created at:

```text
Vendor/Core/vice_x64sc_libretro_ios.dylib
```

The firmware verification report is created at:

```text
Vendor/Core/firmware-scrub-report.json
```

Both files remain local and are excluded from Git.

To build a specific VICE branch, tag, or commit:

```bash
VICE_REF=<branch-tag-or-commit> ./Scripts/build_vice_core.sh
```

A fixed commit should be used for reproducible public releases.

### 2. Generate the Xcode project

```bash
./Scripts/bootstrap.sh
```

This creates:

```text
POKE64.xcodeproj
```

`project.yml` is the source definition. The generated `POKE64.xcodeproj` may also be committed so that contributors can open the repository immediately. Xcode user data, signing identities, and DerivedData remain excluded.

The repository also includes an App Icon asset catalog at `POKE64/Assets.xcassets/AppIcon.appiconset`. Once the project is generated, the icon appears automatically as the application icon.

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

When no firmware has been configured, POKE64 does not start the core. The main screen displays **Configure Firmware**.

Open **Firmware** and import:

1. BASIC ROM;
2. KERNAL ROM;
3. character ROM;
4. optionally, a 1541-II drive ROM.

After the settings page closes, POKE64 writes a VICE configuration file and restarts the session automatically when all required system ROMs are valid.

The files are stored under:

```text
Application Support/System/vice/POKE64/Firmware/
```

POKE64 generates:

```text
Application Support/System/vice/vicerc
```

The generated configuration points VICE at the user-imported firmware using application-sandbox paths. If a valid 1541-II ROM is installed, True Drive Emulation is enabled; otherwise it is disabled.

### JiffyDOS example

A typical JiffyDOS configuration uses:

- a standard compatible BASIC ROM;
- a standard compatible character ROM;
- a JiffyDOS C64 KERNAL image in the KERNAL slot;
- a matching JiffyDOS 1541-II image in the drive slot.

POKE64 does not provide or download these files.

## Loading content

After firmware is configured:

- **Open File** imports and starts supported media;
- **Keyboard** opens the C64 on-screen keyboard;
- **Controls** shows or hides the touch joystick and FIRE button;
- **Reset** resets the current core session;
- **Stop** stops the session; **Start** starts it again.

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

## Repository layout

```text
POKE64/
├── App/
│   ├── ContentView.swift
│   ├── EmulatorModel.swift
│   ├── FirmwareStore.swift
│   ├── FirmwareSettingsView.swift
│   ├── HardwareKeyboardCapture.swift
│   └── C64KeyboardView.swift
├── LibretroHost/
├── Rendering/
└── Shaders/

Scripts/
├── build_vice_core.sh
├── scrub_embedded_firmware.py
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
Vendor/Core/firmware-scrub-report.json
Vendor/vice-libretro-src/
DerivedData/
xcuserdata/
*.xcuserstate
```

Do not add firmware images, games, content archives, provisioning profiles, or signing certificates to the repository.

## Publish on GitHub

Install and authenticate GitHub CLI:

```bash
brew install gh
gh auth login
```

Then run:

```bash
./Scripts/publish_github.sh poke64-ios public
```

The publication script regenerates `POKE64.xcodeproj`, initializes Git when necessary, creates the initial commit, creates the GitHub repository, pushes `main`, and publishes the `v0.2.0` tag.

Use `private` as the second argument for a private repository.

Before publishing, inspect the staged files:

```bash
git status --short
```

No dylib, VICE source tree, firmware file, DerivedData directory, or Xcode user data should appear.

## Known limitations

- The C64 on-screen keyboard is still shown as a sheet rather than an iOS-style bottom keyboard panel.
- Only one active firmware set is currently supported; named firmware profiles are planned.
- The first firmware implementation exposes a 1541-II drive slot only.
- Save states and multidisk management are not exposed in the UI.
- `GCController` support has not yet been implemented.
- Audio/video synchronization remains basic.
- The build pipeline has only been exercised manually on physical-device builds.

See [Docs/ROADMAP.md](Docs/ROADMAP.md).

## Licensing

The original POKE64 frontend code is distributed under the license in [LICENSE](LICENSE).

VICE and `vice-libretro` are separate GPL-licensed components. Anyone distributing an application containing the built core is responsible for complying with the exact upstream license obligations, including corresponding-source and notice requirements where applicable.

No Commodore firmware or commercial content is licensed or distributed by POKE64. Users and distributors are responsible for ensuring that they are authorized to use any imported firmware or content.

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## References

- [libretro/vice-libretro](https://github.com/libretro/vice-libretro)
- [VICE core documentation](https://docs.libretro.com/library/vice/)
- [Libretro core development](https://docs.libretro.com/development/cores/developing-cores/)
- [Libretro iOS compilation guide](https://docs.libretro.com/development/retroarch/compilation/ios/)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
