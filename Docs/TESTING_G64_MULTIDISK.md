# Testing G64 and multi-disk media

This checklist validates the first POKE64 Library implementation for G64 track images, import conflicts and filename-based multi-disk sets.

Use legally obtained test media and keep an untouched backup. G64 images can contain low-level track data and copy-protection structures; use an expendable copy for any write-back test.

## G64 import and startup

1. Configure Drive 8 as a 1541, 1541-II or 1571.
2. For protected or custom-loader software, enable True Drive Emulation and import the matching drive ROM.
3. Import a `.g64` file into the Library.
4. Confirm that the detail view reports `G64`, its SHA-256 value and a 1541-family drive requirement.
5. Try **Insert in Drive 8** first. At the BASIC prompt, use:

   ```basic
   LOAD"$",8
   LIST
   ```

6. Eject the image, then try **Autostart from Drive 8**.
7. Confirm that Soft Reset and Hard Reset retain the mounted G64 image.
8. If the software saves to disk, make a small change using a disposable copy, eject it, reinsert it and verify persistence.

Record separately whether the title works with Fast Virtual Drive and True Drive Emulation. A failure only in Fast Virtual Drive can be expected for software that depends on drive CPU timing or nonstandard track data.

## Multi-disk detection

Import all members together using filenames such as:

```text
Example Game - Disk 1.g64
Example Game - Disk 2.g64
```

or:

```text
Example Game - Disk 1 Side A.d64
Example Game - Disk 1 Side B.d64
Example Game - Disk 2 Side A.d64
Example Game - Disk 2 Side B.d64
```

POKE64 should:

- show one expandable parent row for the detected set;
- display the set title and total number of disks in the parent row;
- show each physical image as a child row with its Disk/Side label;
- show a **Multi-disk Set** section in Media Details;
- order disk numbers numerically and Side A before Side B;
- expose quick insert actions for Drive 8 and, when enabled, Drive 9.

Start the first member with autostart. When the program requests another disk, use one of these non-resetting replacement paths:

1. In the Library, expand the set and insert the requested member.
2. In the emulator side panel, use **Previous**, **Disk List** or **Next** under the mounted drive.

The side panel should show the set name, current member and a position such as `Disk 1 of 3`. Do not autostart replacement disks unless the software explicitly requires a reset.

## Duplicate and conflict handling

1. Import the same file twice. Choose **Use Existing**, then repeat and choose **Import Copy**.
2. Create a different file with the same filename and import it.
3. Verify **Replace**, **Keep Both** and **Skip** independently.
4. After replacement, confirm that the item keeps its title/favorite state but shows the new SHA-256 value and size.
5. Import several files at once with more than one conflict and verify that POKE64 processes the queue one conflict at a time.

## Minimum acceptance result

The feature is ready for integration when:

- at least one ordinary G64 and one protected/custom-loader G64 launch correctly with the appropriate drive mode;
- a two-member disk set can be swapped without restarting the C64;
- a Disk/Side set is grouped and ordered correctly;
- duplicate and same-name conflict choices behave as described;
- existing pre-upgrade Library entries remain visible and receive SHA-256 metadata automatically.
