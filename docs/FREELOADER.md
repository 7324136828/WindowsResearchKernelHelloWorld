# FreeLoader-based WRK packaging (VirtualBox)

Historical build/VM results below describe the recorded experiments. Generated
evidence, media, VM files, and build outputs were removed during cleanup; rebuild
and rerun to collect fresh evidence.

This packages the **real** ReactOS FreeLoader build against the user's
ReactOS checkout into a BIOS boot ISO, plus the frozen WRK kernel payload.
It is different from the toy `bootloader/` BIOS lab: FreeLoader is a real
NT-compatible loader (reads `freeldr.ini`, loads the SYSTEM hive, sets up
the NT boot environment) - not a chainloader.

See [dependency.md](../dependency.md) for the source-backed runtime
inventory, the distinction between an early kernel greeting and continued
Windows startup, and a possible CD-based system root without a Windows
installation on the hard disk. That alternative is not implemented in
the original ISO described here. The separate
[native Hello World experiment](WRK_HELLO_BOOT.md) now boots WRK from a
RAM-disk system root and reaches native SMSS. See [boot.md](boot.md) for
the complete current sequence and [failures.md](failures.md) for stop diagnoses.

## Toolchain provenance

- FreeLoader: built by **MSVC 19.51** (VS2026 BuildTools, vcvarsall x86)
  via CMake/Ninja from `..\reactos` (`_bootldr` tree).
- WRK kernel: built earlier by **bundled MSVC 13.10** under `TOOLS\X86`
  (`tools\Build-WrkX86.cmd`) - reused frozen, not rebuilt.
- WinFlexBison: approved portable `win_flex_bison-2.5.25` under
  `.tools` (bison 3.8.2 / flex 2.6.4; `bison.exe`/`flex.exe`
  aliases inside that dir only).
- The full `..\reactos` dependency tree is required - `_bootldr` does not
  build standalone.

## Rebuild / repackage commands

Build (or dry-run check) the loader:

```bat
tools\Build-WrkFreeLoader.cmd              :: uses sibling ..\reactos
tools\Build-WrkFreeLoader.cmd /N           :: print-only dry run, validates cache
tools\Build-WrkFreeLoader.cmd C:\other\reactos
```

