# README

See the [documentation index](docs/README.md) for the component reference,
complete [boot process](docs/boot.md), and [failures and solutions](docs/failures.md).

## Generated files and cleanup

Preview disposable output with `tools\Clean-GeneratedFiles.ps1 -WhatIf`, then
run `tools\Clean-GeneratedFiles.ps1` to remove it. This includes compiler
objects/binaries, CMake build trees, packaged ISOs, experiment VM files, logs,
and verification caches. Rebuild before packaging or running the demos.

Keep new experiment output under `artifacts/`. Downloaded build prerequisites
belong under `.tools/`; the FreeLoader/runtime scripts use
`.tools/winflexbison-2.5.25`. Both directories are ignored by Git, but cleanup
preserves `.tools/` along with supplied WRK/ProjectOZ libraries, toolchains, HALs,
and source manifests. Source `BUILD/` directories contain makefiles and stay.

Historical boot observations remain documented; their generated evidence files
were removed during cleanup. See the [documentation index](docs/README.md).

## Pre-BUILD

> [!CAUTION]
> Please ensure there are **no** space characters in your project path, or you may encounter errors like `fatal error U1077`.

Create necessary directories **before** building WRK and ProjectOZ: `python3 PREBUILD.PY`.


## Build WRK

1. Open `WRK-V1.2/WRK.sln` with Visual Studio 2026.

2. Build solution with pre-defined "x86"(Windows Server 2003 SP1) configuration.

    - or run `tools\Build-WrkX86.cmd` for the equivalent bundled-toolchain nmake build
    - binary files can be found here: `WRK-V1.2/BASE/NTOS/BUILD/EXE`

3. Install the kernel inside a licensed Windows Server 2003 SP1 (x86) guest -
   see `docs/VIRTUALBOX.md`. `tools\New-WrkVirtualBox.ps1` provisions a ready
   VM and a WRK payload ISO; `tools\guest\INSTALL.TXT` has the in-guest steps.

    - matching HAL DLLs (e.g. `HALMACPI.DLL`): `WRK-V1.2/WS03SP1HALS/X86`
    - example `boot.ini`: `WRK-V1.2/WS03SP1HALS/BOOT.INI` (guest `C:\boot.ini` only)

> [!CAUTION]
> Do **not** copy kernel or HAL files into the host's `C:/Windows/system32`,
> and do **not** edit the host's `C:/BOOT.INI`. Those steps apply only inside
> the guest VM.


## BIOS bootstrap lab (does not boot WRK)

A two-stage BIOS bootstrap/chainloader with a buildable floppy image lives
in `bootloader/` - see `docs/BOOTLOADER.md`.

For the real NT-compatible loader path, `tools\Build-WrkFreeLoader.cmd`
builds ReactOS FreeLoader and `tools\New-WrkFreeLoaderIso.ps1` packages a
boot ISO - see `docs/FREELOADER.md` (still needs a licensed installed
Windows Server 2003 SP1 base to actually boot WRK).

The required runtime files and registry/driver configuration, possible
CD-based boot route, and latest VirtualBox verification are documented in
[`dependency.md`](dependency.md). The original ISO boots FreeLoader but
stops before WRK kernel loading because that runtime is absent.

A separate [native Hello World RAM-disk experiment](docs/WRK_HELLO_BOOT.md)
compiles the supporting DLLs/drivers and boots WRK in VirtualBox without an
installed Windows disk. Its setup loader, arbiter registry data and RAM-disk
PnP fixes pass the earlier `0x9A`, `0x69` and `0x19` stops. The latest VirtualBox
test displays **`Hello world from WRK SMSS!`** from the native demo.


## Build ProjectOZ

1. Modify the `wrk` variable to your WRK path.

    - path: `ProjectOZ/makefile`, Line #8

2. Execute `ProjectOZ/BUILD.BAT`.

    - binary files can be found here:`ProjectOZ/runx86`.
