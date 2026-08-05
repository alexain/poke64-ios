## 0.2.6

- Fixed external firmware loading for the `vice_x64sc` core by writing firmware resources under the `[C64SC]` `vicerc` section.
- Existing imported firmware is reused; the configuration file is regenerated automatically at application startup.
- Improved startup diagnostics so generic trailing VICE errors no longer replace a more useful preceding error.

## 0.2.5

- Show complete libretro/VICE startup errors in an alert instead of truncating them in the top bar.
- Keep a shortened two-line status summary in the emulator header.
- Surface content-loading and file-import errors through the same diagnostic UI.

# Changelog

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
