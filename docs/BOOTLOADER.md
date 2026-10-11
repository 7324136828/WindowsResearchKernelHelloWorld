# WRK BIOS bootstrap / chainloader

Historical build/VM results below describe the recorded experiments. Generated
evidence, media, VM files, and build outputs were removed during cleanup; rebuild
and rerun to collect fresh evidence.

A small educational two-stage x86 BIOS bootstrap with a buildable floppy
image. **It is not an NTLDR replacement and it does not boot WRK.** It can
hand off to the MBR of the first BIOS hard disk (drive 80h) - useful only
once a real Windows installation exists on that disk.

## Build

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File bootloader\Build-Bootloader.ps1
```

Optional: `-NasmPath <path-to-nasm.exe>`, `-OutputDirectory <fresh-dir>`
(default `artifacts\bootloader`, must not already contain outputs).
Requires NASM (found on this host at `C:\Strawberry\c\bin\nasm.exe`).

Outputs (all raw binaries, built with `nasm -f bin`):

| File | Size | Contents |
|---|---|---|
| `stage1.bin` | 512 B | boot sector, 55AA signature, 'WRK1' marker at bytes 5-8 |
| `stage2.bin` | 4096 B | 8 sectors, 'WRK2' magic at bytes 2-5 |
| `stage1.lst` / `stage2.lst` | - | NASM listings |
| `bootloader.img` | 1474560 B | 1.44 MB RAW floppy image: stage1 at sector 0, stage2 at sectors 1-8, rest zero |

The image has a fixed sector layout; it is not a FAT filesystem and not
an OS.

## Real-mode memory layout

| Address | Use |
|---|---|
| `0000:7C00` | BIOS loads stage1 here; stack top (grows downward); chainload target buffer |
| `0000:8000` | stage2 loaded here (sectors 2-9 of track 0) |

stage1 reads 8 sectors via INT13 AH=02 (CHS 0/0/2-9 - the remainder of a
1.44 MB floppy's first 18-sector track), verifies 'WRK2', and jumps to
stage2. stage2 prints a banner, shows the boot drive, and offers:
`C` chainload first hard disk, `R` INT19 BIOS restart, `H` halt.

## Chainloading

`C` reads sector 0 of drive 80h into `0000:7C00` (INT13 AH=42 with an LBA
disk-address packet when the BIOS reports EDD extensions, else CHS
AH=02), requires the 55AA signature, refuses a copy of our own 'WRK1'
sector, and far-jumps to it with DL=80h. It chainloads the whole MBR -
no partition/VBR selection, no drive remapping beyond the first hard
disk, no disk writes anywhere.

## Why this cannot boot WRK

WRK's kernel entry (`BASE\NTOS\KE\I386\NEWSYSBG.ASM`) expects a prepared
NT environment: paging on, GDT/IDT/PCR/TSS set up, a kernel stack, and a
`LOADER_PARAMETER_BLOCK` (`PUBLIC\INTERNAL\BASE\INC\ARC.H`) carrying the
memory descriptor list, load-order/boot-driver lists, registry base, and
NLS data - produced by an NT-compatible loader, such as Windows NTLDR or
the separate FreeLoader path. `INIT\INITOS.C` dereferences that block
immediately; later startup needs a native `smss.exe` and its runtime.
The built `wrkx86.exe` also imports `HAL.dll`, `BOOTVID.dll`, and `KDCOM.dll`.
The installed-system route uses compatible Server 2003 SP1 components;
the [native RAM-disk experiment](WRK_HELLO_BOOT.md) uses the supplied
Microsoft HAL, compiled ReactOS BOOTVID/KDCOM, and a minimal native demo.
A 512-byte BIOS sector cannot provide the required NT loader environment,
so this bootstrap deliberately does not try. See [boot.md](boot.md) and
[components.md](components.md) for the actual kernel boot path.

## Lab usage

The prepared VirtualBox lab VM `WRK-Bootloader-Lab` (floppy boot, no
disk) can run this image headless; `controlvm ... keyboardputscancode`
drives the menu for tests. See `artifacts\checks\` for the retained test
script, screenshots, and logs. The existing `WRK-Server2003-SP1-x86` VM
and its payload are untouched.
