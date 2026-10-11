# WRK native Hello World boot experiment

Historical build/VM results below describe the recorded experiments. Generated
evidence, media, VM files, and build outputs were removed during cleanup; rebuild
and rerun to collect fresh evidence.

**The setup-mode ISO boots FreeLoader, starts the actual WRK kernel, and
displays `Hello world from WRK SMSS!`. The setup loader, arbiter registry data
and RAMDISK PnP repairs pass the earlier license, I/O initialization and pool
header stops.** This
experiment supplies a system root in a RAM-disk ISO so that no Windows
installation on the VM hard disk is needed. It is a small native-program demo,
not a Windows desktop or a general Session Manager replacement.

The original `artifacts/wrk-freeldr/WRK-FreeLoader.iso` remains a separate,
unchanged loader/payload disc. Its verified `Could not load SYSTEM.ALT hive!`
failure precedes WRK loading. See [dependency.md](../dependency.md) for the
original test evidence and dependencies.

## What is built and where it comes from

| Component | Actual source/input used | Result |
|---|---|---|
| WRK x86 kernel | Existing `WRK-V1.2/BASE/NTOS/BUILD/EXE/wrkx86.exe` | Reused without changing WRK sources |
| MP ACPI HAL | Microsoft Server 2003 SP1 `WRK-V1.2/WS03SP1HALS/X86/HALMACPI/HALMACPI.DLL` | Reused; ReactOS HAL is not substituted |
| FreeLoader, rosload and El Torito image | Existing build of sibling `../reactos/_bootldr`, staged in `artifacts/freeldr-build-x86` | Reused |
| `bootvid.dll`, `kdcom.dll` | Sibling `../reactos/drivers/base`; matching source snapshots are also in `_bootldr_ex/drivers/base` | Compiled x86 native modules |
| `ramdisk.sys` | Sibling `../reactos/drivers/storage/class/ramdisk`, with an isolated source override | Compiled x86 native driver |
| `cdfs.sys` | Sibling `../reactos/drivers/filesystems/cdfs` | Compiled x86 native filesystem driver |
| SYSTEM, SOFTWARE, DEFAULT, SAM and SECURITY | [Minimal experiment seed](../hello_world/boot/wrk-hello.inf), plus the arbiter records from `_bootldr_ex/boot/bootdata/hivesys.inf`, processed by `_bootldr_ex/build-host/bin/mkhive.exe` | Fresh binary test hives |
| `c_1252.nls`, `c_437.nls` | `_bootldr_ex/media/nls/src` mappings, processed by its `txt2nls.exe` | Fresh boot codepage tables |
| `l_intl.nls` | `_bootldr_ex/media/nls/l_intl.nls` | Copied language/case table |
| `ntdll.dll`, `smss.exe` | [hello_world](../hello_world/README.md), built with WRK's bundled x86 compiler/assembler/linker | Minimal native startup/syscall DLL and greeting program |

The runtime script currently uses the full sibling ReactOS checkout for all
four runtime modules and their headers/build libraries. The `_bootldr_ex`
snapshot contains BOOTVID, KDCOM, HAL and data-generation sources, but it does
not contain the CDFS or RAMDISK driver source trees. Consequently this build is
not reproducible from `_bootldr_ex` alone. The packager uses the supplied
Microsoft MP HAL because matching filenames and exports do not establish
ReactOS HAL private-layout compatibility with WRK.

`artifacts/wrk-runtime-build-x86` holds the runtime build and logs. Existing
source trees and the original ISO are preserved. The build uses MSVC x86,
CMake/Ninja and the local WinFlexBison package under `.tools`.
Current script defaults include this machine's Visual Studio Build Tools and
CMake paths; another host must provide equivalent tools or adjust those paths.

## Isolated RAMDISK source fixes

[Build-WrkRuntime.ps1](../tools/Build-WrkRuntime.ps1) copies `ramdisk.c` into
`artifacts/wrk-runtime-build-x86/overrides` and changes:

```c
DeviceObject->Flags &= DO_DEVICE_INITIALIZING;
```

to:

```c
DeviceObject->Flags &= ~DO_DEVICE_INITIALIZING;
```

This clears the initialization flag after adding the RAM-disk device. The
original expression retained that flag and discarded the other device flags.
The copy also resolves its relative `fs_rec.h` include to the original absolute
header path.

