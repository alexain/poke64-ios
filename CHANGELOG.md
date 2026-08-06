# Changelog

## Unreleased

### Added

- Added Commodore MPS-803 text and bit-image rendering through a locally patched VICE printer core.
- Added PDF output as the default virtual-printer format, plus PNG pages and optional PDF + RAW export.
- Added live paper preview, dot-intensity controls and multi-file sharing for completed print jobs.
- Added an optional 4 KB MPS-803 printer-ROM import slot and documented the printer firmware policy.
- Added experimental IEC device 4 or 5 RAW printer capture for validating C64 printing through the libretro core.
- Added a contextual PRN 4/5 status panel beside the emulator with capture size and activity feedback.
- Added a Virtual Printer sheet for previewing, sharing, ejecting and discarding the active paper.
- Added persistent completed print jobs when ejecting virtual paper.
- Added docked datasette controls with Play, Stop, Rewind, Fast Forward and counter reset.
- Added native VICE tape transport telemetry, motor/activity status and a three-digit TAP counter in the emulator side margin and Devices panel.
- Added Tape settings for automatic control presentation, counter reset on insertion, CPU-reset behavior and tape autostart load mode.

### Changed

- Changed printer paper eject and discard to operate without restarting the C64 or detaching mounted media.
- Added selection between IEC printer devices 4 and 5.
- Moved datasette control access from the main toolbar to the tappable tape counter/status panel beside the emulator.
- Kept the tappable datasette status panel compact when the keyboard or control dock reduces the emulator display size.
- Set the default datasette sound level to 20%, matching the default mechanical drive-noise level.
- Limited T64 controls to operations that do not imply a physical reel position; T64 fast transport and counter reset are disabled.
- Updated the roadmap to mark datasette transport as complete and retain writable TAP recording/export as future work.

## 0.7.0 — 2026-08-06

### Added

- Added an IEC virtual printer selectable on device 4 or 5.
- Added Commodore MPS-803 text, PETSCII and bit-image rendering through the VICE printer core.
- Added PDF output as the default format, with optional PNG pages, RAW diagnostic capture and PDF plus RAW export.
- Added a live paper preview with scrolling, full-screen zoom and automatic updates during printing.
- Added a contextual PRN 4/5 status panel with ready and flashing printing states.
- Added paper eject and discard operations that preserve the running C64 session and mounted media.
- Added persistent completed print jobs and sharing of generated output.
- Added a user-supplied 4 KB MPS-803 printer-ROM slot with exact-size validation.

### Changed

- Restored the real VICE MPS-803 driver in place of the libretro printer stub.
- Added a sandbox-safe grayscale raster backend compiled as part of the GPL VICE component.
- Pinned the VICE/libretro source used by this release to `c8c242db75a559246d6d51017e6dd4ecd75d6a9f`.
- Changed printer refresh and sharing actions to flush active output before reading it.

### Fixed

- Fixed retention and export of printer bridge symbols used through `dlsym()`.
- Fixed false symbol-verification failures caused by `pipefail` and early `grep` termination.
- Fixed short RAW captures appearing empty until a larger buffered print was produced.

### Documentation

- Updated the README, roadmap, firmware policy and third-party notices for the virtual printer.
- Documented the exact VICE/libretro revision and the licensing boundary between the MIT application and GPL printer backend.

## 0.6.5 — 2026-08-06

### Added

- Added complete datasette support for TAP and T64 media.
- Added native Play, Stop, Rewind, Fast Forward and tape-counter controls where supported.
- Added datasette motor, read activity and transport status indicators.
- Added a collapsible datasette control panel below the emulator.

### Changed

- Changed T64 handling to always use autostart and reserved the on-screen datasette transport, counter and status controls exclusively for TAP images.
- Moved datasette control access from the top toolbar to the side tape-status panel.
- Kept the side tape-status panel compact when the keyboard or datasette controls are visible.
- Set the default datasette audio volume to 20%.
- Updated the roadmap to reflect the completed datasette implementation.

## 0.6.2 — 2026-08-06

### Added

- Added configurable Commodore REU support from 128 KB through 16 MB in Settings → System.
- Added optional persistent REU memory backed by an app-managed image file.
- Added REU size, activity and persistence status to the Devices interface.

### Fixed

- Improved Commodore 1351 mouse handling, including compatibility with Final Cartridge III.

