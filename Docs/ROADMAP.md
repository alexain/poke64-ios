# POKE64 roadmap

POKE64 is designed for **iPadOS first**. Landscape remains the primary interface target, with an adaptive portrait layout for the emulator toolbar and status panels. iPhone and macOS adaptations will be considered after the core iPad experience is stable.

This document lists only work that is still pending. Completed Library foundations, G64 support, duplicate handling, disk inspection, Library artwork/screenshots, multi-disk detection, keyboard, Devices, video, audio, Drive 8–11, physical-keyboard host-layout mapping, REU including external `.reu` image import, datasette transport, the MPS-803 virtual printer, the Virtual Hayes modem/BBS foundation, Emulation/Firmware Profiles, C64 Power control and automatic Previous Session restore have been removed.

## 1. Core, firmware and diagnostics

- Automate verification and release-note recording of the exact pinned VICE/libretro revision used by every release build.
- Make the external-firmware-only core build fully reproducible from a recorded revision and patch set.
- Improve startup, firmware, drive-ROM and media-operation diagnostics.
- Add known-ROM identification and clearly label standard, JiffyDOS and other recognized replacements.
- Add explicit per-model firmware profiles while preserving the VICE limitation that a model's ROM is shared by every unit using it.
- Verify pinned OpenROMs downloads with recorded hashes and surface upstream revision/license information in release material.

## 2. Profiles and remaining settings

- Add per-title Emulation Profile assignment and selective overrides without binding mounted media to the hardware profile itself.
- Add known-ROM identification/status to Firmware Profiles, including recognized Commodore and JiffyDOS replacements where licensing permits identification.
- Extend logical input/joyport configuration into profiles without binding a profile to a specific physical controller instance.
- Add advanced options only where they can be applied safely without destabilizing the current core lifecycle.
- Evolve Emulation Profiles toward complete machine/hardware profiles backed by the same hardware-configuration model used by the emulator, including expansion devices, SID layout, drive topology and conflict validation.
- Add profile import/export for hardware configurations once the schema is stable, without embedding copyrighted ROMs, firmware or media.

## 3. Library and media management

- Add other disk formats after their drive and write-back requirements are handled reliably.
- Add an optional cover/grid view while retaining the detailed list.
- Preview BASIC listings where practical.
- Add manual multi-disk grouping and editing for sets that cannot be inferred reliably from filenames.
- Associate hardware profiles, joyports, firmware and save states with library entries.
- Add explicit export/share workflows for created or modified disk images.
- Add optional iCloud Drive and Google Drive backup/synchronization for the library, imported media and user-supplied firmware/ROM files, supporting recovery after app reinstallation and synchronization across multiple devices.

## 4. Keyboard, control ports and input

- Redesign the **Control Ports** panel before adding more joyport devices so it remains compact and device-oriented rather than becoming a long list of controls. Keep the frequently used **Swap ports** action at the top and always reachable without scrolling.
- Generalize each control port around a selected emulated device (Joystick, Paddles, KoalaPad, 1351 mouse and future VICE-supported devices), with a dedicated device-specific virtual control surface instead of crowding every option into the port configuration panel.
- Add virtual **Paddles** with the real two-controls-per-port topology: two independent analog controls and two fire buttons on one C64 control port, multi-touch operation for simultaneous players, and an iPad-friendly drag gesture rather than requiring literal circular knob motion. Evaluate split mapping to separate physical game controllers where supported by the pinned core.
- Add a **KoalaPad** control surface presented as a bottom sheet/panel that keeps the C64 display visible. Map touch and Apple Pencil position absolutely to the emulated tablet X/Y coordinates, expose both KoalaPad buttons, and validate latency/scaling with period graphics software.
- Make the Control Ports state part of `HardwareConfiguration`/Hardware Map so mutually exclusive devices on the same port are represented and validated by the same compatibility system as other expansion hardware.
- Test additional Commodore 1351 software and refine pointer sensitivity where needed.
- Investigate Apple Pencil as a Commodore mouse, light pen or graphics pointer in addition to the dedicated KoalaPad mapping.

## 5. Media and expansion devices