The later arbiter test exposed a second defect in `RamdiskPnp`: unsupported
requests for a RAM-disk child PDO returned the successful remove-lock status
without completing their IRPs. The runtime builder now completes those PDO
requests and returns their incoming `Irp->IoStatus.Status`. The resource-query
cases also save and return that incoming status before completion. This
follows the [resource-filter request contract](https://learn.microsoft.com/en-us/windows-hardware/drivers/kernel/irp-mn-filter-resource-requirements)
for a parent bus driver to complete the request with its I/O status unchanged.
Both drive-only `StartDevice` branches now complete before returning; their
dedicated query helpers already complete requests and receive no blanket
completion change. Bus forwarding remains unchanged.

A deferred CMake override selects only this copied source; the sibling source
file is unchanged.

provenance.json (`artifacts/wrk-runtime-build-x86/overrides/provenance.json`)
records the original and copied paths, SHA-256 hashes and the changes. The
packager copies it beside the new ISO as `runtime-provenance.json` and includes
the existing WRK and ReactOS license files in the external disc.

## Build and package

From the repository root, with the existing loader and host tools built:

```powershell
.\tools\Build-WrkRuntime.ps1
.\tools\New-WrkHelloHives.ps1
.\hello_world\Build-HelloWorld.ps1
.\tools\New-WrkHelloIso.ps1
```

The runtime builder accepts `-ReactOSRoot` for another full checkout. If the
FreeLoader build is absent, run `tools\Build-WrkFreeLoader.cmd` first. If the
bundle's host tools are absent, build `_bootldr_ex`'s `bootldr_data` target as
described in its [README](../_bootldr_ex/README.md).

The hive builder's default `Ramdisk` mode creates
`artifacts/wrk-hello-hives/{Config,Nls}`. A separate diagnostic mode is available:

```powershell
.\tools\New-WrkHelloHives.ps1 -BootMode Core -OutputDirectory artifacts\wrk-hello-hives-core
```

Both modes include the six complete arbiter AddReg records from the supplied
`hivesys.inf`: the parent key, root/PCI allocation-order resource lists, and
root/PCI reservation aliases with their `PCStandard` resource list. The
generator preserves the source's binary continuation data in `inf/arbiters.inf`
and records both source and generated INF hashes in the hive manifest. WRK's
phase 0 Plug and Play initialization requires this data before boot drivers run.

That mode has no storage services and cannot open NTDLL or SMSS through a
kernel filesystem. The ISO packager uses the default RAM-disk hives. It accepts
`-RuntimeBuildDirectory`, `-LoaderBuildDirectory`, `-HiveDirectory` and
`-OutputDirectory` overrides. Its output must be a new/empty directory beneath
`artifacts`; it refuses to overwrite a populated output directory. By default
it creates `artifacts/wrk-hello-<timestamp>/WRK-HelloWorld.iso`.

## Boot path and registry

The external boot ISO contains the loader and `WRKSYS.ISO`. The inner image
contains `WRK/System32` with the kernel, HAL, boot DLLs, native pair, hives, NLS
and two drivers. The configured loader route loads that image into `LoaderXIPRom` memory and
selects:

```ini
BootType=Windows2003
SystemPath=ramdisk(0)\WRK
Kernel=wrkx86.exe
Hal=halmacpi.dll
```

The generated options include `/SOS /MININT /INRAM /RDEXPORTASCD`, the
`/RDPATH=\WRKSYS.ISO` and image length, and non-PAE execution options. `/MININT`
selects WRK's in-memory, nonpersistent registry initialization. `/INRAM` marks
the WinPE-style memory boot. `/RDEXPORTASCD` asks the RAM-disk driver to expose
the ISO as a CD device for CDFS; after handoff the system root is intended to use
RAMDISK/CDFS rather than a physical IDE/CD-ROM driver stack.

The SYSTEM hive selects control set 1 and maps ANSI 1252, OEM 437 and language
0409 to the supplied NLS files. It includes the driver group list, exactly two
boot-start services (`ramdisk`: type 1, Boot Bus Extender; `cdfs`: type 2, Boot
File System), and empty BootExecute/subsystem/paging-file lists. SAM and
SECURITY are valid empty seed hives, not functioning account databases.

WRK's default initial program is `\SystemRoot\System32\smss.exe`. The custom
NTDLL initializes only the demo executable's imports/startup context. SMSS
prints `Hello world from WRK SMSS!` through `NtDisplayString` and stays alive.
See [native demo limits](../hello_world/README.md).

## VirtualBox verification (2026-10-03)

### Original normal-mode experiment

Completed checks confirm compilation of BOOTVID, KDCOM, RAMDISK and CDFS;
generation of five binary hive files and three NLS files; valid hive header
checksums, clean sequences, root cells and hive-bin chains; actual Select/NLS/
driver-order/service values; and the native demo's PE/syscall checks. Packaging
checks x86/native PE inputs and records all staged file hashes.

The verified new disc is
`artifacts/wrk-hello-20261003-r2/WRK-HelloWorld.iso` (`artifacts/wrk-hello-20261003-r2/WRK-HelloWorld.iso`).
It was booted in the disposable `WRK-HelloWorld-r2` VirtualBox VM with 512 MB,
one processor, BIOS and the supplied MP ACPI HAL.

| Check | Observed result |
|---|---|
| External ISO/El Torito boot catalog and staged loader files | Passed |
| Inner system ISO | All 16 runtime payload files exactly match staging/manifest |
| FreeLoader -> WRK handoff | Verified; WRK displays Version 5.2, Build 3800 at the 30-second capture |
| Later startup | `SYSTEM_LICENSE_VIOLATION`, stop `0x9A (0x4, 0xC0000034, 0, 0)` at the 60-second capture |
| RAMDISK/CDFS kernel initialization | Not established; failure precedes the expected I/O initialization stage |
| Native NTDLL/SMSS and Hello World | Not reached or verified |
| Original kernel/HAL/ISO and new ISO integrity | Pre/post hashes unchanged |
| Final VM state | Powered off |

The specific missing value is `SYSTEM\Setup\SystemPrefix`. WRK's own
[BUGCODES.TXT](../WRK-V1.2/PUBLIC/INTERNAL/BASE/INC/BUGCODES.TXT) describes
subcode 4 as a missing SystemPrefix value. Microsoft's
[0x9A reference](https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/bug-check-0x9a--system-license-violation)
confirms that interpretation; `0xC0000034` is `STATUS_OBJECT_NAME_NOT_FOUND`.

An ordinary binary-hive read confirms that the fresh test hive and staged r2
hive omit SystemPrefix. The supplied ReactOS example SYSTEM does contain it,
but only as a zero-length REG_BINARY placeholder, with SetupType and
SystemSetupInProgress both set to 1. Its seed is
`_bootldr_ex/boot/bootdata/hivesys.inf`; those example setup values are not a
verified installed Server 2003 license/setup state. No valid populated
SystemPrefix was found in the provided inputs. A compatible, valid source
SYSTEM/setup state is needed for ordinary installed-system startup. The
explicit setup-mode experiment below tests a separate kernel initialization
path without inventing licensing data or altering kernel license checks.

Evidence: WRK banner (`artifacts/wrk-hello-20261003-r2/verification/screen-extended-30s.png`),
stop screen (`artifacts/wrk-hello-20261003-r2/verification/screen-extended-60s.png`),
ISO validation (`artifacts/wrk-hello-20261003-r2/iso-validation.log`),
inner file validation (`artifacts/wrk-hello-20261003-r2/inner-validation.json`),
run result (`artifacts/wrk-hello-20261003-r2/verification/result.json`),
post-run hashes (`artifacts/wrk-hello-20261003-r2/verification/hashes-after.json`),
and final VM configuration (`artifacts/wrk-hello-20261003-r2/verification/vm-after.txt`).
The mixed Microsoft/ReactOS runtime remains experimental beyond the observed
kernel startup.

## Explicit NT 5.2 setup-mode experiment

The loader now supports `SetupMode=Text` for a Windows2003 entry booting
`ramdisk(0)` with `/MININT /INRAM`. WRK initializes `ExpInTextModeSetup` from
the setup loader block, not from `/MININT`. The loader supplies the existing
zero-initialized setup block and lets its phase 1 code convert the setup pointer
and ARC source path to virtual addresses.

The copied `arc/setupblk.h` had its flag values reversed relative to WRK:
remote boot must be `0x1` and text-mode setup must be `0x2`. The updated loader
checks both constants and, on i386, checks the `Flags` offset of `0x22c` at
compile time. This matches the supplied WRK source and kernel instructions.

This is a setup-mode kernel experiment with generated hives. It leaves
`SystemPrefix` absent and selects the kernel's existing setup path. Ordinary
installed-system startup still requires compatible installation registry state.
The default loader and packaging modes remain ordinary startup.

Build and run this mode separately:

```powershell
.\tools\Build-WrkSetupLoader.ps1
.\tools\New-WrkHelloHives.ps1 -TextModeSetup -OutputDirectory artifacts\wrk-hello-hives-setup
.\tools\New-WrkHelloIso.ps1 -TextModeSetup `
    -LoaderBuildDirectory artifacts\freeldr-setup-build-x86 `
    -HiveDirectory artifacts\wrk-hello-hives-setup `
    -OutputDirectory artifacts\wrk-hello-setup-new
.\tools\Verify-WrkHelloIso.ps1 -PackageDirectory artifacts\wrk-hello-setup-new
.\tools\Test-WrkHelloVm.ps1 `
    -IsoPath artifacts\wrk-hello-setup-new\WRK-HelloWorld.iso `
    -Name WRK-HelloWorld-setup-new -ObservationSeconds 180 -CaptureCore
```

The isolated build selects this repository's changed `winldr.c` while using the
sibling ReactOS checkout for its other sources. A target-specific include
directory selects the corrected setup header. `provenance.json` records input
and output hashes, and packaging checks the selected loader binaries against
those hashes. The setup hives contain `SetupType=1` and
`SystemSetupInProgress=1`; packaging also checks their SYSTEM hash against the
generation manifest. The VM runner captures intermediate screenshots, pauses
for an optional core dump, and powers the test VM off afterward.

### Verified setup-mode result (2026-10-03)

The rebuilt disc is
`artifacts/wrk-hello-20261003-setup/WRK-HelloWorld.iso` (`artifacts/wrk-hello-20261003-setup/WRK-HelloWorld.iso`),
4,022,272 bytes, SHA-256
`940FB557011CB287C8AB43A325F889C284B09F869838597D50D36329F2ACCF81`.
It was observed for 180 seconds after selection in the fresh CD-only
`WRK-HelloWorld-setup-20261003` VM, with 512 MB RAM and one i386 CPU.

| Check | Observed result |
|---|---|
| Loader build and i386 setup-block ABI assertions | Passed |
| Binary hive setup flags | Both REG_DWORD values are 1; SystemPrefix remains absent |
| External ISO boot catalog and staged files | Passed |
| Inner ISO payload | All 16 files exactly match staging and manifest |
| Actual WRK setup handoff | Core confirms `ExpInTextModeSetup = 1` |
| Previous `0x9A (4, C0000034, 0, 0)` stop | Avoided in this setup-mode boot |
| Current stop | `IO1_INITIALIZATION_FAILED`, `0x69 (0, 0, 0, 0)` |
| Native Hello World | Not reached |
| Final VM state | Powered off; checked ISO/kernel/HAL hashes unchanged |

The screenshot and captured `KiBugCheckData` agree on `0x69`. WRK's
`Phase1InitializationDiscard` calls `ExInitSystemPhase2` before `IoInitSystem`,
then reports this stop when `IoInitSystem` fails. The missing-prefix branch no
longer stops this experiment, but successful storage/filesystem initialization
and native program execution are still unverified. The cause of the I/O
initialization failure was not established by the initial boot observation;
the subsequent source/core investigation below narrows it to arbiter setup.

Evidence: final screen (`artifacts/wrk-hello-20261003-setup/verification/screen-final.png`),
core analysis (`artifacts/wrk-hello-20261003-setup/verification/core-analysis.json`),
run result (`artifacts/wrk-hello-20261003-setup/verification/result.json`),
loader provenance (`artifacts/wrk-hello-20261003-setup/loader-provenance.json`),
binary hive verification (`artifacts/wrk-hello-hives-setup/verification/binary-hive-verification.json`),
inner payload checks (`artifacts/wrk-hello-20261003-setup/inner-validation.json`),
external ISO checks (`artifacts/wrk-hello-20261003-setup/iso-validation.log`),
and final VM configuration (`artifacts/wrk-hello-20261003-setup/verification/vm-after.txt`).

### Trace of IO1_INITIALIZATION_FAILED

The captured kernel contains `IopInitFailCode = 4` at runtime address
`0x805c7334`. Its matching map places the symbol at link address `0x0049f334`;
the loaded kernel base is `0x80528000`. In
[IOINIT.C:620](../WRK-V1.2/BASE/NTOS/IO/IOMGR/IOINIT.C), this marker is assigned
when `IopInitializePlugPlayServices(LoaderBlock, 0)` returns a failing status.
`IoInitSystem` then returns FALSE, and
[INITOS.C:1532](../WRK-V1.2/BASE/NTOS/INIT/INITOS.C) calls
`KeBugCheck(IO1_INITIALIZATION_FAILED)`. This call uses no status parameters,
which explains why the stop screen shows four zeros.

Source and original-kernel disassembly give this path:

```text
Phase1InitializationDiscard
  IoInitSystem
    IopInitializePlugPlayServices(LoaderBlock, 0)
      IopPortInitialize
        ArbInitializeArbiterInstance (root I/O-port arbiter)
          ArbBuildAssignmentOrdering
            ZwOpenKey(...\CurrentControlSet\Control\Arbiters)
```

The root port arbiter has its `Arbs` signature, callback fields, and allocation/
ordering buffer pointers set. Its ordering counts remain zero. The root memory,
DMA, IRQ, and bus-number arbiters are still zeroed. The original phase 0 routine
calls the port initializer first and calls the memory initializer only after
port success. Its shared arbiter code initializes the ordering buffers before
the first registry open. These persisted states place the failure in root-port
assignment-order setup. Cleanup may leave freed pointers in the arbiter;
nonzero pointers here establish progress, not live allocations.

The compiled assignment-order routine first opens
`\Registry\Machine\System\CurrentControlSet\Control\Arbiters`, then
opens `AllocationOrder` and queries the `Root` value. An independent binary
read of the exact packaged SYSTEM hive confirms that the entire `Arbiters`
tree is absent. This is the concrete missing registry dependency on this path.
The exact returned NTSTATUS was not retained in the bugcheck parameters;
`STATUS_OBJECT_NAME_NOT_FOUND` is the expected result of that first missing-key
open, rather than a directly captured status.

The relevant seed definitions already exist in
[_bootldr_ex/boot/bootdata/hivesys.inf:277](../_bootldr_ex/boot/bootdata/hivesys.inf):
`Arbiters\AllocationOrder` contains resource-requirements data for `Root` and
`Pci`, and `Arbiters\ReservedResources` supplies their reservation policy.
The arbiter repair below includes this data in the generated test hive.
Creating an empty `Arbiters` key alone leaves the subsequent allocation-order
lookup unsatisfied. Boot-start driver initialization is a later step
(`IopInitFailCode = 6`); the existing `0x69` stop occurs before that step.

Evidence: I/O failure marker and stack (`artifacts/wrk-hello-20261003-setup/verification/io-init-core-analysis.json`),
original-binary and guest-code trace (`artifacts/wrk-hello-20261003-setup/verification/io-init-trace/io-init-evidence.json`),
arbiter ordering disassembly (`artifacts/wrk-hello-20261003-setup/verification/io-init-trace/05-ArbBuildAssignmentOrdering-required-key.txt`),
loader/PnP state audit (`artifacts/wrk-hello-20261003-setup/verification/loader-pnp-audit.json`),
and binary hive arbiter-key audit (`artifacts/wrk-hello-20261003-setup/verification/hive-arbiters-audit.json`).
The investigation reuses the captured core; no new VM boot or kernel modification
was needed. The core inspector now includes `IopInitFailCode` in its default
symbol reads for future diagnostics.

For a future live debugger session using this same x86 kernel and matching
symbols, break just after the first `ZwOpenKey` returns:

```text
bp nt!ArbBuildAssignmentOrdering+0x9a
g
r eax
dd nt!IopInitFailCode L1
```

The offset comes from the inspected routine at link `0x0058a2a6` and the
instruction after the call at `0x0058a340`. `eax` there holds the actual key-open
NTSTATUS; `IopInitFailCode` is assigned later during failure unwinding. These
breakpoint commands are proposed confirmation steps and were not run in a live
debugger during this investigation.

### Arbiter repair and VirtualBox rerun

[New-WrkHelloHives.ps1](../tools/New-WrkHelloHives.ps1) now extracts the six
complete arbiter records from the existing SYSTEM seed into a separate INF
and includes them when generating either diagnostic or RAM-disk hives.
The original seed and kernel binaries remain unchanged. The repaired
setup-mode disc was produced with the existing setup loader and runtime:

```powershell
.\tools\New-WrkHelloHives.ps1 -TextModeSetup `
  -OutputDirectory artifacts\wrk-hello-hives-setup-arbiters
.\tools\New-WrkHelloIso.ps1 -TextModeSetup `
  -LoaderBuildDirectory artifacts\freeldr-setup-build-x86 `
  -HiveDirectory artifacts\wrk-hello-hives-setup-arbiters `
  -OutputDirectory artifacts\wrk-hello-20261003-setup-arbiters
.\tools\Verify-WrkHelloIso.ps1 `
  -PackageDirectory artifacts\wrk-hello-20261003-setup-arbiters
.\tools\Test-WrkHelloVm.ps1 `
  -IsoPath artifacts\wrk-hello-20261003-setup-arbiters\WRK-HelloWorld.iso `
  -Name WRK-HelloWorld-arbiters-20261003 -ObservationSeconds 180 -CaptureCore
```

The new ISO (`artifacts/wrk-hello-20261003-setup-arbiters/WRK-HelloWorld.iso`)
is 4,022,272 bytes, SHA-256
`FA5C24D9728A1CD025D01F833E88EF37AA8C61604CC616443EAEDB94C95E220D`.
Independent binary hive checks confirm that the actual resource-list data
matches the supplied INF bytes: `AllocationOrder\Root` has 36 descriptors,
`Pci` has 17, and `ReservedResources\PCStandard` has 7. Both reservation
aliases are null-terminated REG_SZ values. The types, list sizes, record
boundaries, hive headers and setup flags pass validation. External ISO boot
catalog checks and all 16 inner payload comparisons also pass.

The fresh CD-only VirtualBox VM ran for 180 seconds with the same 512 MB,
one-CPU configuration. Captured memory confirms successful Plug and Play
phase 0: all five root arbiters have their signatures and populated ordering
lists, the root/HAL device nodes exist, and `IopLoaderBlock` is assigned
after the phase 0 call. The boot-driver-loaded flag is 1; its initialized
flag remains 0. The former `IopInitFailCode = 4` stop is therefore resolved
in this boot. The native greeting remains unverified.

The new stop is `BAD_POOL_HEADER`,
`0x19 (0x20, 0x806A68FF, 0x806A6F1F, 0xE8C475FF)`.
The stack places it in a later resource-assignment worker:

```text
PipDeviceActionWorker -> PiProcessReenumeration -> PipProcessDevNodeTree
  IopProcessAssignResources -> IopAssignResourcesToDevices
    IopAllocateResources -> IopGetResourceRequirementsForAssignTable
      IopQueryDeviceResources -> ExFreePoolWithTag -> KeBugCheckEx
```

`IopQueryDeviceResources` attempts to free `0x806A6907`, an address inside
kernel code, after its resource-filter call. The pool check consequently
interprets code bytes as a pool header. This is a separate resource-query/
filtering failure; successful driver initialization and filesystem mounting
have not been established. No kernel patch was applied for this new stop.
The VM finished powered off, with checked original kernel/HAL/ISO and new
ISO hashes unchanged.

Evidence: binary hive validation (`artifacts/wrk-hello-hives-setup-arbiters/verification/arbiter-hive-validation.json`),
final screen (`artifacts/wrk-hello-20261003-setup-arbiters/verification/screen-final.png`),
captured core and stack (`artifacts/wrk-hello-20261003-setup-arbiters/verification/core-analysis.json`),
PnP state audit (`artifacts/wrk-hello-20261003-setup-arbiters/verification/loader-pnp-audit.json`),
run result (`artifacts/wrk-hello-20261003-setup-arbiters/verification/result.json`),
inner ISO checks (`artifacts/wrk-hello-20261003-setup-arbiters/inner-validation.json`),
and external ISO checks (`artifacts/wrk-hello-20261003-setup-arbiters/iso-validation.log`).

### RAMDISK completion repair and verified native greeting

The first arbiter rerun's captured PDO belongs to `\Driver\ramdisk`.
Its outstanding `FILTER_RESOURCE_REQUIREMENTS` request has the incoming
`STATUS_NOT_SUPPORTED`, but the driver's default path returns the successful
remove-lock result without completing it. The kernel consequently consumes
an uninitialized result pointer. A second unsupported legacy-bus-information
request remains outstanding on the same PDO. This identifies the driver
completion defect rather than another missing arbiter registry value.
See the failing-device audit (`artifacts/wrk-hello-20261003-setup-arbiters/verification/failing-device-audit.json`)
and original driver source (`artifacts/wrk-hello-20261003-setup-arbiters/verification/ramdisk-before-pnp-fix.c`).

The isolated runtime fixes described above were rebuilt and packaged with
the validated arbiter hives and existing setup loader:

```powershell
.\tools\Build-WrkRuntime.ps1 -Targets ramdisk
.\tools\New-WrkHelloIso.ps1 -TextModeSetup `
  -LoaderBuildDirectory artifacts\freeldr-setup-build-x86 `
  -HiveDirectory artifacts\wrk-hello-hives-setup-arbiters `
  -OutputDirectory artifacts\wrk-hello-20261003-setup-pnp
.\tools\Verify-WrkHelloIso.ps1 `
  -PackageDirectory artifacts\wrk-hello-20261003-setup-pnp
.\tools\Test-WrkHelloVm.ps1 `
  -IsoPath artifacts\wrk-hello-20261003-setup-pnp\WRK-HelloWorld.iso `
  -Name WRK-HelloWorld-pnp-20261003 -ObservationSeconds 180 -CaptureCore
```

The successful ISO (`artifacts/wrk-hello-20261003-setup-pnp/WRK-HelloWorld.iso`)
is 4,022,272 bytes, SHA-256
`1FC0F6BCC3E1020039ED184A79C93DC8F05952A4B8BE6A52235465F9EB7CFC65`.
Its staged RAMDISK driver has SHA-256
`76E287CF108480F7D68D5853292FBD0416D510CB45A575207A0541556C0FB384`.
The build, source/provenance checks, external boot catalog, and all 16 inner
payload comparisons pass.

| Check | Observed result |
|---|---|
| Native greeting | `Hello world from WRK SMSS!` visible at 70 seconds through final capture |
| SMSS process | PID 120; image base `0x00400000` |
| `SmssDisplayStatus` | `0x00000000`, successful `NtDisplayString`; initial value was `0x103` |
| SMSS and NTDLL execution identity | Executable code matches staging; native imports are bound |
| WRK runtime identity | Loaded-module entry and captured accessor instructions confirm base `0x80528000` |
| Bugcheck state | Five `KiBugCheckData` DWORDs remain zero; CPU is in `KiIdleLoop` |
| I/O failure marker | `IopInitFailCode = 0` |
| Previous stops | No `0x9A`, `0x69` or `0x19` stop in this run |
| Final VM state | Powered off |
| Original source/payload integrity | Eight baseline files match their recorded SHA-256 hashes |

After initialization the kernel has discarded header/initialization pages,
so the generic core inspector cannot identify it by its export name alone.
The loaded-module entry and original instruction bytes independently establish
the base used for the symbol reads. The native audit walks the active process
list and uses SMSS's own page tables (`CR3 = 0x1FDC7000`) to read its code,
bound NTDLL imports and successful display status. This corroborates native
execution beyond the screenshot. The small demo keeps SMSS alive and sleeping;
this test does not establish general Windows desktop or filesystem behavior.

Evidence: final greeting screen (`artifacts/wrk-hello-20261003-setup-pnp/verification/screen-final.png`),
native execution audit (`artifacts/wrk-hello-20261003-setup-pnp/verification/native-smss-audit.json`),
kernel/core analysis (`artifacts/wrk-hello-20261003-setup-pnp/verification/core-analysis.json`),
PnP state (`artifacts/wrk-hello-20261003-setup-pnp/verification/loader-pnp-audit.json`),
run result (`artifacts/wrk-hello-20261003-setup-pnp/verification/result.json`),
runtime provenance (`artifacts/wrk-hello-20261003-setup-pnp/runtime-provenance.json`),
source integrity (`artifacts/wrk-hello-20261003-setup-pnp/verification/source-integrity.json`),
inner payload checks (`artifacts/wrk-hello-20261003-setup-pnp/inner-validation.json`),
and external ISO checks (`artifacts/wrk-hello-20261003-setup-pnp/iso-validation.log`).
