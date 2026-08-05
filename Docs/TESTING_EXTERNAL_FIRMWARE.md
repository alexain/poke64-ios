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

On first launch:

1. import valid BASIC, KERNAL and character ROM files;
2. close the Firmware sheet;
3. confirm that the BASIC screen appears;
4. remove or replace one firmware file and confirm that POKE64 displays a startup error instead of a silent black screen;
5. inspect both JSON reports in `Vendor/Core/`;
6. confirm that the dylib is ignored by Git.

Do not tag a release until the exact `vice-libretro` revision has passed this clean-device test.


During the macOS build, verify that the compiler command still contains:

```text
-I./include/embedded
```

This path is required for VIC-II palette headers. Its presence is expected; firmware safety is enforced by neutralizing exact firmware arrays before compilation and by the final read-only dylib scan.