- Add optional drive units 10 and 11.
- Expand compatibility testing for the explicit Fast Virtual — Traps and True Drive — Hardware backends across standard KERNAL loaders, JiffyDOS, common fastloaders and REU-heavy software such as ReadyOS; keep ReadyOS CRT+D64 with a 16 MB REU as a regression case for fast trap-based preload.
- Expose independent per-drive activity indicators by connecting to a VICE API that identifies the active unit; the current libretro LED is aggregate.
- Add safe writable TAP recording, explicit write-back and export before exposing the datasette RECORD control.
- Extend cartridge handling for supported expansion devices beyond basic CRT attachment, including cartridge-type identification in the Library. Prophet64 CRT images already use VICE's native type-43 emulation through normal CRT auto-detection; optional raw 256 KiB Prophet64 BIN import can be evaluated separately because a bare `.bin` does not identify its cartridge type safely.
- Add explicit export/share for modified external REU images and clarify snapshot/write-back workflows.

### Hardware configuration, conflict management and Hardware Map

Build this before the historical-expansion list grows substantially so new devices plug into one shared model rather than accumulating device-specific UI rules.

- Introduce a POKE64-owned `HardwareConfiguration` model as the single source of truth for the emulated machine's hardware topology. It should describe machine/firmware selection, memory expansions, cartridge slot, SID configuration, IEC devices, I/O expansions and other resources that affect compatibility.
- Add a central compatibility/conflict resolver. Each emulated device should declare the resources it consumes, including CPU/I/O address ranges, cartridge/expansion slots, IEC device numbers and mutually exclusive or size-limited relationships.
- Distinguish hard conflicts from compatibility warnings and informational/shared-resource states. Prevent known-invalid configurations by default and, where possible, offer safe fixes such as moving SID #2 to a free address or choosing another IEC device number.
- Add an **Advanced Hardware Map** in Settings → System that visualizes the active machine rather than maintaining separate state. Initial views should cover:
  - the C64 CPU/I/O address space, highlighting occupied areas such as SID, IO1/IO2 and expansion registers;
  - cartridge/expansion-port topology and relationships between connected devices;
  - the IEC bus, including printer and Drives 8, 9, 10 and 11;
  - the two control ports, showing the selected joyport device and per-port exclusivity (for example Joystick vs Paddles vs KoalaPad vs 1351 mouse).
- Make Hardware Map entries interactive so a selected address/device can show ownership, active configuration, detected conflicts and available resolutions.
- Keep VICE's own collision behavior as the final backend safeguard, but detect and explain conflicts in POKE64 before applying them whenever the configuration is known.
- Store the complete validated `HardwareConfiguration` inside Emulation Profiles so a profile can reconstruct a complete virtual machine quickly and reproducibly. Loading an older or conflicting profile should run through the same compatibility resolver before it is applied.
- Treat the Hardware Map as both diagnostics and documentation: show enough information to explain why REU, GeoRAM, RAMLink, second SID, cartridges and IEC devices can or cannot coexist without exposing raw VICE options unnecessarily.

### Historical storage and expansion hardware

Add historical expansion hardware incrementally, preferring devices already emulated by the pinned VICE core and exposing them through coherent POKE64 media, firmware and device workflows rather than raw core-option switches. Planned order:

1. **CMD FD-2000 / FD-4000**
   - Expose CMD FD-2000 and FD-4000 as selectable drive models.
   - Add Library/import/mount support for D1M, D2M and D4M media as supported by the active VICE/libretro revision.
   - Add external CMD drive-ROM handling to Firmware Profiles and validate write-back, formatting, disk swapping and compatibility with standard/JiffyDOS environments.
2. **CMD HD**
   - Expose the VICE CMD HD emulation and DHD hard-disk images through a POKE64-owned storage workflow.
   - Support creation/import/mount/eject and safe persistence/export of DHD media.
   - Investigate Normal, Configuration and Installation modes and ensure CMD DOS initialization can be performed without exposing unsafe or confusing low-level controls.
3. **CMD RAMLink**
   - Expose RAMLink and persistent RAMCard images.
   - Validate combinations with REU/GeoRAM-compatible configurations and, where supported by VICE, CMD HD parallel-link behavior.
   - Keep RAMLink state/media persistence explicit and recoverable across app lifecycle transitions.
