# ISX 1.4 — Kaypro 1 Universal ROM patch

**Patched by Mickey White Lawless**

This directory contains a patched build of **ISX**, Digital Research's *ISIS-II Interface* version 1.4, which runs Intel's ISIS-II 8080 development tools (PL/M-80, FORTRAN-80, ASM80, LINK, LOCATE, ...) under CP/M 2.2. The patch makes ISX work on a **Kaypro 1 with the Kaypro '84 Universal ROM (81-478C)**. Without it, FORT80 and PLM80 print their sign-on banner and then seek drive A forever.

| File | Description |
|------|-------------|
| `ISX.ASM` | ISX 1.4 source (P112 disassembly) with the Kaypro patch |
| `ISX.COM` | Assembled, patched ISX (12,544 bytes) |

---

## Contents

- [Symptom](#symptom)
- [Background: ISX's Intellec monitor page](#background-isxs-intellec-monitor-page)
- [Cause: collision with the uROM's disk vectors](#cause-collision-with-the-uroms-disk-vectors)
- [The fix](#the-fix)
- [Exact changes](#exact-changes)
- [Building ISX.COM](#building-isxcom)
- [Patching an existing ISX.COM](#patching-an-existing-isxcom)
- [Verification](#verification)
- [Portability](#portability)
- [Credits](#credits)

---

## Symptom

On a Kaypro 1 running CP/M 2.2, ISX itself starts normally:

```
A0>isx
ISIS-II INTERFACE VERS 1.4

0>fort80 mypro.src
ISIS-II FORTRAN COMPILER V2.1
```

The compiler then switches to drive A and **seeks indefinitely**, even when every file it needs is on that drive. PLM80 behaves the same way. Accesses to drive B are not affected.

## Background: ISX's Intellec monitor page

ISIS-II programs call the Intellec monitor for console I/O and memory sizing through fixed entry points starting at `F800H`. To support them, ISX copies a 128-byte monitor image from its own code (`loc_57`, at `3100H`) to **`F800H`–`F87FH`** at startup:

| Range | Contents |
|-------|----------|
| `F800H`–`F823H` | 12 entry vectors (`JMP` instructions), fixed by the ISIS-II ABI |
| `F824H`–`F825H` | 2 filler bytes |
| `F826H`–`F87FH` | The routines the vectors jump to |

| Entry | Name | Original routine address |
|-------|------|--------------------------|
| `F800H` | — (error) | `F826H` |
| `F803H` | CI — console input | `F829H` |
| `F806H` | RI — reader input (error) | `F82FH` |
| `F809H` | CO — console output | `F832H` |
| `F80CH` | PO — punch output | `F838H` |
| `F80FH` | LO — list output | `F83EH` |
| `F812H` | CSTS — console status | `F844H` |
| `F815H` | IOCHK | `F84AH` |
| `F818H` | IOSET | `F84FH` |
| `F81BH` | MEMCK — top of memory | `F854H` |
| `F81EH` | — (error) | `F85BH` |
| `F821H` | — (error) | `F85EH` |

The console routines all funnel through a common dispatcher at `F878H`, which indexes into the BIOS jump table.

On the P112, where ISX was distributed, that RAM is unused.

## Cause: collision with the uROM's disk vectors

On the Kaypro, the Universal ROM keeps live CP/M disk data in that page. The ROM's disk-parameter-header setup (`L_0C79`/`L_0D17` in the 81-478C disassembly) assigns:

| Configuration | Drive | Checksum vector (CSV) | Allocation vector (ALV) |
|---------------|-------|-----------------------|--------------------------|
| Floppy only (Kaypro 1) | A | **`F848H`–`F857H`** | `F9F1H` |
| Floppy only (Kaypro 1) | B | `F748H`–`F757H` | `F948H` |
| Hard disk fitted | floppies | — | **`F848H`–`F860H`**, **`F8E7H`–`F8FFH`** |

On a Kaypro 1, drive A's directory checksum vector occupies `F848H`–`F857H`, inside ISX's routine area. It overlaps the CSTS tail, IOCHK, IOSET and **MEMCK (`F854H`)**.

The failure sequence:

1. ISX logs in drive A, and the BDOS writes directory checksums into `F848H`–`F857H`, overwriting part of the monitor code.
2. The compiler prints its banner. The console-output path (`F809H` → `F832H` → `F878H`) lies entirely outside the overlap, so output still works.
3. The compiler calls **MEMCK** at `F81BH` to size its tables, jumps to `F854H`, and executes checksum bytes as code.
4. In the other direction, ISX's copy has overwritten drive A's checksum vector. Every later directory read on A therefore looks like a disk change.

Drive B's checksum vector is at `F748H`, outside the page, which is why only drive A misbehaves.

## The fix

The entry vectors at `F800H`–`F823H` are part of the ISIS-II ABI and cannot move. They also lie in RAM the uROM does not use. Only the routine bodies collide.

The patch keeps the vectors at `F800H`–`F823H` and moves the routine bodies up by `3BH`, to **`F861H`–`F8B8H`**. ISX then copies the two parts separately and **never writes `F824H`–`F860H`**:

| Range | Floppy-only uROM | Hard-disk uROM | Patched ISX |
|-------|------------------|----------------|-------------|
| `F800H`–`F823H` | free | free | entry vectors |
| `F824H`–`F847H` | free | free | not touched |
| `F848H`–`F857H` | **drive A CSV** | floppy ALV | not touched |
| `F858H`–`F860H` | free | floppy ALV | not touched |
| `F861H`–`F8B8H` | free | free | routine bodies |
| `F8B9H`–`F8E6H` | free | free | not touched |
| `F8E7H`–`F8FFH` | free | floppy ALV | not touched |

`F861H`–`F8B8H` is free in **both** uROM configurations, floppy-only and hard disk.

The original single 128-byte copy:

```asm
main1:          lxi     b,80h
                lxi     h,loc_57        ; 3100H
                lxi     d,0F800h
mdsv_move:      mov     a,c
                ora     b
                jz      isx_start
                dcx     b
                mov     a,m
                stax    d
                inx     h
                inx     d
                jmp     mdsv_move
```

became two bounded copies:

```asm
main1:          lxi     h,loc_57        ; 3100H: entry vectors
                lxi     d,0F800h
                mvi     c,24h
                call    mdsv_move
                lxi     h,loc_57+26h    ; stub bodies
                lxi     d,0F861h
                mvi     c,58h
                call    mdsv_move
                jmp     isx_start
mdsv_move:      mov     a,m
                stax    d
                inx     h
                inx     d
                dcr     c
                jnz     mdsv_move
                ret
```

Inside the monitor image, every address that refers to the routine area is raised by `3BH`: the twelve vector targets and the internal jumps to the error routine (`F86AH` → `F8A5H`), the dispatcher (`F878H` → `F8B3H`) and the error data (`F872H` → `F8ADH`, `F876H` → `F8B1H`). The routines themselves are unchanged.

`main` still ends well below `3100H` (`mdsv_move` assembles at `303CH`), so the larger copy routine does not run into the monitor image.

## Exact changes

Compared with ISX 1.4 assembled from the unpatched source, the patch changes only these bytes. Addresses are run-time addresses; the file offset is the address minus `0100H`.

**Copy routine, `3023H`–`3044H`:**

```
old: 01 80 00 21 00 31 11 00 F8 79 B0 CA 00 10 0B 7E 12 23 13 C3 2C 30
     00 00 00 00 00 00 00 00 00 00 00 00
new: 21 00 31 11 00 F8 0E 24 CD 3C 30 21 26 31 11 61 F8 0E 58 CD 3C 30
     C3 00 10 7E 12 23 13 0D C2 3C 30 C9
```

**Monitor image, `3101H`–`3174H`** (each byte is the low byte of an `F8xxH` address):

| Address | Old | New | | Address | Old | New |
|---------|-----|-----|-|---------|-----|-----|
| `3101H` | 26 | 61 | | `3127H` | 6A | A5 |
| `3104H` | 29 | 64 | | `312DH` | 78 | B3 |
| `3107H` | 2F | 6A | | `3130H` | 6A | A5 |
| `310AH` | 32 | 6D | | `3136H` | 78 | B3 |
| `310DH` | 38 | 73 | | `313CH` | 78 | B3 |
| `3110H` | 3E | 79 | | `3142H` | 78 | B3 |
| `3113H` | 44 | 7F | | `3148H` | 78 | B3 |
| `3116H` | 4A | 85 | | `315CH` | 6A | A5 |
| `3119H` | 4F | 8A | | `315FH` | 6A | A5 |
| `311CH` | 54 | 8F | | `3167H` | 6A | A5 |
| `311FH` | 5B | 96 | | `316DH` | 72 | AD |
| `3122H` | 5E | 99 | | `3174H` | 76 | B1 |

That is the complete patch: **34 bytes** in the copy routine and **24 bytes** in the monitor image.

> **Note on the distributed ISX.COM.** The `ISX.COM` in the P112 distribution also differs from a fresh assembly in a few ranges that ISX never executes. These are the unassembled gap at `010DH`–`017FH`, ISX's stack at `2E0FH`–`2E3EH`, the SUBMIT FCB block map at `2E53H`–`2E62H`, and the area after the end of the program (`3181H`–`31FFH`). The distributed file has leftover bytes there; a fresh assembly has zeros. They have no effect.

## Building ISX.COM

With Microsoft MACRO-80 and LINK-80 3.44:

```
M80 =ISX.ASM
L80 /P:0,ISX,ISX/N/E
```

L80 warns `Origin below loader memory, move anyway (Y or N)?`. Answer **Y**.

Because the link origin is `0000H`, the output file starts with 256 bytes of padding for `0000H`–`00FFH`, while a CP/M `.COM` file must start at `0100H`. **Remove the first 256 bytes**. The result is the 12,544-byte `ISX.COM`.

On a host system:

```sh
dd if=ISX.COM of=ISX.NEW bs=256 skip=1
```

On CP/M, use DDT: it loads the 12,800-byte link output at `0100H`–`32FFH`; move it down one page and save 49 pages (12,544 bytes):

```
A>DDT ISX.COM
-M200,32FF,100
-G0
A>SAVE 49 ISX.COM
```

> A plain `L80 ISX,ISX/N/E` is **not** equivalent. L80's default origin is `0103H`, which produces a different file.

`ISX.ASM` must have CR/LF line endings. MACRO-80 stops with `%No END statement` on a file with bare LF endings.

## Patching an existing ISX.COM

If you already have the distributed ISX 1.4 `ISX.COM`, you can apply the 58 bytes in [Exact changes](#exact-changes) directly with DDT or SID. Each file offset is the address minus `0100H`. With DDT the file loads at `0100H`, so you use the addresses as listed. For example:

```
A>DDT ISX.COM
-S3023
3023 01 21
3024 80 00
...
-S3101
3101 26 61
...
-G0
A>SAVE 49 ISX.COM
```

## Verification

- `ISX.ASM` assembles with MACRO-80 3.44 with no errors and links with LINK-80 3.44 to a **12,544-byte** `ISX.COM`, the same size as the distributed file.
- Rebuilding from the source in this directory reproduces this directory's `ISX.COM` byte for byte.
- A byte comparison against the unpatched build shows changes only in `3023H`–`3044H` and `3101H`–`3174H`.
- **On a Kaypro 1 with ROM 81-478C:** ISX 1.4 loads, FORT80 V2.1 loads its overlays from drive A and compiles to completion, and `DIR :F1:` lists drive B. The seek hang is gone.

## Portability

The original ISX needs `F800H`–`F87FH` free. The patched ISX needs **`F800H`–`F823H` and `F861H`–`F8B8H`** free.

The patch was made for, and verified on, the Kaypro Universal ROM layout. On another CP/M system it works wherever those two ranges are free. On a system that happens to use `F880H`–`F8B8H`, the original ISX could work where the patched one does not.

## Credits

- **ISX (ISIS-II Interface) 1.4**: Digital Research.
- **`isx.asm` disassembly**: from the P112 ISX distribution.
- **Kaypro '84 Universal ROM**: Kaypro Computer Corporation.
- **Kaypro patch to ISX**: Mickey White Lawless.