Package a fresh build (default output `artifacts\wrk-freeldr` is already
populated by the verified build on this machine - the packager refuses a
nonempty output directory, so always pick a NEW output dir):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\zachn\Documents\GitHub2\WRK\tools\New-WrkFreeLoaderIso.ps1 -OutputDirectory C:\Users\zachn\Documents\GitHub2\WRK\artifacts\wrk-freeldr-p2 -SystemPath "multi(0)disk(0)rdisk(0)partition(2)\WINDOWS"
```

The packager refuses to overwrite an existing ISO or a nonempty output
directory; it fails cleanly on missing build outputs or an invalid
`-SystemPath` (must be `multi(0)disk(0)rdisk(N)partition(N>=1)\path`).

## Outputs

- Build tree: `artifacts\freeldr-build-x86\` (wrkboot stage under
  `_bootldr\wrk\`, `isoboot.bin` under `_bootldr\freeldr\bootsect\`,
  native `host-tools\bin\mkisofs.exe`)
- ISO: `artifacts\wrk-freeldr\WRK-FreeLoader.iso` + `iso-root\` staging
  (loader/{freeldr.sys,rosload.exe,isoboot.bin,freeldr.ini}, root
  freeldr.ini/README.TXT/COPYING-GPL.TXT, payload/{WRKX86.EXE,WRKX86.PDB,
  HALMACPI.DLL,LICENSE.TXT,INSTALL.TXT})
- Note: `payload\INSTALL.TXT` is the preserved guest guide written for the
  earlier *data-only* `WRK-X86.iso`; its "not bootable" line describes that
  old data CD, **not** this genuinely bootable FreeLoader disc. The
  install/copy steps it describes still apply to this disc's `payload\`
  contents once a base OS exists.

## Boot the ISO in the lab VM

Prepared VM: `WRK-FreeLoader-x86` (BIOS/PIIX3/IDE, ACPI+APIC+I/O APIC on,
PAE off, 512 MB, no NIC/audio/USB; blank 20 GB VDI on IDE0; ISO on IDE1;
boot order DVD then disk). Headless start:

```powershell
& "$env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe" startvm WRK-FreeLoader-x86 --type headless
```

The FreeLoader menu appears (timeout 30 s). **What success looks like:**
the menu itself, then - because the VDI is blank - an error that the
SystemPath's SYSTEM hive/installation is missing. FreeLoader reads the
SYSTEM hive **before** loading the kernel, so that expected error means
the disc works; it does **not** mean WRK loaded.

## Observed verification (this machine, before the host reboot)

The prepared VM was booted headless from this ISO under VirtualBox NEM
(Snail) mode. Screenshots retained under `artifacts\logs\`:

- `shot-12.png` / `shot-28.png`: the real FreeLoader menu, showing both
  ini entries ("WRK 1.2 x86 (requires Windows Server 2003 SP1)" and
  "Windows Server 2003 SP1 (original kernel)") and the auto-boot
  countdown.
- `shot-44.png` / `shot-60.png` / `freeldr-error2.png`: the exact observed
  error after selecting WRK on the blank disk:
  **`Could not load SYSTEM.ALT hive!`** (FreeLoader `wlregistry.c`,
  raised while loading the SYSTEM hive - i.e. before any kernel load).
- `shot-75.png` / `shot-90.png`: Enter dismisses the box and returns to
  the menu.
- `freeldr-com1.txt`: FreeLoader debug output on COM1
  (`partition.c:216 fixme: DiskGetPartitionEntry() unimplemented for RAW`),
  proving real loader execution from this ISO.
- `freeldr-vm-vbox.log`: VBox.log of the run (NEM backend evidence).

The VM is registered and **powered off**. None of this proves WRK boots -
the kernel was never reached.

## Fresh verification (2026-10-03)

The supplied `artifacts\wrk-freeldr\WRK-FreeLoader.iso` was booted again in
the existing `WRK-FreeLoader-x86` VM with VirtualBox 7.2.20r175154. The
FreeLoader menu appeared, and selecting WRK reproduced
**`Could not load SYSTEM.ALT hive!`** before kernel loading. Static ISO
checks passed for ISO9660, the El Torito catalog, the boot image, and all
staged files. WRK kernel entry and a WRK Hello World were **not reached**.

The VM was powered off after the test. SHA-256 checks before/after matched
for the kernel, PDB, HAL, FreeLoader, rosload, boot image, ISO and blank VDI.
Evidence is retained in
`artifacts/checks/wrk-freeldr-current-20261003-033907/` (`artifacts/checks/wrk-freeldr-current-20261003-033907/`),
including screenshots, serial output, VBox.log and integrity results.

## To actually boot WRK using an installed Windows disk

1. Obtain licensed 32-bit **Windows Server 2003 SP1** media (or a
   compatible preinstalled disk image). WRK is licensed for eligible
   academic/noncommercial users only; do not publicly redistribute this
   ISO or WRK source/binaries. The FreeLoader parts are GPL
   (`COPYING-GPL.TXT` on the disc).
2. For an existing installed VDI: the VM must be **powered off** first.
   Make a standalone **clone** of the disk (a snapshot alone is not a
   separate medium and cannot be attached as an independent disk), then
   attach only that clone - never the original:
   ```powershell
   & "$env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe" clonemedium disk "C:\full\path\to\your-server2003.vdi" "C:\Users\zachn\Documents\GitHub2\WRK\artifacts\VirtualBox\server2003-clone.vdi" --format VDI
   & "$env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe" storageattach WRK-FreeLoader-x86 --storagectl IDE --port 0 --device 0 --type hdd --medium "C:\Users\zachn\Documents\GitHub2\WRK\artifacts\VirtualBox\server2003-clone.vdi"
   ```
3. Inside the guest: copy `WRKX86.EXE` + `HALMACPI.DLL` from the disc's
   `payload\` to the installed `%SystemRoot%\System32` (see
   `payload\INSTALL.TXT`); FreeLoader's freeldr.ini replaces the NTLDR
   path - keep the stock `Windows2003` menu entry as the recovery route.
4. Stock recovery without this disc: eject the FreeLoader CD
   (`storageattach ... --type dvddrive --medium emptydrive` while powered
   off) and boot the untouched original Windows disk and its original
   `boot.ini`.
5. WRK needs the installed SYSTEM hive, NLS files, boot drivers,
   BOOTVID/KDCOM and `smss.exe` from the base OS - none are on this disc.

An installed disk is the practical baseline described here. FreeLoader
also supports a system directory on the boot CD, but such a directory
still needs compatible runtime files and registry data; the current
packager does not create it. See [dependency.md](../dependency.md).

The original loader/payload ISO has not reached WRK in the recorded blank-disk
tests. The separate setup-mode RAM-disk image has verified native greeting
execution; see [its evidence](WRK_HELLO_BOOT.md#ramdisk-completion-repair-and-verified-native-greeting).
No performance measurement is implied by either test.
