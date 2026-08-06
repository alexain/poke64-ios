# Testing the external-firmware core

The source-level patch, generated-header neutralizer and binary verifier can be tested without Xcode:

```bash
python3 Scripts/test_external_firmware_tools.py
./Scripts/check_integrated_sources.sh
```

A complete validation still requires macOS, Xcode and a physical iOS device:

```bash
rm -rf Vendor/vice-libretro-src
rm -f Vendor/Core/vice_x64sc_libretro_ios.dylib
./Scripts/build_vice_core.sh
./Scripts/bootstrap.sh
open POKE64.xcodeproj
```

## Clean-device system-ROM test

On first launch:

1. confirm that POKE64 blocks core startup while BASIC, KERNAL or character firmware is missing;
2. install the pinned OpenROMs profile and confirm that the BASIC screen appears;
3. verify that the displayed OpenROMs revision matches the revision pinned in `FirmwareStore`;
4. replace the system set with valid custom ROM files and confirm that OpenROMs is no longer reported as the active profile;
5. reinstall OpenROMs and verify that a previously complete custom system set can be restored;
6. remove or corrupt one required firmware file and confirm that POKE64 displays a startup error instead of a silent black screen.

## Drive-ROM and True Drive test

For every supported drive slot:

```text
1541       16384 bytes
1541-II    16384 bytes
1571       32768 bytes
1581       32768 bytes
```

1. confirm that an incorrect file size is rejected;
2. import a valid ROM and select the matching drive model;
3. enable True Drive Emulation and confirm that the core restarts cleanly;
4. insert a compatible D64, D71 or D81 image and verify directory access;
5. confirm that mechanical drive sound is available for supported 1541-family and 1571 configurations;
6. enable Drive 9 with the same model and verify that the UI identifies the ROM as shared;
7. enable Drive 9 with a different model and verify that both required ROMs are checked;
8. confirm that an incompatible disk format is rejected before attachment;
9. verify that Fast Virtual Drive still works after True Drive is disabled.

## Build-output verification

Inspect both JSON reports in `Vendor/Core/` and confirm that the dylib remains ignored by Git.

During the macOS build, verify that the compiler command still contains:

```text
-I./include/embedded
```

This path is required for VIC-II palette headers. Its presence is expected; firmware safety is enforced by neutralizing exact firmware arrays before compilation and by the final read-only dylib scan.

Do not tag a release until the exact `vice-libretro` revision has passed the clean-device, custom-firmware and drive-ROM tests.
