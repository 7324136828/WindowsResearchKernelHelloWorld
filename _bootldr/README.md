# Bootloader sources and WRK boot files

This directory contains the canonical FreeLoader sources and its boot runtime
library from this ReactOS checkout:

- `armllb/`: legacy ARM first-stage loader sources (no active CMake target).
- `bootdata/`: FreeLoader configurations for ReactOS boot media and PC-98.
- `freeldr/bootsect/`: BIOS boot sectors and first-stage assembly.
- `freeldr/freeldr/`: FreeLoader, the `rosload.exe` second stage, NT loading,
  filesystem readers, firmware support, and boot configuration handling.
- `freeldr/install/` and `freeldr/fdebug/`: existing installation and debugging
  utilities.
- `rtl/`: the boot runtime library.
- `wrk/freeldr.ini`: an example configuration for an installed NT 5.2 system
  using a Windows Research Kernel image.

Build this code through the repository root. This subtree is not a standalone
project: shared SDK headers, generated headers, runtime and configuration
libraries, HAL support, NT kernel helper sources, and build tools remain in
`sdk/`, `hal/`, `ntoskrnl/`, and the repository build infrastructure. Copying
`_bootldr/` alone into a WRK tree does not supply those dependencies.

## Build and collect the loader

Open the ReactOS Build Environment (RosBE) for the kernel's architecture, then
run these commands from the repository root. For an initial 32-bit BIOS test,
use the i386 environment:

```bat
configure.cmd
cmake --build output-MinGW-i386 --target wrkboot
```

Replace `output-MinGW-i386` with the build directory actually selected by
`configure.cmd`. An appropriately configured supported Visual Studio developer
command prompt can also be used; see the repository [build instructions](../README.md).
The bootloader architecture must match the WRK kernel and installed system.

The `wrkboot` target collects these files beneath
`<build-directory>/_bootldr/wrk/`:

```text
freeldr.sys
rosload.exe
freeldr.ini
bootsect/dosmbr.bin
bootsect/fat.bin
bootsect/fat32.bin
bootsect/ntfs.bin
```

`freeldr.sys` requires the current second-stage `rosload.exe`. Keep
`rosload.exe` beside it on the boot volume; the loader also checks
`loader\rosload.exe`. Keep `freeldr.ini` in the FreeLoader boot path.

Collecting files does not install a boot sector or make a disk bootable. The
boot medium needs a BIOS boot mechanism that loads `freeldr.sys`; the supplied
boot-sector binaries are inputs for a suitable installer or image-building
workflow. They contain filesystem-specific code and require the correct disk
and filesystem metadata. Use a disposable VM disk or disk image to validate
that integration before deploying it to a working installation.

## Configure an installed system for WRK

The sample selects `BootType=Windows2003`, which uses the source's NT 5.2 loader
path. It points at `multi(0)disk(0)rdisk(0)partition(1)\WINDOWS`: the first BIOS
disk's first partition, with an installed system under `\WINDOWS`. Edit
`SystemPath` for the actual disk, partition, and system directory; ARC disk
indices start at zero and partition indices at one.

Copy your compatible WRK kernel image to the installed system's
`WINDOWS\System32\wrk.exe`, or change `Kernel=` to its actual filename.
`wrk.exe` is an illustrative name, not a required WRK build output name.
`Hal=hal.dll` selects the default HAL filename; use the installed system's HAL
that matches the kernel architecture, build, and machine. The loader preserves
the imported module names `ntoskrnl.exe` and `hal.dll` even when different files
are selected. `/KERNEL=` and `/HAL=` in `Options=` override the separate INI
settings.

An installed compatible NT environment is required. The loader reads the
SYSTEM registry hive, its boot-start driver configuration and NLS data, and
loads the kernel's required DLLs, including the matching debugger transport
and boot video components when referenced. A bare WRK executable plus a HAL is
not enough to boot a Windows system. Preserve a working boot route to the
original installation while testing.

The sample enables kernel debugging on COM1 at 115200 baud. Connect the VM or
machine's serial port to your kernel debugger, or remove the debug options if
they are not needed. Its `/NOPAE /NOEXECUTE=ALWAYSOFF` options are an initial
i386 non-PAE configuration: the current source marks PAE handling as
unimplemented and leaves PAE kernel selection and CPU checks unfinished.
`/3GB` is also marked unimplemented. Use a kernel built for the selected
configuration.

These files provide the current code and a starting configuration. They do
not establish that a particular WRK build boots successfully. Validate the
kernel handoff and installed system in a VM. The presence of UEFI sources does
not establish UEFI support for WRK.

## NT 5.2 setup-mode RAM-disk experiment

The WRK workspace adds an explicit `SetupMode=Text` entry setting to the normal
Windows2003 loader route. It requires `SystemPath=ramdisk(0)\...` and
`/MININT /INRAM`; other combinations are rejected. The loader supplies its
zero-initialized setup block with the NT 5.2 text-mode flag, `0x2`, and uses the
existing setup-block virtual-address conversion before kernel entry. Compile-time
checks verify the flag values and the i386 `Flags` offset, `0x22c`.

This selects WRK's setup initialization path for generated experimental hives.
It does not create installed-system `SystemPrefix` data. Entries without this
setting continue to use normal installed-system initialization.

Build with [Build-WrkSetupLoader.ps1](../tools/Build-WrkSetupLoader.ps1), which
uses this workspace's changed loader source and setup header in an isolated
build. See [the experiment guide](../docs/WRK_HELLO_BOOT.md) for hive generation,
packaging, and VirtualBox results.

## Source and license

This is ReactOS bootloader code, retaining its existing source notices and
licenses. FreeLoader files marked GPL-2.0-or-later remain under those terms;
individual file notices apply. See [COPYING](../COPYING). No Microsoft WRK
kernel sources or Windows system binaries are supplied here.