4. **GeoRAM**
   - Add GeoRAM as a first-class alternative memory expansion, including supported capacity selection and persistent image import/export where available.
   - Keep REU and GeoRAM configuration mutually clear in profiles so software-specific requirements are easy to reproduce.
5. **KoalaPad / Apple Pencil**
   - Expose VICE KoalaPad emulation using iPad touch and Apple Pencil as the primary modern input surface.
   - Map position/buttons deliberately, validate coordinate scaling/latency and test period graphics software.
6. **SwiftLink / Turbo232**
   - Expose ACIA-based SwiftLink/Turbo232 emulation as an advanced networking device.
   - Bridge the emulated serial device to an iPadOS-safe TCP transport for terminal software and BBS access, reusing the Virtual Hayes networking foundation where practical.
   - Keep connection state, baud configuration and disconnect behavior explicit.
7. **CMD SuperCPU 64**
   - Investigate a dedicated `xscpu64` libretro/direct-VICE backend rather than treating SuperCPU as a normal x64sc peripheral option.
   - Evaluate 65C816 execution, 20 MHz timing, SuperRAM/SIMM configuration, firmware requirements, save-state implications and software compatibility.
   - Validate interaction with other CMD devices, especially RAMLink, only after the standalone SuperCPU path is stable.

After the ordered items above, evaluate additional historically relevant hardware where VICE support and iPadOS integration make it practical:

- **IDE64**, including supported cartridge revisions and persistent HDD images.
- **Lt. Kernal** SCSI hard-disk/host-adapter emulation.
- **Dolphin DOS, Professional DOS and SpeedDOS** configurations, including parallel-cable requirements and matching drive ROMs.
- **SFX Sound Expander** and other historically relevant sound expansions where audio routing is reliable.
- **MIDI interfaces** such as Sequential, Passport, Datel/Siel/JMS, Namesoft and Maplin, with a future CoreMIDI bridge where feasible.
- **IEEE-488 storage**, including compatible interfaces and 8050/8250/D9090/D9060-class devices, as a preservation/advanced-user feature.

## 6. Graphics and audio

- Add Metal CRT shaders and presets based on compatible openly licensed shader projects.
- Add scanlines, shadow mask, curvature, bloom, vignette and phosphor-persistence controls.
- Add reusable performance/quality presets for iPad hardware classes.
- Add SID filter controls and finer stereo/mixing controls beyond the completed core-supported second-SID address selection.
- Add external-display mode for connected monitors/TVs: move the C64 video output to the external screen at full screen while keeping the iPad as the control surface for the keyboard, datasette, Devices and other emulator controls.
- Add an explicit move/return display action, preserve the running emulation while switching screens, and handle external-display connection/disconnection gracefully.

## 7. Printer

- Broaden virtual-printer compatibility testing beyond the validated BASIC text, direct bit-image and PrintMaster MPS-801 workflows, including PETSCII-heavy productivity software.
- Add MPS-801, MPS-802 and other VICE printer models after their firmware requirements are defined.
- Add a persistent print-job browser and optional continuous-paper presentation.
- Add printer mechanism sound and finer ribbon-wear simulation.
- Investigate Okimate 20 protocol and color-print support.

## 8. Networking and BBS

- Validate the Virtual Hayes modem against additional C64 terminal software and BBS implementations, including the CCGMS 2021/RetroCampus display-corruption case.
- Implement stricter Hayes compatibility where useful, including real `+++` guard times and functional hardware-flow-control command semantics.
- Investigate RR-Net/Ethernet emulation with an iPadOS-compatible user-space backend rather than relying on raw TAP/pcap access.

## 9. Hardware Link

Investigate integration with Ultimate 64 Elite-II and compatible current Commodore hardware exposing network APIs.

- Discover supported hardware on the LAN.
- Transfer PRG, D64, D71, D81, CRT and library items where the target supports them.
- Mount or eject media and remotely control reset or execution.
- Exchange memory and program data.
- Investigate audio/video streaming where supported by the hardware API.

## 10. iPadOS lifecycle and save states

