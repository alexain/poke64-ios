# Roadmap

## Firmware

- named firmware profiles;
- additional drive models and ROM slots;
- known-ROM identification database without restricting custom firmware;
- profile export/import without embedding firmware data;
- clearer diagnostics when VICE rejects a firmware combination;
- investigate an upstreamable compile-time option that disables embedded firmware before linking.

## On-screen keyboard

- replace the sheet with a keyboard panel attached to the bottom edge;
- support compact height and rotation without obscuring the video;
- preserve held modifiers across virtual-key presses;
- optional haptic feedback.

## Input

- `GCController` integration;
- default joyport selection;
- controller remapping;
- paddle and mouse support;
- customizable touch layout.

## Media

- Disk Control interface;
- M3U multidisk selection and disk swapping;
- tape and cartridge management;
- local library with metadata and artwork.

## Emulation

- VICE core options;
- per-content configuration;
- PAL/NTSC and C64 model selection;
- SID settings;
- save/load states and thumbnails;
- cartridge freeze support.

## Rendering and audio

- integer scaling;
- optional CRT shaders;
- configurable overscan and crop;
- adaptive audio/video synchronization;
- audio interruption and route-change handling.

## Distribution

- pin a verified VICE commit for each POKE64 release;
- automated frontend tests;
- CI static checks;
- privacy manifest and TestFlight/App Store preparation;
- independent final license and firmware-distribution review.
