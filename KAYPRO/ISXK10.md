# ISX 1.4 — Kaypro Universal ROM patch

**Patched by Mickey White Lawless**

A patch to Digital Research's **ISX** (ISIS-II Interface 1.4) so it runs Intel's ISIS-II 8080 tools (PL/M-80, FORTRAN-80, ASM80, LINK, LOCATE) on Kaypros with the **'84 Universal ROM (81-478C)**.

## The problem

ISX emulates the Intellec monitor by copying 128 bytes to `F800H`–`F87FH`: 12 entry vectors, then the routines they jump to. The Kaypro ROM keeps CP/M disk vectors in that same area (its scratch area is `F748H`–`FA99H`):

- **Kaypro 1/2/4:** drive A's checksum vector is at `F848H`. ISX overwrites it, and the BDOS overwrites ISX's MEMCK routine. FORT80 and PLM80 print their banner, then seek drive A forever.
- **Kaypro 10/12:** hard disk partition A's allocation vector starts at `F848H`. ISX overwrites it, which can silently corrupt files.

## The fix

The 12 entry vectors stay at `F800H`–`F823H`, because ISIS programs call them directly. The 88 bytes of routine bodies move to **`F7A8H`–`F7FFH`**, just below the vectors, and every address that refers to them is adjusted.

ISX now writes only `F7A8H`–`F823H`. That range is unused on every 81-478C system with standard floppies, with or without a hard disk.

The binary patch is **79 bytes**: 31 in the startup copy routine (`3023H`–`3044H`) and 48 in the monitor image (`3101H`–`3175H`). The routines themselves are unchanged.

## Building

```
M80 =ISX.ASM
L80 /P:0,ISX,ISX/N/E      (answer Y to "Origin below loader memory")
```

Then remove the first 256 bytes of the output to get the 12,544-byte `ISX.COM`.

## Compatibility

| System | Status |
|--------|--------|
| Kaypro 1/2/4, standard floppies | Supported |
| Kaypro 10/12, hard disk + standard floppy | Supported (not yet tested on hardware) |
| Any system with a Drivetec high-density floppy | **Not supported.** Its 256-byte checksum vector overlaps the `F800H` vectors. |

The first version of the patch, which put the routine bodies at `F861H`, ran correctly on a Kaypro 1: FORT80 V2.1 compiled to completion and both drives worked. This `F7A8H` version runs the same routines from a new address. It has been verified at the binary level but not yet run on hardware.

See `README.md` for the full details, memory maps and the complete byte list.

## Credits

ISX: Digital Research. `isx.asm` disassembly: P112 ISX distribution. Kaypro Universal ROM: Kaypro Computer Corporation. Patch: Mickey White Lawless.
