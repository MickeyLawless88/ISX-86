# ISX86 — ISIS-II Interface for MS-DOS

**Ported by Mickey White Lawless**

ISX86 runs Intel's ISIS-II 8080 development tools — **PL/M-80, ASM80, FORTRAN-80, LINK, LOCATE, OBJHEX** — unmodified on an IBM PC under MS-DOS. It is an 8086 assembly port of **ISX**, Digital Research's *ISIS-II Interface* version 1.4, which did the same job under CP/M. It is built from the Kaypro-patched `ISX.ASM`.

ISX86 is a single MASM 3.00 source file assembling to a 14,704-byte `ISX86.EXE`. It comes with 8086 versions of the four ISX companion utilities: `OBJCPM`, `IDUMP`, `SETEOF` and `ISXDIR`.

```
C:\PLM> ISX86

ISIS-II INTERFACE VERS 1.4 (MS-DOS)

0>PLM80 PLMSMP.PLM DEBUG PAGEWIDTH(80)

ISIS-II PL/M-80 COMPILER V3.1
PL/M-80 COMPILATION COMPLETE.      0 PROGRAM ERROR(S)

0>EXIT
```

## Files

| File | Description |
|------|-------------|
| `ISX86.ASM` / `ISX86.EXE` | ISIS-II interface for MS-DOS |
| `ISX86.OBJ`, `.LST`, `.MAP`, `.CRF`, `.REF`, `BUILD.LOG` | Output of the full build (see [Building ISX86](#building-isx86)) |
| `OBJCPM.ASM` / `OBJCPM.EXE` | ISIS absolute object → CP/M `.COM` converter |
| `IDUMP.ASM` / `IDUMP.EXE` | Intel object file record dump |
| `SETEOF.ASM` / `SETEOF.EXE` | Trim CP/M ^Z padding to the exact file length |
| `ISXDIR.ASM` / `ISXDIR.EXE` | Directory listing with exact file sizes |

All sources use CR/LF line endings and are laid out for 4-column tabs.

## Contents

- [Design](#design)
- [The 8080 interpreter](#the-8080-interpreter)
- [Traps and the 8080 memory map](#traps-and-the-8080-memory-map)
- [The ISIS-II system call layer](#the-isis-ii-system-call-layer)
- [Program loader](#program-loader)
- [Command line interpreter](#command-line-interpreter)
- [File names and devices](#file-names-and-devices)
- [Building ISX86](#building-isx86)
- [Using ISX86](#using-isx86)
- [Verification](#verification)
- [Companion utilities](#companion-utilities)
- [A complete PC-hosted PL/M-80 build](#a-complete-pc-hosted-plm-80-build)
- [Reference](#reference)
- [Known limitations](#known-limitations)
- [Credits](#credits)

---

## Design

An 8086 cannot execute 8080 machine code, so a DOS version of ISX cannot just trap system calls the way the CP/M version does. **ISX86** has two halves:

1. **An 8080 interpreter** that runs the unmodified Intel binaries in their own 64 KB segment.
2. **The ISIS-II layer from ISX**, reimplemented on MS-DOS handle calls (INT 21h) instead of CP/M FCBs. ISX's internal BDOS has no role on DOS.

The user-visible behaviour follows ISX 1.4: the `n>` prompt, the internal commands, the program loader, the fifteen ISIS calls, device names, ISX's error codes and the `ERROR nnn, AT USER PC xxxx` report.

The program is a single source file, `ISX86.ASM` (about 3,600 lines), and assembles to a 14,704-byte `ISX86.EXE`.

## The 8080 interpreter

The 8080 registers live permanently in 8086 registers while the interpreter runs:

| 8080 | 8086 | Notes |
|------|------|-------|
| A | AL | |
| F (flags) | AH | The 8080 flag byte (S Z 0 AC 0 P 1 CY) has exactly the same bit layout as the low byte of the 8086 FLAGS register, so `LAHF`/`SAHF` move flags with no conversion. |
| BC | CX | B = CH, C = CL |
| DE | DX | D = DH, E = DL |
| HL | BX | H = BH, L = BL, M = `[BX]` |
| PC | SI | |
| SP | BP | Stack accesses use `DS:[BP]` |
| memory | DS = ES | 64 KB allocated from DOS at startup |

Each of the 256 opcodes has its own handler. Every handler ends by dispatching the next instruction inline:

```asm
NXT     MACRO
        MOV     DI,WORD PTR [SI]
        INC     SI
        AND     DI,0FFH
        SHL     DI,1
        JMP     WORD PTR CS:OPTAB[DI]
        ENDM
```

Flag handling follows 8080 semantics:

- **Arithmetic and logic** (`ADD`, `ADC`, `SUB`, `SBB`, `ANA`, `XRA`, `ORA`, `CMP` and their immediate forms) use the corresponding 8086 instruction followed by `LAHF`. Instructions that consume the carry (`ADC`, `SBB`) start with `SAHF`.
- **`INR`/`DCR`** run as `SAHF / INC / LAHF`. That preserves CY exactly as on the 8080, because 8086 `INC`/`DEC` also leave CF alone.
- **Rotates and `DAA`** run between `SAHF` and `LAHF`.
- **`DAD`** clears CY, adds, and folds the new carry back in, leaving S, Z and P untouched as the 8080 does.
- **`PUSH PSW` / `POP PSW`** swap AL and AH so the stack image is A-high, F-low, and `POP PSW` forces the always-0 and always-1 flag bits.

The undocumented 8080 aliases are honoured: `08H`/`10H`/... as NOP, `CBH` as JMP, `D9H` as RET, `DDH`/`FDH` as CALL. The exception is `EDH`, which ISX86 reserves for its own traps. `HLT` stops the program with `HALT AT xxxx`. `IN` returns `FFH`; `OUT`, `EI` and `DI` are ignored.

The handler source is regular and annotated. Every handler label carries its 8080 mnemonic (`OP_04: ; INR B`, `OP_C2: ; JNZ nn`).

## Traps and the 8080 memory map

ISX86 places small stubs in 8080 memory that use the reserved opcode `EDH` followed by a trap number:

| Address | Bytes | Purpose |
|---------|-------|---------|
| `0000H` | `ED 0D` | Program exit (a program that returns or jumps to 0 ends back at the CLI) |
| `0038H` | `ED 0E` | `RST 7`: reports `BREAK AT xxxx` and returns to the CLI |
| `0040H` | `ED 00 C9` | **ISIS-II system call entry** |
| `F800H` to `F823H` | `ED nn C9` x 12 | Intellec monitor entry vectors |

The monitor vectors:

| Entry | Name | ISX86 behaviour |
|-------|------|-----------------|
| `F803H` | CI | Console input without echo (DOS fn 08h) |
| `F809H` | CO | Console output of C (DOS fn 02h) |
| `F80CH` | PO | Punch output of C (AUX, DOS fn 04h) |
| `F80FH` | LO | List output of C (PRN, DOS fn 05h) |
| `F812H` | CSTS | Console status in A: FFh if a key is ready (DOS fn 0Bh) |
| `F815H` | IOCHK | Returns the I/O byte in A |
| `F818H` | IOSET | Sets the I/O byte from C |
| `F81BH` | MEMCK | Returns top of memory in B:A = `F7FFH` |
| `F800H`, `F806H`, `F81EH`, `F821H` | other | Reported as `ERROR 255, AT USER PC xxxx` |

Programs load at `3100H` or above, exactly as ISX requires, and must end at or below MEMTOP (`F7FFH`). The 8080 stack starts below `3100H`, with a return address of `0000H` pushed so a program that simply returns exits cleanly.

> ISX's original monitor code had IOCHK and IOSET swapped. ISX86 implements them as Intel documents them.

## The ISIS-II system call layer

An ISIS call is `CALL 0040H` with the function number in `C` and `DE` pointing at a parameter block of 16-bit words. The last parameter is always a pointer to the status word. ISX86 implements all fifteen:

| C | Call | Parameters | Notes |
|---|------|------------|-------|
| 0 | OPEN | AFTN$P, PATH$P, ACCESS, ECHO, STATUS$P | Access 1 = read, 2 = write (create/truncate), 3 = update (open or create). `:CI:` returns AFTN 1 and `:CO:` returns AFTN 0. Opening a file that is already open is error 12. An echo file must be open for writing (error 25). |
| 1 | CLOSE | AFTN, STATUS$P | Closing AFTN 0/1 or an already-closed AFTN returns 0, as in ISX |
| 2 | DELETE | PATH$P, STATUS$P | Returns 0 even if the file doesn't exist, matching ISX. Deleting an open file is error 32. |
| 3 | READ | AFTN, BUFFER$P, COUNT, ACTUAL$P, STATUS$P | `:CI:` reads come from the line buffer, at most one line per call. `:BB:` always returns 0 bytes. |
| 4 | WRITE | AFTN, BUFFER$P, COUNT, STATUS$P | A short write is error 7 (disk full) |
| 5 | SEEK | AFTN, MODE, BLOCK$P, BYTE$P, STATUS$P | Modes: 0 return position, 1 backward, 2 absolute, 3 forward, 4 end of file. Positions are 128-byte blocks plus a byte offset. Seeking past EOF extends an update file with zeros; on a read-only file it stops at EOF with error 35. Seeking on a write-only file is error 31. |
| 6 | LOAD | PATH$P, BIAS, SWITCH, ENTRY$P, STATUS$P | Switch 0 loads and returns the entry address (used for overlays); switch 1 loads and transfers control. Load errors are fatal, as in ISX. |
| 7 | RENAME | OLD$P, NEW$P, STATUS$P | Different drives is error 10, an existing target is 11, a missing source is 13 |
| 8 | CONSOLE | CI$P, CO$P, STATUS$P | Accepted and ignored, as in ISX |
| 9 | EXIT | none | Closes all files and returns to the CLI |
| 10 | ATTRIB | PATH$P, ATTRIB, ON$OFF, STATUS$P | Accepted and ignored, as in ISX |
| 11 | RESCAN | AFTN, STATUS$P | AFTN 1 rewinds the `:CI:` line buffer to the start of the command line; anything else is error 21 |
| 12 | ERROR | ERRNUM, STATUS$P | Prints `ERROR nnn, AT USER PC xxxx` and continues |
| 13 | WHOCON | AFTN, BUFFER$P | Writes `:CI: ` or `:CO: ` |
| 14 | SPATH | PATH$P, INFO$P, STATUS$P | Fills the 12-byte info block: device number, name (6), extension (3), device type and drive type. Disk files report type 3 (random access), drive type 1. |

An unknown function number reports `ERROR 18`.

**AFTNs.** AFTN 0 is `:CO:` and AFTN 1 is `:CI:`. AFTNs 2 to 9 are allocated to files and devices.

**The `:CI:` line buffer** works the way ISX's does. When the CLI starts a program, it leaves the whole (uppercased) command line in the buffer, positioned just after the program name. The program's first read of `:CI:` therefore returns its parameters, and `RESCAN` gives it the full line. When the buffer is exhausted, the next read gets a new line from the keyboard.

**Ctrl-C** is caught through INT 23h. A break during console I/O inside an ISIS call returns to the CLI with `^C`.

## Program loader

The loader reads Intel **OMF-80 absolute object** files, the output of LOCATE, through a 512-byte buffer:

| Record | Handling |
|--------|----------|
| `02H` Module header | Skipped |
| `06H` Content | Segment byte must be 0 (absolute). Load address + bias must be at or above `3100H`, and the end at or below MEMTOP + 1 (otherwise error 15). |
| `04H` Module end | If the module type is 1 (main), its offset becomes the entry point |
| `0EH` End of file | Load is complete; at least one content record is required |
| others | Skipped |

Every record's checksum is verified (a bad record is error 16). If no entry point is given, execution starts at the lowest loaded address.

## Command line interpreter

```
ISIS-II INTERFACE VERS 1.4 (MS-DOS)

0>
```

The prompt is the current default drive number followed by `>`. Input is uppercased before it is parsed.

| Command | Action |
|---------|--------|
| `DIR [:Fn:][pattern]` | Directory, four entries per line in ISX's format (`F0: NAME     EXT : ...`). `*` and `?` work; `DIR .OV*` lists by extension. |
| `ERA [:Fn:]pattern` | Delete files. `ERA *.*` asks `ALL FILES (Y/N)?`. |
| `TYPE [:Fn:]file` | Display a text file (stops at ^Z) |
| `REN new=old` | Rename, CP/M style |
| `DBUG` | Prompts `TRACE LEVEL:`. Level 1 or higher prints every ISIS call with its name and parameter words. |
| `:Fn:` | Change the default drive (the prompt changes to `n>`) |
| `EXIT` | Return to DOS (ISX had no exit command; on DOS one is needed) |
| *anything else* | Load and run that ISIS program. An unknown name echoes `NAME?`, like ISX. |

## File names and devices

ISIS pathnames are `:Fn:NAME.EXT`, with a name of up to 6 characters and an extension of up to 3. A name without a drive refers to the current default drive.

**Drive mapping.** By default every drive `:F0:` to `:F9:` maps to the current DOS directory. Any of them can be redirected with an environment variable:

```bat
SET ISISF1=B:
SET ISISF2=C:\PLM\WORK\
```

A trailing `\` is added automatically if the path doesn't end in `:` or `\`.

**Devices:**

| Device | Maps to |
|--------|---------|
| `:CI:` `:TI:` `:VI:` | Console input (AFTN 1) |
| `:CO:` `:TO:` `:VO:` | Console output (AFTN 0) |
| `:LP:` `:L1:` | DOS printer (PRN) |
| `:I1:` `:TR:` `:HR:` `:R1:` `:R2:` | AUX input |
| `:O1:` `:TP:` `:HP:` `:P1:` `:P2:` | AUX output |
| `:BB:` | Bit bucket: writes are discarded, reads return end of file |

Console input and output go through the standard DOS handles, so ISX86 can be driven entirely from redirected files. When input is redirected, each line read is echoed to output, so a transcript shows the commands.

## Building ISX86

Requirements: Microsoft MASM 3.00 and LINK 3.00 (or compatible).

```bat
MASM ISX86;
LINK ISX86;
```

This produces `ISX86.EXE` (14,704 bytes) with no warnings or errors.

The source is laid out for 4-column tabs: labels in column 0, mnemonics in column 12, operands in column 20, comments in column 36. MASM 3.00 does not lengthen out-of-range conditional jumps automatically, so the source uses explicit inverted-branch-plus-`JMP` sequences wherever a target is out of short range.

### Full build with listing, map and cross-reference

These are the files produced when the package's `ISX86.LST`, `ISX86.OBJ`, `ISX86.MAP`, `ISX86.CRF` and `ISX86.REF` were generated, using MASM 3.00, LINK 3.00 and CREF 3.00:

```bat
MASM ISX86,ISX86,ISX86,ISX86;
LINK ISX86,ISX86,ISX86/MAP;
CREF ISX86,ISX86;
```

| File | Size | Contents |
|------|------|----------|
| `ISX86.OBJ` | 19,846 | Object module |
| `ISX86.LST` | 289,584 | Full listing: addresses, object bytes, source, symbol table |
| `ISX86.CRF` | 20,014 | Raw cross-reference data from MASM |
| `ISX86.REF` | 46,761 | Cross-reference report: every symbol with its defining line (`#`) and every reference |
| `ISX86.MAP` | 312 | Segment map |
| `ISX86.EXE` | 14,704 | Executable |

Program layout (from `ISX86.MAP`):

| Segment | Range | Length | Contents |
|---------|-------|--------|----------|
| `CODE` | `00000H`–`03568H` | `3569H` | Interpreter, ISIS layer, CLI, loader and all data |
| `STK` | `03570H`–`0376FH` | `0200H` | 512-byte stack |
| `ZZZ` | `03770H` | 0 | End marker used to shrink the program's memory block at startup |

At startup ISX86 shrinks its memory block to the end of `ZZZ` and allocates a separate **64 KB segment** for the 8080, so it needs about 78 KB of free conventional memory.

> MASM 3.00 cannot print dates after 1999. A listing made with the system clock set to 2026 shows the date as `10-02-<6` in its page header. Nothing else is affected.

## Using ISX86

Add this to `CONFIG.SYS`. PLM80 keeps several files open at once.

```
FILES=20
```

Interactive use:

```
C:\PLM> ISX86

ISIS-II INTERFACE VERS 1.4 (MS-DOS)

0>PLM80 PLMSMP.PLM DEBUG PAGEWIDTH(80)

ISIS-II PL/M-80 COMPILER V3.1
PL/M-80 COMPILATION COMPLETE.      0 PROGRAM ERROR(S)

0>EXIT
```

One-shot use from DOS or a batch file, which runs one ISIS command and returns to DOS:

```bat
ISX86 PLM80 PLMSMP.PLM DEBUG PAGEWIDTH(80)
ISX86 LINK PLMSMP.OBJ,PLM80.LIB,SYSTEM.LIB TO PLMSMP.MOD MAP PRINT(PLMSMP.MAP)
ISX86 LOCATE PLMSMP.MOD MAP SYMBOLS PRINT(PLMSMP.TRA)
ISX86 PLMSMP
```

Scripted use, with redirected input:

```bat
ISX86 <BUILD.TXT >BUILD.LOG
```

> **Source files from CP/M disks** are usually padded to a 128-byte boundary with ^Z (`1AH`). ISIS tools treat those bytes as source text and report errors such as `UNPRINTABLE ASCII CHARACTER` at the end of the file. Run `SETEOF` on such files first; Digital Research's own CP/M 3 build scripts do exactly this before every compile.

## Verification

I tested ISX86 under DOSBox 0.74 with MASM 3.00/LINK 3.00, using the Intel tools and reference outputs from the P112 ISX distribution and the CP/M 3 sources from Digital Research's own distribution. I tested input both from redirected files and from keystrokes typed into the DOSBox window.

**PL/M-80 sample (`PLMSMP`) against the reference outputs produced by real ISX:**

| Step | Output | Result |
|------|--------|--------|
| `PLM80 PLMSMP.PLM DEBUG PAGEWIDTH(80)` | `PLMSMP.OBJ`, `PLMSMP.LST` | byte-identical |
| `LINK PLMSMP.OBJ,PLM80.LIB,SYSTEM.LIB TO PLMSMP.MOD MAP PRINT(PLMSMP.MAP)` | `PLMSMP.MOD`, `PLMSMP.MAP` | byte-identical |
| `LOCATE PLMSMP.MOD MAP SYMBOLS PRINT(PLMSMP.TRA)` | `PLMSMP.TRA` | identical except the MEMORY line* |
| `PLMSMP` | square-root table, 1 to 1000 | correct |

\*LOCATE's MEMORY segment comes from MEMCK. The reference was made under a 60K CP/M system (top `E9FEH`); ISX86 reports `F7FFH`.

**8080 assembler:** `ASM80 X0100.ASM DEBUG` produces an object byte-identical to the reference `X0100`.

**CP/M 3 utilities built from source.** I compiled all **26 PL/M-80 modules** of Digital Research's CP/M 3 utility sources with DR's own command (`PLM80 xxx.PLM DEBUG OPTIMIZE`), many of them pulling in multiple `$INCLUDE` files. All compile with **0 errors**, in about 68 seconds of DOSBox time at maximum CPU speed. I then built four complete utilities from source with DR's exact ASM80 → PLM80 → LINK → LOCATE commands and compared them with the binaries DR shipped:

| Utility | Result |
|---------|--------|
| DATE.COM | byte-identical to DR's distribution |
| TYPE.COM | byte-identical |
| ERASE.COM | byte-identical |
| RENAME.COM | byte-identical |
| DEVICE.COM | Mine is correct. DR's distributed file is one byte short: a `1AH` byte inside a `JMP 1A8FH` was lost to a text-mode copy, leaving a `JMP 218FH` past the end of the program. |
| HELP.COM | Identical apart from a hand patch DR applied to the shipped binary after the build (code that saves the drive byte, written into zero filler, plus three address fixups). That patch isn't in the source, so no build from source reproduces it. |

**CLI and file functions.** DIR (all files and wildcards), TYPE, REN, ERA, drive switching, unknown commands (`FOO?`), one-shot mode, OBJHEX, and ISIS OPEN/READ/WRITE/SEEK/CLOSE/DELETE/RENAME/LOAD/RESCAN/SPATH (as used by PLM80's overlays and work files) all work.

---

## Companion utilities

The P112 ISX distribution includes four utilities with source code. All four are now 8086 programs built with MASM 3.00/LINK 3.00. I tested each against the original CP/M program, running under a CP/M 2.2 emulator, on identical input files.

| Utility | Approach | Original source |
|---------|----------|-----------------|
| OBJCPM | Instruction-for-instruction translation of the 8080 code | `objcpm.asm` (1,389 lines) |
| IDUMP | Instruction-for-instruction translation of the 8080 code | `idump.mac` (278 lines) |
| SETEOF | Native rewrite | `seteof.asm` (53 lines) |
| ISXDIR | Native rewrite | `isxdir.mac` (618 lines) |

**Why two approaches.** OBJCPM and IDUMP use only CP/M BDOS file and console functions: open, close, delete, make, sequential read and write, set DMA, print string, console output and list output. MS-DOS kept those functions with **the same INT 21h numbers and the same FCB layout**, and a DOS program's PSP has the default FCBs at `5CH`/`6CH` and the command tail at `80H`, just like CP/M page zero. So these two could be translated one instruction at a time, which keeps every quirk of their output intact. SETEOF and ISXDIR depend on things DOS doesn't have: ISX's patched-BDOS byte count and the raw CP/M directory and disk parameter block. Those two are rewritten natively with the same behaviour and output.

#### Translation rules (OBJCPM, IDUMP)

- **Registers:** A = AL, B = CH, C = CL, D = DH, E = DL, H = BH, L = BL, M = `[BX]`, SP = SP. Flags live in the real 8086 flags.
- **`INX`/`DCX`** are wrapped in `LAHF`/`SAHF`, because 8086 16-bit `INC`/`DEC` change flags and the 8080 versions don't.
- **`DAD`** updates only the carry.
- **`PUSH`/`POP PSW`** swap AL and AH to keep the 8080 stack image.
- **Conditional jumps, calls and returns** become an inverted short branch around an unconditional one, since 8086 conditional jumps are short-range only.
- **`CALL BDOS`** becomes a small shim: `MOV AH,CL / INT 21H`, followed by `OR AL,AL`. It also treats DOS's "partial last record" read result (`AL=3`, zero-filled) as data. ISIS object files have exact lengths, while CP/M only ever had whole records.
- **`JMP 0`** (warm boot) becomes a DOS exit.
- **Startup** copies the PSP's first 256 bytes into offset 0 of the program segment, so the translated code finds its FCBs and command tail exactly where CP/M put them. It uppercases the tail, 0-terminates it the way the CCP does, and sets the DMA to `80H`.

### OBJCPM

Converts an ISIS absolute object file (LOCATE output) to a CP/M `.COM` file. Optionally it also writes `.SYM` (symbol table) and `.LIN` (line number) files from the debug records.

```
OBJCPM name [$options]
```

| Option | Meaning |
|--------|---------|
| `C` | Produce `.COM` (default on) |
| `L` | Produce `.LIN` (default on) |
| `B` | Base-address handling (default on): the first content record sets the base; a module based at `0003H` gets a `JMP` to its start address written at the front of the `.COM` |
| `P` | Echo the console report to the printer |
| `-x` / `+x` | Turn the following option off/on, e.g. `$-L` |

Output summary:

```
0100 = BASE ADDRESS
0292 = STARTING ADDRESS
0BD9 = NEXT EMPTY ADDRESS
```

**Verified against the original OBJCPM:** for DATE and PLMSMP, the `.COM`, `.SYM` and `.LIN` files and the console output are byte-identical. The same holds for the `$-L`, `$B` and `$-C` option runs and for the `NO OBJECT FILE` error. The `DATE.COM` it produces is also byte-identical to Digital Research's shipped `DATE.COM`.

### IDUMP

Dumps an Intel object file record by record: record type, length, a hex/ASCII dump of the contents, and the checksum byte.

```
IDUMP file
```

```
Record type = 02, length = 000A
0000: 06 50 4C 4D 53 4D 50 00 00                       .PLMSMP..
Checksum byte = 15
```

**Verified:** output byte-identical to the original IDUMP on PLMSMP (7,591 bytes of output), and on a missing file (`File Not Found`).

### SETEOF

Trims CP/M end-of-file padding so ISIS tools see the file's real length.

```
SETEOF file
```

The original counted the ^Z bytes at the end of the file's last 128-byte record and stored that count in the FCB for ISX's patched BDOS. MS-DOS keeps exact file lengths, so the DOS version truncates the file by the same count. It does nothing if the file is missing or empty, or if no file is given, just like the original.

**Verified** on whole and partial last records, a ^Z that is not at the end, a last record that is entirely ^Z, an empty file, and real CP/M 3 sources (DATE.PLM 15,488 → 15,484 bytes, ED.PLM 81,664 → 81,558, COMLIT.LIT 896 → 774). Every result matches the original's rule exactly.

### ISXDIR

A sorted directory listing showing exact file sizes.

```
ISXDIR [d:][filespec]
```

```
Directory for drive A:, user 0

ALPHA   .LIT    1k     128     BETA    .COM    3k    2176
BIG     .DAT   38k   38400     GAMMA   .TXT    2k    1152
MID     .       5k    5120     NOEXT   .       1k     256
ODD     .BIN    2k    1025     ZETA    .PLM    1k     384

8 file(s), total size = 53k bytes.
```

The output is the same as the CP/M original: the header, files sorted by name, two per line, a 5-digit allocated size in k, a 7-digit exact size in bytes, and the totals line. Wildcards follow CP/M rules through DOS FCB search, so `B*` means "name starting with B, no extension". The "k" column is computed from the drive's cluster size, where the original used the CP/M block size. DOS has no user areas, so the user is always 0.

**Verified** against the original for layout, sorting, wildcard matching and the `No such file(s).` message, and on a real 360K FAT12 disk image for the allocation figures (1025 bytes → 2k, 38400 → 38k).

---

## A complete PC-hosted PL/M-80 build

With ISX86 and the utilities, the whole CP/M program build runs on a PC. Here is Digital Research's CP/M 3 `DATE` utility, built from source:

```bat
SETEOF DATE.PLM
SETEOF MCD80A.ASM
ISX86 ASM80 MCD80A.ASM DEBUG
ISX86 PLM80 DATE.PLM PAGEWIDTH(100) DEBUG OPTIMIZE
ISX86 LINK MCD80A.OBJ,DATE.OBJ,PLM80.LIB TO DATE.MOD
ISX86 LOCATE DATE.MOD CODE(0100H) STACKSIZE(100)
OBJCPM DATE
```

The resulting `DATE.COM` is byte-identical to the one Digital Research distributed with CP/M 3.

To build an ISIS program instead, link with `SYSTEM.LIB` (which supplies the ISIS interface) and run the located module directly under ISX86.

---

## Reference

### ISIS-II error codes used

| Code | Meaning |
|------|---------|
| 2 | AFTN does not specify an open file |
| 3 | Too many open files |
| 4 | Illegal pathname |
| 5 | Illegal or unrecognised device |
| 6 | Write to a file open for input |
| 7 | Disk full |
| 8 | Read from a file open for output |
| 9 | Cannot create file |
| 10 | Pathnames refer to different drives |
| 11 | Rename target already exists |
| 12 | File already open |
| 13 | No such file |
| 15 | Load address outside the user area |
| 16 | Illegal object file format / checksum |
| 17 | Rename/delete of a non-disk file |
| 18 | Unrecognised system call |
| 19 | Seek on a non-disk file |
| 20 | Seek before beginning of file |
| 21 | RESCAN of a non-line-edited file |
| 22 | Illegal access mode |
| 23 | Missing filename |
| 24 | Disk I/O error |
| 25 | Illegal echo file |
| 27 | Illegal seek mode |
| 31 | Seek on a write-only file |
| 32 | Delete of an open file |
| 33 | Illegal system call parameter |
| 35 | Seek past end of a read-only file |
| 255 | Unsupported monitor entry |

### ISIS-II device numbers

Used by SPATH:

| No. | Device | No. | Device | No. | Device |
|----|--------|----|--------|----|--------|
| 0 to 9 | `:F0:` to `:F9:` | 16 | `:TR:` | 23 | `:P2:` |
| 10 | `:TI:` | 17 | `:HR:` | 24 | `:LP:` |
| 11 | `:TO:` | 18 | `:R1:` | 25 | `:L1:` |
| 12 | `:VI:` | 19 | `:R2:` | 26 | `:BB:` |
| 13 | `:VO:` | 20 | `:TP:` | 27 | `:CI:` |
| 14 | `:I1:` | 21 | `:HP:` | 28 | `:CO:` |
| 15 | `:O1:` | 22 | `:P1:` | | |

---

## Known limitations

- **Speed.** ISX86 interprets 8080 code, so on a 4.77 MHz 8088 it will be far slower than the DOSBox figures above. I haven't measured it on real PC hardware yet.
- **Ctrl-C handling** (break during console I/O returns to the CLI) is implemented but has not been tested.
- **Ctrl-C while a program is computing** (not doing I/O) is only seen at the program's next ISIS or console call. A program stuck in a tight loop can't be interrupted.
- **Interactive console input** uses DOS line input (fn 0Ah) with DOS's own editing keys, not ISIS line editing. Echo files for line-edited disk input are validated but otherwise ignored.
- **CONSOLE, ATTRIB and WHOCON** are no-ops or minimal implementations, matching ISX.
- **Ten AFTNs**: `:CO:`, `:CI:` and eight files or devices.
- **ISXDIR** doesn't list hidden or system files, has no user areas, and handles up to 1,024 files.

---

## Credits

- **ISX (ISIS-II Interface) 1.4**: Digital Research.
- **ISIS-II, PL/M-80, ASM80, FORTRAN-80, LINK, LOCATE, OBJHEX**: Intel Corporation.
- **`isx.asm`, `objcpm.asm` disassemblies and the ISX utilities**: P112 ISX distribution.
- **IDUMP**: Hector Peraza.
- **CP/M 3 utility sources** used for verification: Digital Research.
- **ISX86 and the MS-DOS ports of OBJCPM, IDUMP, SETEOF and ISXDIR**: Mickey White Lawless.

The original programs remain the property of their respective copyright holders.
