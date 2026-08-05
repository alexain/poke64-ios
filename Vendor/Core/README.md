# Local core output

Run:

```bash
./Scripts/build_vice_core.sh
```

The script creates an unsigned, external-firmware-only local core:

```text
vice_x64sc_libretro_ios.dylib
```

It also creates a local verification report:

```text
firmware-scrub-report.json
```

Both files are excluded from Git. The dylib is copied into the application and signed by `Scripts/embed_core.sh` during the Xcode build.
