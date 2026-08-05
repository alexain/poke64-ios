## 0.2.1

- Added a full iOS App Icon asset catalog based on the new POKE64 branding.
- Added a repository banner image for GitHub/README usage.
- Updated the XcodeGen configuration so the App Icon is applied automatically.
- Refreshed the README to reference the included branding assets.

# Changelog

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