- Finish lifecycle regression coverage for audio-route changes, audio interruptions, printer activity and Virtual Modem/BBS behavior across inactive/background/restore transitions.
- Keep external resources that cannot survive process termination, especially live BBS/TCP sockets, explicitly disconnected after Previous Session restoration and validate clean reconnection paths.
- Add optional **Library Save States** tied to a Library item rather than global emulator slots: multiple named/timestamped states, screenshot previews, configuration/media metadata and explicit load/delete/replace actions. These states should let games continue from arbitrary points even when the original software has no native save facility.

## 11. Distribution and release engineering

- Automate release builds and archive validation.
- Document the exact source revision and patches corresponding to every distributed core binary.
- Publish the complete corresponding VICE/libretro source and required license material for distributed builds.
- Verify that release packages contain no proprietary Commodore firmware, JiffyDOS or commercial media.
- Record third-party notices and OpenROMs revision/hash information in every release.
- Prepare App Store metadata, privacy declarations and review documentation.

## 12. Long-term and experimental work

### Core abstraction and direct VICE integration

- Keep libretro as the production backend while reducing direct dependencies on `LibretroSession` in new frontend features.
- Define POKE64-owned session interfaces for lifecycle, video, audio, input, media operations and device state so the frontend is not tied permanently to one core host.
- Investigate an experimental `ViceSession` backend that embeds VICE directly through a POKE64 platform/bridge layer, without the libretro translation layer.
- Allow `LibretroSession` and `ViceSession` to coexist during migration and compare compatibility, timing, performance, save states and peripheral behavior on real iPad hardware.
- Consider removing libretro only after the direct VICE backend has reached feature and compatibility parity and offers a clear maintenance or capability advantage.
- Treat a ground-up POKE64 C64 core as a separate research project rather than a planned migration target.
- Preserve and document all GPL/source-distribution obligations associated with VICE regardless of whether libretro remains in the stack.

### Physical Commodore hardware bridge

Experimental research only; do not tie this work to a specific release until the iPadOS transport requirements and hardware compatibility are validated on real devices.

- Investigate class-compliant USB HID adapters such as Keyrah for using original Commodore keyboards and DE9 joysticks as physical POKE64 input devices.
- Investigate XUM1541/ZoomFloppy as a USB-to-IEC bridge for original 1541/1571/1581 drives and IEC printers, reusing VICE/OpenCBM real-device support where practical.
- Evaluate an iPadOS USBDriverKit transport for custom XUM1541-class devices on supported M-series iPads, including Apple entitlement and distribution constraints.
- Explore physical-drive workflows both as live emulated devices and as media tools for reading real disks into D64/G64 images and writing compatible images back to disk.
- Explore real IEC printer output through the same physical bus bridge, including MPS-series devices.
- Investigate class-compliant USB-audio Datasette interfaces for tape capture/import and XUM-style tape adapters for deeper motor/button/data integration.
- Keep physical-hardware support optional and isolated from the normal emulator path so unsupported adapters never affect standard iPad-only operation.

#### C64 Reloaded MK2 companion and real-hardware development target

- Investigate the C64 Reloaded MK2 USB serial/debug interface as a dedicated POKE64 companion target rather than treating it only as another peripheral bridge.
- Research direct USB-C communication with the MK2 through its PL2303-based serial interface, including an optional USBDriverKit transport on supported M-series iPads and the associated entitlement/distribution requirements.
- Detect and display the attached real machine configuration where the MK2 interface exposes it, including VIC-II/PAL-NTSC and installed SID information, and offer an explicit action to match a POKE64 emulation profile to the detected hardware.
- Add a development workflow for sending PRG payloads to the real C64 Reloaded MK2, resetting the machine and launching the transferred program, building on the capabilities demonstrated by the MK2 remote interface and mk2codenet-style workflows.
- Investigate safe remote reset, CPU halt/continue, memory read/write and memory-inspection commands as optional development tools.
- Explore emulator-versus-real-hardware validation: run controlled test programs in POKE64 and on the MK2, capture selected RAM/register-visible state, and compare results to help diagnose compatibility, timing and peripheral issues.
- Consider a dedicated "Run on Real C64" action from the Library or future development workspace, while keeping physical execution clearly separate from normal emulation.
- Investigate whether keyboard/joystick state can be obtained through the existing MK2 controller/debug channel and forwarded to POKE64 as an input bridge; do not assume the MK2 can become a native USB HID device without additional hardware/firmware support.
- Treat the original C64 Reloaded separately unless a comparable programmable/debug interface is identified; prioritize the MK2-specific integration where documented remote-control capabilities exist.
- Keep all real-hardware write/control operations opt-in, explicit and recoverable; never issue reset, memory-write or firmware-related commands merely because an MK2 is connected.

