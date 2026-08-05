# Changelog

## Unreleased

- Added a persistent media library for D64, PRG, CRT, TAP and T64 files.
- Added library search, favorites, recent usage, editable titles and deletion.
- Added direct media launch from the library and automatic tracking of the currently running item.
- Changed the main Open action to import media into the library before launching it.

## 0.4.2

- Changed both C64 joyports to default to `None` at application startup.
- Added multiple physical-controller discovery and per-port assignment using Game Controller.
- Mapped each controller's D-pad and left stick to C64 directions, with both A and B acting as FIRE.
- Added Commodore 1351 mouse assignment for either joyport.
- Added touchscreen trackpad gestures: one-finger movement, one-finger left click and two-finger right click.
- Added external mouse and trackpad movement plus left, right and middle button input.

## 0.4.1

- Prevented the native iPadOS software keyboard from appearing when interacting with the Port 1 and Port 2 menus.
- Fixed the joyport menu labels to a stable width and a non-morphing port icon.
- Removed the virtual-joystick port caption from the emulation area.
- Updated README, About and GitHub repository wording to describe POKE64 as a native Commodore 64 emulator.
- Refreshed the README banner without the word “frontend”.

## 0.4.0

- Redesigned the iPad toolbar and removed the manual Start/Stop and generic Controls buttons.
- Added independent Port 1 and Port 2 assignment menus.
- Added exclusive virtual-joystick routing: the on-screen joystick can be assigned to either C64 port, but never both.
- Added visible placeholders for future physical-controller and Commodore-mouse assignments.
- Added project credits and the official POKE64 website link to the README and About panel.

## 0.3.3

- Forced VICE Virtual Device Traps for reliable D64 loading while the dedicated drive configuration layer is still under development.
- Temporarily disabled True Drive Emulation and drive sound at the libretro core-option level so core defaults do not leave device 8 unavailable.
- Removed the invalid early `Drive8Type` assignment from generated firmware configuration.
- Added **Eject Cartridge and Reset**, shown only when a CRT cartridge is loaded.
- Kept Soft Reset and Hard Reset hardware-accurate: an inserted cartridge remains attached across both reset types.
- Reduced the root README to a project overview and moved build instructions, architecture details and the roadmap into dedicated documentation files.

## 0.3.2

- Fixed D64 loading without a drive ROM by enabling VICE virtual device traps when True Drive Emulation is unavailable.
- Added separate Soft Reset and Hard Reset actions without automatic content relaunch.
- Prevented closing Settings from restarting the emulator when firmware files have not changed.
- Added firmware configuration fingerprinting so a core restart occurs only after an actual ROM change.

## 0.3.1

- Added a branded launch screen and an in-app startup overlay while VICE initializes.
- Added the POKE64 app icon to the About panel.
- Added creator credits for Alessandro Capano, 2026, and www.alexain.it.

## 0.3.0

- Added an iPad-first Settings modal based on `NavigationSplitView`.
- Added System, Graphics, Audio, Tape, Disk Drives, Printer, Firmware / ROMs, Networking and About panels.
- Embedded the existing firmware manager into the new Settings architecture.
- Added structured placeholders for features that will be implemented incrementally.
- Added an About panel with build information, technology credits and licensing guidance.
- Changed the current deployment target to iPad only; iPhone and macOS adaptations remain future work.
- Expanded the README and project roadmap with Library, Apple input, hardware-link and long-term development features.

## 0.2.6

- Fixed external firmware loading for the `vice_x64sc` core by writing firmware resources under the `[C64SC]` `vicerc` section.
- Existing imported firmware is reused; the configuration file is regenerated automatically at application startup.
- Improved startup diagnostics so generic trailing VICE errors no longer replace a more useful preceding error.

## 0.2.5

- Show complete libretro/VICE startup errors in an alert instead of truncating them in the top bar.
- Keep a shortened two-line status summary in the emulator header.
- Surface content-loading and file-import errors through the same diagnostic UI.

## 0.2.4 — 2026-08-05

### Fixed

- preserve the upstream `include/embedded` compiler path required by VIC-II palette headers;
- prevent the `vicii_c64hq_vpl.h` and related generated-palette build failure;
- neutralize only generated arrays whose byte contents exactly match C64 or drive firmware payloads;
- keep palette and other non-firmware generated resources unchanged;
- extend tests to verify that firmware arrays are neutralized while palette headers remain intact.

## 0.2.3 — 2026-08-05

### Fixed

- keep all upstream `embedded_check_file(...)` call sites compilable after the embedded firmware declarations are disabled;
- force those checks to return zero in external-firmware-only builds so VICE continues with normal filesystem lookup;
- extend the source-patch test fixture to cover the unguarded call pattern present in current `sysfile.c`.

## 0.2.2 — 2026-08-05

### Added

- source-level external-firmware patch applied before VICE compilation;
- read-only final dylib verification with no Mach-O mutation;
- source patch and firmware verification reports;
- startup diagnostics for VICE logs, frontend messages and shutdown requests;
- first-frame startup check to prevent silent black-screen failures;
- expanded project roadmap covering settings, joyports, keyboard, drives, CRT, printer and networking.

### Removed

- post-link `scrub_embedded_firmware.py` binary rewriting.

### Changed

- README and local core documentation now describe the source-level workflow;
- publication checks reject the new local reports and continue to exclude all local core outputs.

## 0.2.1 — 2026-08-05

- Added a full iOS App Icon asset catalog based on the new POKE64 branding.
- Added a repository banner image for GitHub/README usage.
- Updated the XcodeGen configuration so the App Icon is applied automatically.
- Refreshed the README to reference the included branding assets.


## 0.2.0 — 2026-08-05

### Added

- external firmware settings page;
- import slots for C64 BASIC, KERNAL, character, and optional 1541-II ROMs;
- support for compatible custom firmware such as JiffyDOS;
- exact file-size validation and SHA-256 diagnostics;
- generated `vicerc` configuration using sandbox-local firmware paths;
- startup gate that prevents core execution until required firmware is installed;
- automatic core restart after firmware changes;
- post-link firmware scrubber and verification report for the locally built VICE core.

### Changed

- application UI strings standardized in English;
- VICE core build now fails if expected embedded firmware payload categories cannot be detected and removed;
- GitHub publication script now targets version `0.2.0` and generates the Xcode project before committing.

## 0.1.0 — 2026-08-05

Initial working baseline with a native libretro host, Metal video, AVAudioEngine audio, file import, hardware/on-screen keyboard input, and optional touch controls.