### Documentation

- Added planned iCloud Drive and Google Drive backup/synchronization for the library, imported media and user-supplied firmware/ROM files.

## 0.6.0 — 2026-08-06

### Added

- Added functional System settings for C64 PAL, C64 NTSC, C64C PAL and C64C NTSC profiles.
- Added Graphics settings for aspect ratio, crop, VIC-II palette, PAL filtering, crop delay and color adjustments.
- Added Audio settings for FastSID, ReSID and ReSID-FP, SID model, ReSID sampling, sample rate, VIC-II audio leak and datasette sound.
- Added an optional pinned MEGA65 OpenROMs profile with backup and restoration of an existing complete system-ROM set.
- Added a unified Devices control for Drive 8, optional Drive 9, datasette and cartridge status and actions.
- Added configurable 1541, 1541-II, 1571 and 1581 drive models with exact-size firmware slots.
- Added global Fast Virtual Drive or True Drive Emulation for all enabled drives.
- Added True Drive ROM initialization, compatible JiffyDOS configuration, write protection and mechanical drive sound.
- Added Drive 8 and Drive 9 power indicators plus the aggregate floppy-activity LED exposed by libretro.
- Added optional Drive 9 with independent model, mounted media, insert, replace, autostart and eject actions.
- Added D71 and D81 import, temporary opening, Library actions and drive-model compatibility checks.
- Added creation of formatted or completely blank D64, D71 and D81 images from Library and Devices.

### Changed

- Moved True Drive Emulation into a shared Drive Emulation section because the selected backend applies to every enabled unit.
- Clarified that drive ROMs are shared by model rather than assigned separately to Drive 8 or Drive 9.
- Extended configuration fingerprinting so System, Graphics, Audio and Disk Drives restart the core only when their saved values change.
- Improved VICE runtime drive initialization so True Drive media insertion loads the selected ROM and activates the configured drive model before attachment.

## 0.5.5 — 2026-08-06

- Changed Settings to a stable full-screen presentation with an always-visible Done button.
- Replaced the modal C64 keyboard with a docked Compact/Full keyboard that keeps the emulator display visible.
- Added dynamic Shift and Commodore legends, including color labels for Commodore plus number combinations.
- Changed Shift and Commodore to momentary touch modifiers.
- Added persistent Shift Lock behavior, including shifted function keys.
- Improved adaptive keyboard sizing and removed keyboard scrolling.

## 0.5.1 — 2026-08-06

- Added media-specific actions shared by Open and Library: direct PRG execution, CRT insertion with reset, D64 insertion or autostart in Drive 8, and TAP/T64 insertion or autostart in the datasette.
- Added replacement confirmation when a drive, datasette or cartridge slot already contains another medium.
- Added runtime VICE bridging for disk, tape and cartridge mounting, detaching and autostart without routing every action through generic content loading.
- Changed Soft Reset and Hard Reset to preserve mounted disks, tapes and cartridges.
- Added **Eject All Media and Reset** to detach every mounted medium, clear temporary media and restart the C64 empty.
- Added shared media-action state and dialogs that can be reused by the future Devices interface.
- Fixed empty virtual drives so `LOAD"$",8` reports `DEVICE NOT PRESENT` instead of exposing the application sandbox filesystem.

## 0.5.0 — 2026-08-05

- Added a persistent media library for D64, PRG, CRT, TAP and T64 files.
- Added library search, favorites, recent usage, editable titles and deletion.
- Added direct media launch from the library and automatic tracking of the currently running item.
- Changed the main Open action to launch media from a temporary session directory instead of importing it automatically.
- Added automatic cleanup of temporary media when the application starts.
- Kept temporary media mounted across Soft Reset; Hard Reset now ejects temporary content, clears its cache and restarts the C64 empty.
- Added Add to Library for the currently running temporary file, while retaining direct persistent import from the Library.
- Added a full-screen Library with an always-visible header containing Import and Done actions.
- Added media-specific Library artwork for disks, programs, cartridges and tapes.
- Replaced the separate Port 1 and Port 2 toolbar controls with a unified Ports popover and a Swap Port 1 and Port 2 command.
- Redesigned the main toolbar as a centered, fixed-height, horizontally scrollable command bar so input changes do not resize the emulator canvas.
- Removed automatic migration of files from the legacy Documents/Imported directory.

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
