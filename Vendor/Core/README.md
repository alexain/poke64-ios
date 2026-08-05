# Local core output

Run:

```bash
./Scripts/build_vice_core.sh
```

The script creates an unsigned local core compiled with the POKE64 source-level external-firmware patch:

```text
vice_x64sc_libretro_ios.dylib
```

It also creates two local reports:

```text
external-firmware-source-patch-report.json
external-firmware-verification-report.json
```

The verifier does not modify the linked Mach-O file. It rejects the build if an exact upstream firmware payload is detected.

The dylib and both reports are excluded from Git. `Scripts/embed_core.sh` copies and signs the dylib during the Xcode build.