### Integrated C64 development workspace

Future/experimental work, intentionally scheduled after the first App Store release. Treat this as a switchable **Development Mode** built around the running emulator rather than as a separate application.

- Add a dedicated development workspace with project/file browser, source editor and build/output console for Commodore BASIC and 6502/6510 assembly. Keep normal emulation UI uncluttered when Development Mode is off.
- For BASIC, support editable plain-text source and a local tokenizer/export path that produces a normal C64 PRG, with direct injection/load into the running machine for rapid edit → run cycles.
- For assembly, evaluate an embedded assembler/linker that can run entirely inside the app sandbox. Prefer a permissively licensed toolchain suitable for App Store distribution (for example the `ca65`/`ld65` subset of cc65) before considering GPL-only tools such as ACME. Record exact third-party source/license obligations for whichever implementation is selected.
- Keep the build pipeline self-contained and deterministic: source files remain user-visible/editable, generated 6502 code runs only inside the emulated C64, and the feature must not depend on downloading executable native code, plug-ins or compiler extensions. Re-check the current App Store Review Guidelines before implementation/submission.
- Add **Build & Run**, **Build & Inject**, **Reset & Run** and configurable load/start address workflows. Allow generated PRGs to be saved into the Library or exported as normal files rather than existing only as transient emulator state.
- Preserve assembler symbols/source mappings where possible so the debugger can resolve addresses back to labels and source lines.
- Build a POKE64 debugger bridge on top of VICE monitor/debug capabilities rather than polling unrelated frontend state. Expose live CPU registers (`A`, `X`, `Y`, `SP`, `PC` and status flags), disassembly, memory, stack and selected VIC/SID/CIA registers with a controlled refresh rate that does not disturb emulation timing.
- Add breakpoints, conditional breakpoints where the backend permits them, watchpoints, single-step/step-over/continue, memory watches and a compact execution trace. Keep debugger pause/resume semantics explicit so normal emulation audio/video state remains predictable.
- Allow useful debugger layouts such as source + disassembly + registers + memory, with panes that can be shown/hidden independently rather than forcing a desktop-style IDE onto every iPad size.
- Make external-display support a first-class development workflow: for example keep the editor/debugger on the iPad while the connected display shows the C64 output full-screen, and later evaluate the inverse arrangement where supported by iPadOS multi-window/external-display APIs.
- Integrate Development Mode with `HardwareConfiguration`/Emulation Profiles so a project can request a reproducible target machine (PAL/NTSC, SID layout, REU, drives and other compatible hardware) without embedding copyrighted firmware or media. Validate the target through the normal conflict resolver before Build & Run.
- Keep any future online/source-sharing integration separate from the first implementation. The initial development workspace should work fully offline and should never turn remotely downloaded code into new native app functionality.

### Additional platforms

- Adapt the interface for iPhone after the iPad workflow is stable.
- Evaluate native macOS, Mac Catalyst or shared SwiftUI targets.

## Development order

```text
lifecycle hardening + modem/printer resume validation
→ Library per-title save states and per-title Emulation Profile overrides
→ Control Ports redesign + always-visible Swap + virtual Paddles/KoalaPad framework
→ advanced CRT graphics, SID options and external-display support
→ HardwareConfiguration/conflict resolver + Hardware Map v1
→ historical expansion phase: CMD FD-2000/4000 → CMD HD → RAMLink → GeoRAM → KoalaPad/Pencil → SwiftLink/Turbo232 → SuperCPU
→ complete hardware profiles + profile import/export as the expansion model stabilizes
→ printer validation and broader compatibility testing
→ release engineering / App Store preparation and first iPad release
→ post-App-Store platform work and other experimental features
```
