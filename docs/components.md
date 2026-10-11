# Windows Research Kernel component map

This inventory describes the **current WRK 1.2 checkout and its x86 boot
experiments**, inspected on 2026-10-03. It covers every NTOS build unit, the
prebuilt code used in the kernel link, external boot/runtime modules, boot data,
and repository tooling. The routines below are major entry points or examples,
not a complete API reference. Follow [boot.md](boot.md) for execution order and
[failures.md](failures.md) for observed failures and repairs.

WRK is the core NT kernel, not a complete Windows distribution. Its supplied
[README](../WRK-V1.2/README.TXT) identifies x86 Windows Server 2003 SP1 and AMD64
Windows XP x64 Professional as targets; it explicitly excludes Windows XP x86.
The current verified experiment is **x86, BIOS, non-PAE**, using Microsoft's
Server 2003 SP1 multiprocessor ACPI HAL. AMD64 sources and alternative loader/HAL
targets are present, but this experiment does not establish their execution.

## Current assembled system

The latest recorded experiment was
`artifacts/wrk-hello-20261003-setup-pnp/` (`artifacts/wrk-hello-20261003-setup-pnp/`).
Its manifest (`artifacts/wrk-hello-20261003-setup-pnp/manifest.json`) records the
exact source paths and hashes of the loader and all **16 system-root payload
files**. The final screen (`artifacts/wrk-hello-20261003-setup-pnp/verification/screen-final.png`)
shows `Hello world from WRK SMSS!`; its
verification result (`artifacts/wrk-hello-20261003-setup-pnp/verification/result.json`)
and native-process audit (`artifacts/wrk-hello-20261003-setup-pnp/verification/native-smss-audit.json`)
support the kernel/native-process execution claim. This verifies the narrow
greeting path, not a desktop, a production Windows installation, or general
driver compatibility.

Paths under `artifacts/` identify historical generated evidence. Cleanup
removed those outputs; rebuild and rerun the experiment to collect new evidence.

| Component | Current selection and purpose | Provenance |
|---|---|---|
| `wrkx86.exe` | NTOS kernel; provides scheduling, memory, objects, registry, security and I/O services | Built from included WRK sources plus supplied prebuilt libraries; reused unchanged in this experiment |
| `halmacpi.dll`, loaded as `hal.dll` | Multiprocessor ACPI/APIC hardware abstraction | Supplied Microsoft Server 2003 SP1 binary, not the ReactOS HAL |
| `bootvid.dll` | Early VGA graphics/text operations | Built ReactOS compatibility module |
| `kdcom.dll` | Serial kernel-debugger packet transport | Built ReactOS compatibility module |
| `ramdisk.sys` | Exposes the loader-preserved inner ISO as a kernel device | Built from sibling ReactOS source with an isolated RAMDISK override |
| `cdfs.sys` | Mounts/reads the ISO filesystem after kernel handoff | Built from sibling ReactOS source |
| `ntdll.dll` | Minimal Native API syscalls and initial user APC/import bootstrap | Local `hello_world/ntdll` implementation |
| `smss.exe` | Initial native process; prints greeting and remains alive | Local `hello_world/smss` demo; does not implement Windows Session Manager |
| Five registry hives | SYSTEM, SOFTWARE, DEFAULT, SAM, SECURITY | Generated experiment data; see the data inventory below |
| Three NLS files | `c_1252.nls`, `c_437.nls`, `l_intl.nls` | Generated/copied ReactOS data selected by the experiment hive |

The external ISO also contains `freeldr.sys`, `rosload.exe`, `isoboot.bin`,
`freeldr.ini`, and the inner `WRKSYS.ISO`. The actual payload selections are
defined by [New-WrkHelloIso.ps1](../tools/New-WrkHelloIso.ps1), with provenance
checks for its optional explicit text-mode setup route.

The original `wrk-freeldr` ISO (`artifacts/wrk-freeldr/`) is a different
loader/payload disc. It points at an installed-disk system root and its attached
blank disk has no SYSTEM hive. It reaches FreeLoader, then fails before kernel
loading. The existence of its kernel/HAL payload does not make it the assembled
system above. See [dependency.md](../dependency.md).

## Components compiled into NTOS

These are **parts of one kernel image**, not separately deployed DLLs. The
canonical [NTOS makefile](../WRK-V1.2/BASE/NTOS/MAKEFILE) builds the units listed
below, and the [final link makefile](../WRK-V1.2/BASE/NTOS/BUILD/MAKEFILE) combines
their libraries with supplied code. `Nt*` names denote Native API system
services; the other prefixes help locate subsystem routines, but do not imply
that every routine is exported or callable from user mode.

| Build unit | Major responsibility | Important routines and source examples |
|---|---|---|
| `init` | Coordinates phase 0/phase 1 startup, validates the loader block, initializes subsystems and creates the first native process | `ExpInitializeExecutive`, `Phase1Initialization`, `Phase1InitializationDiscard` in [INITOS.C](../WRK-V1.2/BASE/NTOS/INIT/INITOS.C) |
| `ke` | CPU startup, thread dispatch/scheduling, interrupts/traps, APCs, DPCs, timers, dispatcher synchronization and bugchecks | `KiSystemStartup` in [NEWSYSBG.ASM](../WRK-V1.2/BASE/NTOS/KE/I386/NEWSYSBG.ASM); `KeInitSystem` in [KIINIT.C](../WRK-V1.2/BASE/NTOS/KE/KIINIT.C); `KeInitializeApc` in [APCOBJ.C](../WRK-V1.2/BASE/NTOS/KE/APCOBJ.C); `KeInsertQueueDpc` in [DPCOBJ.C](../WRK-V1.2/BASE/NTOS/KE/DPCOBJ.C); `KeBugCheckEx` in [BUGCHECK.C](../WRK-V1.2/BASE/NTOS/KE/BUGCHECK.C) |
| `ex` | Executive services: pool allocation, worker/resource synchronization, handles, time and system information | `ExInitSystem` in [EXINIT.C](../WRK-V1.2/BASE/NTOS/EX/EXINIT.C); `ExAllocatePoolWithTag` in [POOL.C](../WRK-V1.2/BASE/NTOS/EX/POOL.C); `ExInitializeResourceLite` in [RESOURCE.C](../WRK-V1.2/BASE/NTOS/EX/RESOURCE.C) |
| `mm` | Virtual/physical memory, page tables, faults, working sets, sections, paging and executable mappings | `MmInitSystem` in [MMINIT.C](../WRK-V1.2/BASE/NTOS/MM/MMINIT.C); `NtAllocateVirtualMemory` in [ALLOCVM.C](../WRK-V1.2/BASE/NTOS/MM/ALLOCVM.C); `NtCreateSection` in [CREASECT.C](../WRK-V1.2/BASE/NTOS/MM/CREASECT.C); `MmMapViewOfSection` in [MAPVIEW.C](../WRK-V1.2/BASE/NTOS/MM/MAPVIEW.C) |
| `ps` | Process/thread creation and lifetime, system DLL mapping, initial process support | `PsInitSystem` and `PspInitializeSystemDll` in [PSINIT.C](../WRK-V1.2/BASE/NTOS/PS/PSINIT.C); `NtCreateProcessEx`, `NtCreateThread` in [CREATE.C](../WRK-V1.2/BASE/NTOS/PS/CREATE.C); user trampoline lookup in [KULOOKUP.C](../WRK-V1.2/BASE/NTOS/PS/KULOOKUP.C) |
| `ob` | Object types, object namespace, handles, reference counting and object lifetime | `ObInitSystem` in [OBINIT.C](../WRK-V1.2/BASE/NTOS/OB/OBINIT.C); `ObInsertObject` in [OBINSERT.C](../WRK-V1.2/BASE/NTOS/OB/OBINSERT.C); `ObReferenceObjectByHandle` in [OBREF.C](../WRK-V1.2/BASE/NTOS/OB/OBREF.C) |
| `se` | Security reference monitor: tokens, privileges, access checks, auditing and security descriptors | `SeInitSystem` in [SEINIT.C](../WRK-V1.2/BASE/NTOS/SE/SEINIT.C); `SeAccessCheck` in [ACCESSCK.C](../WRK-V1.2/BASE/NTOS/SE/ACCESSCK.C); token support in [TOKEN.C](../WRK-V1.2/BASE/NTOS/SE/TOKEN.C) |
| `config` | Registry hive/cell implementation, registry namespace and Native API operations | `CmInitSystem1`, `CmpInitializeSystemHive`, `CmpInitializeHiveList` in [CMSYSINI.C](../WRK-V1.2/BASE/NTOS/CONFIG/CMSYSINI.C); `NtCreateKey`, `NtSetValueKey` in [NTAPI.C](../WRK-V1.2/BASE/NTOS/CONFIG/NTAPI.C) |
| `io/iomgr` | I/O manager: file/device/driver objects, IRP dispatch and completion, boot-driver integration and file services | `IoInitSystem` in [IOINIT.C](../WRK-V1.2/BASE/NTOS/IO/IOMGR/IOINIT.C); `IoCreateDevice`, `IofCallDriver`, `IofCompleteRequest` in [IOSUBS.C](../WRK-V1.2/BASE/NTOS/IO/IOMGR/IOSUBS.C); `NtCreateFile` in [CREATE.C](../WRK-V1.2/BASE/NTOS/IO/IOMGR/CREATE.C) |
| `io` | Additional I/O interface GUID definitions; a separate build unit alongside `io/iomgr` | [IOGUID.C](../WRK-V1.2/BASE/NTOS/IO/IOGUID.C) and its [makefile](../WRK-V1.2/BASE/NTOS/IO/BUILD/MAKEFILE) |
| `cache` | File cache maps, cached reads/writes, dirty-page writeback and cache flushing; works with MM and filesystem drivers | `CcInitializeCacheManager`, `CcInitializeCacheMap` in [FSSUP.C](../WRK-V1.2/BASE/NTOS/CACHE/FSSUP.C); `CcCopyRead`, `CcCopyWrite` in [COPYSUP.C](../WRK-V1.2/BASE/NTOS/CACHE/COPYSUP.C); `CcFlushCache` in [CACHESUB.C](../WRK-V1.2/BASE/NTOS/CACHE/CACHESUB.C) |
| `fsrtl` | Shared filesystem support such as fast I/O, locks, names, notifications and stream contexts; does not implement NTFS/CDFS | `FsRtlInitSystem` in [FSRTLPC.C](../WRK-V1.2/BASE/NTOS/FSRTL/FSRTLPC.C); `FsRtlCopyRead`, `FsRtlCopyWrite` in [FASTIO.C](../WRK-V1.2/BASE/NTOS/FSRTL/FASTIO.C) |
| `raw` | Built-in RAW filesystem handling for volumes without a recognized mounted filesystem | `RawInitialize` in [RAWINIT.C](../WRK-V1.2/BASE/NTOS/RAW/RAWINIT.C), request dispatch in [RAWDISP.C](../WRK-V1.2/BASE/NTOS/RAW/RAWDISP.C), read/write in [READWRIT.C](../WRK-V1.2/BASE/NTOS/RAW/READWRIT.C) |
| `fstub` | Disk/partition and drive-name helper functions retained in the kernel | `HalExamineMBR`, `IoReadPartitionTable`, `IoSetPartitionInformation`, `IoWritePartitionTable` and drive-letter helpers in [DRIVESUP.C](../WRK-V1.2/BASE/NTOS/FSTUB/DRIVESUP.C); these are not a storage controller driver |
| `lpc` | Local Procedure Call ports and request/reply IPC | `LpcInitSystem` in [LPCINIT.C](../WRK-V1.2/BASE/NTOS/LPC/LPCINIT.C); `NtCreatePort` in [LPCCREAT.C](../WRK-V1.2/BASE/NTOS/LPC/LPCCREAT.C); `NtRequestWaitReplyPort` in [LPCSEND.C](../WRK-V1.2/BASE/NTOS/LPC/LPCSEND.C) |
| `dbgk` | Kernel support for debugging user processes, debug objects and process/thread/image notifications | `DbgkInitialize` in [DBGKOBJ.C](../WRK-V1.2/BASE/NTOS/DBGK/DBGKOBJ.C); `DbgkCreateThread`, `DbgkMapViewOfSection` in [DBGKPROC.C](../WRK-V1.2/BASE/NTOS/DBGK/DBGKPROC.C); distinct from the KD transport DLL |
| `wmi` | Kernel WMI providers/requests and event tracing buffers, sessions and instrumentation | `WmipDriverEntry` in [WMI.C](../WRK-V1.2/BASE/NTOS/WMI/WMI.C); `WmiStartTrace`, `WmiTraceEvent` in [TRACEAPI.C](../WRK-V1.2/BASE/NTOS/WMI/TRACEAPI.C); `WmipLogger`, `WmiBootPhase1` in [TRACELOG.C](../WRK-V1.2/BASE/NTOS/WMI/TRACELOG.C) |
| `perf` | Performance logging hooks, profile interrupts and process/module/file-name rundown | `PerfInfoStartLog` in [PERFSUP.C](../WRK-V1.2/BASE/NTOS/PERF/PERFSUP.C); `PerfInfoLogBytes` in [LOGGING.C](../WRK-V1.2/BASE/NTOS/PERF/LOGGING.C); `PerfProfileInterrupt`, `PerfInfoProcessRunDown` in [HOOKS.C](../WRK-V1.2/BASE/NTOS/PERF/HOOKS.C) |
| `rtl` | Shared runtime algorithms: strings/NLS, PE parsing, context setup, trees, bitmaps and related helpers | `RtlUnicodeStringToAnsiString` in [NLS.C](../WRK-V1.2/BASE/NTOS/RTL/NLS.C); `RtlImageNtHeader` in [RTLNTHDR.C](../WRK-V1.2/BASE/NTOS/RTL/RTLNTHDR.C); `RtlInitializeContext` in [I386/CONTEXT.C](../WRK-V1.2/BASE/NTOS/RTL/I386/CONTEXT.C) |

`BASE/NTOS/INC` contains shared NTOS-private declarations; `PUBLIC` contains
headers shared with other components, including the
[`LOADER_PARAMETER_BLOCK`](../WRK-V1.2/PUBLIC/INTERNAL/BASE/INC/ARC.H). `BUILD`
contains makefiles, link inputs, objects and output images. These are support
directories rather than separately loaded operating-system modules.

## Supplied prebuilt code and source boundaries

The checkout does not expose every implementation that runs in the kernel.
WRK's README explicitly identifies missing source primarily in Plug and Play,
power management, Driver Verifier, the kernel debugger interface and VDM.
`IO/PNPMGR`, `VERIFIER` and `VDM` contain limited headers/includes, not full
buildable implementations of those subsystems.

| Link input | Role and inspection boundary |
|---|---|
| `NTOSWRK.LIB` | Supplied static code for omitted pieces and other support. The current [link map](../WRK-V1.2/BASE/NTOS/BUILD/EXE/wrkx86.map) attributes `ExInitSystemPhase2` and `NtDisplayString` to `ntoswrk:EXSCAN.obj`, `InbvDriverInitialize`/`InbvDisplayString` to `ntoswrk:BOOTVID.obj`, PnP initialization to `ntoswrk:PNPINIT.obj`, and power initialization to `ntoswrk:POINIT.obj`. Their call sites/types are visible, but their original function bodies are not included. In particular, the license/setup validation inside `ExInitSystemPhase2` cannot be explained as visible `EX` source. |
| `NTOSARCH.LIB` | Supplied architecture-dependent static support, merged into the kernel export/import library during the final build. The i386 library includes security-cookie/load-configuration and structured exception handling support symbols such as `__load_config_used`, `___security_cookie`, `__SEH_prolog` and `__SEH_epilog`. It is not a guest DLL. |
| `SDBAPINT.LIB` | Supplied static application-compatibility database/cache support, with `NtApphelpCacheControl`, `ApphelpCacheInitialize`/`Lookup`/`Read`/`Write`/`Shutdown`, `SdbInitDatabaseInMemory`, `SdbGetFileInfo` and database tag/index helpers. The link map also includes `Sdb*` and `ApphelpCache*` symbols from this library. Its implementation source is not included. |
| `HAL.LIB`, `BOOTVID.LIB`, `KDCOM.LIB` | Import libraries used at link time. They describe DLL imports and do not supply the runtime DLLs themselves. |
| `NTOSKRNL.RES`, `STUB512.COM` / AMD64 `HOTPATCH.OBJ` | Kernel resources, the x86 executable stub and AMD64 hotpatch link object; not independent drivers. |

The corresponding inputs live in
[`BUILD/PREBUILT/i386`](../WRK-V1.2/BASE/NTOS/BUILD/PREBUILT/i386/) for the current
target; the kit also has AMD64 inputs. The output `.pdb`, `.map`, `.def`, `.lib`
and object files support debugging/linking and are not additional boot modules.

## HAL: hardware abstraction layer

`hal.dll` is the kernel's canonical import identity. FreeLoader can select the
physical `halmacpi.dll` filename while registering it as `hal.dll`; similarly,
the WRK image is registered as `ntoskrnl.exe`. See `LoadWindowsCore` in
[winldr.c](../_bootldr/freeldr/freeldr/ntldr/winldr.c). The supplied HAL imports
the kernel and KDCOM in return, so all core images must be linked/resolved as a
set before handoff. Retained binary evidence:
WRK imports (`artifacts/checks/wrk-freeldr-current-20261003-033907/wrk-pe-imports.txt`)
and HAL imports (`artifacts/checks/wrk-freeldr-current-20261003-033907/hal-pe-imports.txt`).

| Major HAL interface | Function |
|---|---|
| `HalInitSystem`, `HalInitializeProcessor`, `HalStartNextProcessor`, `HalAllProcessorsStarted` | Platform and multiprocessor initialization |
| `HalBeginSystemInterrupt`, `HalEndSystemInterrupt`, `HalEnableSystemInterrupt`, `HalDisableSystemInterrupt`, `HalRequestIpi`, software-interrupt routines | Interrupt-controller and interprocessor-interrupt support |
| `KeRaiseIrql`, `KeLowerIrql`, `KeGetCurrentIrql`, spin-lock entry points | Architecture/platform-specific IRQL and lock operations imported by this x86 kernel |
| `KeQueryPerformanceCounter`, `KeStallExecutionProcessor`, `HalSetTimeIncrement`, clock/profile routines | Timing, stalls, clock configuration and profiling |
| `HalGetAdapter`, `HalAllocateAdapterChannel`, `HalAllocateCommonBuffer`, `IoMapTransfer`, adapter/map-register helpers | DMA adapter and transfer support |
| `HalGetBusDataByOffset`, `HalSetBusDataByOffset`, `HalTranslateBusAddress`, `HalGetInterruptVector`, port-I/O entry points | Bus configuration and device I/O access |
| `HalQueryRealTimeClock`, `HalSetRealTimeClock`, firmware environment routines, `HalReturnToFirmware`, `HalHandleNMI` | RTC, firmware return and platform-specific exceptional handling |

The supplied x86 choices are
[`HALMACPI`](../WRK-V1.2/WS03SP1HALS/X86/HALMACPI/) (ACPI APIC MP),
[`HALACPIM`](../WRK-V1.2/WS03SP1HALS/X86/HALACPIM/) (ACPI PIC MP), and
[`HALMPS`](../WRK-V1.2/WS03SP1HALS/X86/HALMPS/) (MPS MP), with symbols. WRK's x86
build requires a suitable MP HAL even for a one-vCPU guest. Select by compatible
OS/architecture/platform, not solely by filename. Microsoft HAL implementation
source is absent. The ReactOS HAL sources in [`_bootldr_ex/hal`](../_bootldr_ex/hal/)
are alternate compatibility candidates; they are not the HAL used by the
verified native experiment.

## BOOTVID: early boot display

The built WRK kernel statically imports these ten interfaces from
`bootvid.dll`:

| Interfaces | Function |
|---|---|
| `VidInitialize`, `VidResetDisplay`, `VidCleanUp` | Initialize/reset/release the boot display |
| `VidDisplayString`, `VidSetTextColor`, `VidSetScrollRegion` | Boot text output, foreground color and scrolling bounds |
| `VidSolidColorFill` | Fill a rectangular region |
| `VidBitBlt`, `VidBufferToScreenBlt`, `VidScreenToBufferBlt` | Bitmap drawing and copies between screen memory and buffers |

The current ReactOS source snapshot has
[console.c](../_bootldr_ex/drivers/base/bootvid/console.c),
[common.c](../_bootldr_ex/drivers/base/bootvid/common.c), and the PC VGA code in
[i386/pc](../_bootldr_ex/drivers/base/bootvid/i386/pc/), with the export list in
[bootvid.spec](../_bootldr_ex/drivers/base/bootvid/bootvid.spec). Other platform
implementations are present but not selected for this PC experiment.

The kernel's `Inbv*` boot-display wrapper code is separate from the DLL and is
supplied in `NTOSWRK.LIB`. `INITOS.C` calls `InbvDriverInitialize` before boot
display use. The native demo reaches that display through `NtDisplayString`.
`/SOS` permits the intended boot text path; `/NOGUIBOOT` is unsuitable for this
greeting experiment. Disabling graphics does not remove the PE import
requirement for BOOTVID.

## KDCOM: serial debugger transport

The kernel imports `KdDebuggerInitialize0`, `KdDebuggerInitialize1`,
`KdSendPacket`, `KdReceivePacket`, `KdSave`, `KdRestore`, `KdD0Transition` and
`KdD3Transition`. Initialization selects/configures the COM transport, and
packet routines implement the debugger's serial protocol. In the current
ReactOS candidate, the save/restore and D0/D3 routines return success without
additional COM-port work; do not infer a complete power-transition
implementation from the export names.

Sources: [kdcom.c](../_bootldr_ex/drivers/base/kdcom/kdcom.c) handles port setup
and byte operations; [kddll.c](../_bootldr_ex/drivers/base/kdcom/kddll.c) handles
packets/checksums; [kdserial.c](../_bootldr_ex/drivers/base/kdcom/kdserial.c)
handles buffers; [kdcom.spec](../_bootldr_ex/drivers/base/kdcom/kdcom.spec) lists
exports. This is a transport DLL, not WinDbg/KD itself and not WRK's omitted
kernel debugger implementation. `/NODEBUG` does not remove the kernel/HAL
static import dependency. Successful boot alone does not verify every debugger
command or transport feature.

## Storage and filesystem drivers

The current RAM-disk experiment deliberately uses **two boot-start services**:

| Driver | Major functions and configuration |
|---|---|
| `ramdisk.sys` | `DriverEntry` registers dispatch/device-add handlers; `RamdiskAddDevice` creates the bus device; `RamdiskCreateRamdisk`/`RamdiskCreateDiskDevice` create the image-backed child; `RamdiskPnp` handles enumeration/start/resource requests; `RamdiskReadWrite`/`RamdiskReadWriteReal` access the image and `RamdiskDeviceControl` handles device controls. `/RDEXPORTASCD` selects a CD-style device for the inner ISO. The hive supplies a boot-start service and a matching root-device `CriticalDeviceDatabase` entry. |
| `cdfs.sys` | `DriverEntry` in `cdinit.c` registers the filesystem; `CdFsdDispatch` in `cddata.c` routes IRPs; `CdMountVolume` in `fsctrl.c` mounts the ISO; `CdCommonCreate` in `create.c` opens filesystem objects; `CdCommonRead` in `read.c` reads file data. These let WRK open system-root files after FreeLoader stops running. The hive supplies a boot-start filesystem service. |

[Build-WrkRuntime.ps1](../tools/Build-WrkRuntime.ps1) builds these from the full
sibling `../reactos` checkout (`drivers/storage/class/ramdisk` and
`drivers/filesystems/cdfs`). Those source trees are **not included in
`_bootldr_ex`**. The runtime script writes an isolated copy of `ramdisk.c` under
`artifacts/wrk-runtime-build-x86/overrides` (`artifacts/wrk-runtime-build-x86/overrides/`)
and fixes `DO_DEVICE_INITIALIZING` clearing and PDO PnP IRP completion/status
handling. Its provenance (`artifacts/wrk-runtime-build-x86/overrides/provenance.json`)
records those changes; original sibling sources remain unchanged. Details and
verification limits are in [WRK_HELLO_BOOT.md](WRK_HELLO_BOOT.md).

FreeLoader's own RAM-disk/ISO reader is a pre-kernel facility. It cannot replace
`ramdisk.sys` or `cdfs.sys` after handoff. Likewise, NTOS `fsrtl`, `fstub` and
`raw` are not substitutes for the current storage/filesystem stack.

An installed Windows disk instead needs the boot drivers selected by its
SYSTEM hive and hardware. Possible IDE configurations include `pciide.sys`,
`pciidex.sys`, `atapi.sys`, `disk.sys`/`classpnp.sys`, `ntfs.sys` or `fastfat.sys`,
and applicable `acpi.sys`/`pci.sys` bus/platform drivers. Physical CD access can
add `cdrom.sys` and CDFS. This is an **illustrative installed-system inventory**,
not a verified required/minimal set, and these drivers are not staged in the
current RAM-disk experiment. Filesystem, network and general device-driver
implementations are outside the supplied WRK NTOS sources.

## Loader and boot-medium components

| Component | Major function and current use |
|---|---|
| BIOS / virtual machine firmware | Starts the configured boot medium. It is external to WRK. The verified path uses VirtualBox BIOS and El Torito optical boot. |
| `isoboot.bin` / boot catalog | El Torito first stage and boot metadata that start FreeLoader from the external ISO; the image is 2,048 bytes. [Boot-sector sources](../_bootldr/freeldr/bootsect/) also include disk/filesystem-specific alternatives. |
| `freeldr.sys` | First FreeLoader stage: `BootMain` initializes loader facilities/boot access and `LaunchSecondStageLoader` loads the matching `rosload.exe`; see [freeldr.c](../_bootldr/freeldr/freeldr/freeldr.c). |
| `rosload.exe` | Matching second stage: `RunLoader` handles configuration/menu/OS selection in [bootmgr.c](../_bootldr/freeldr/freeldr/bootmgr.c). NT loader code reads registry/NLS, maps kernel/HAL/imports and boot drivers, builds loader structures, prepares x86 paging/CPU state and enters `KiSystemStartup`. See `LoadWindowsCore`, `WinLdrLoadBootDrivers`, `LoadAndBootWindowsCommon` in [winldr.c](../_bootldr/freeldr/freeldr/ntldr/winldr.c), registry/NLS functions in [wlregistry.c](../_bootldr/freeldr/freeldr/ntldr/wlregistry.c), and `WinLdrSetupMachineDependent` in [arch/i386/winldr.c](../_bootldr/freeldr/freeldr/ntldr/arch/i386/winldr.c). |
| `freeldr.ini` | Chooses `BootType=Windows2003`, system-root ARC path, kernel/HAL names, options and, for the explicit lab route, `SetupMode=Text`. |
| `WRKSYS.ISO` | Inner image containing `WRK/System32`; loaded into memory by `/RDPATH` and later exported by RAMDISK for CDFS. It is data, not a PE module. |
| NT loader parameter block and extension | Handoff contract: memory descriptors, module/driver lists, registry/NLS pointers, boot paths and hardware/setup state. WRK types are in [ARC.H](../WRK-V1.2/PUBLIC/INTERNAL/BASE/INC/ARC.H). Correct structure layouts and virtual-address conversion are essential. |
| NTLDR, `NTDETECT.COM`, `boot.ini`, Windows disk boot code | Alternative installed-Windows BIOS boot route; not used by the current FreeLoader-from-CD experiment. Keep original installed-system boot entries for recovery when testing WRK on that route. |
| Local `bootloader/stage1.asm` and `stage2.asm` | Separate educational BIOS bootstrap/chainloader: reads its fixed floppy sectors, shows a menu, and can chainload the first hard disk MBR. It does not load PE images or construct the NT handoff. See [BOOTLOADER.md](BOOTLOADER.md). |

The loader/minihal/boot runtime and filesystem readers are distinct from the
kernel HAL and drivers. The [`_bootldr`](../_bootldr/README.md) source subtree
needs a full ReactOS build environment. [`_bootldr_ex`](../_bootldr_ex/README.md)
bundles focused HAL/BOOTVID/KDCOM/loader/SDK/data tooling sources and dependencies;
its private NT headers and kernel import definitions support those builds and
do not build a replacement NTOS kernel. Optional ARM, AMD64, UEFI and other
platform code does not establish a tested WRK route.

## Registry and NLS data

| Data | Major function and current contents |
|---|---|
| `System32/Config/SYSTEM` | Control-set selection, boot service names/order, hardware and kernel configuration, NLS filenames and Session Manager configuration. The current seed selects control set 1 and boot-start RAMDISK/CDFS. It also includes the copied root/PCI arbiter allocation-order and reservation records needed by WRK PnP initialization. |
| `SOFTWARE`, `DEFAULT`, `SAM`, `SECURITY` | Other machine/default/security hive inputs to configuration initialization. SAM/SECURITY are valid empty experiment seeds, not functional account/security databases. |
| `c_1252.nls`, `c_437.nls`, `l_intl.nls` | ANSI and OEM codepage tables and Unicode case data selected by this hive. FreeLoader supplies them in `NlsData`, and early WRK startup calls `RtlInitNlsTables`/`RtlResetRtlTranslations`. Other systems must follow their hive-selected filenames. |
| Setup block / setup registry values | Distinguish the explicit text-mode setup lab from normal installed-system startup. Generated lab hives do not provide validated installed Server 2003 `Setup/SystemPrefix` state. This is relevant to `SYSTEM_LICENSE_VIOLATION`; see [failures.md](failures.md). |

[New-WrkHelloHives.ps1](../tools/New-WrkHelloHives.ps1) processes
[wrk-hello.inf](../hello_world/boot/wrk-hello.inf) and source arbiter records using
`mkhive`; it generates codepages using `txt2nls` and copies `l_intl.nls`.
`/MININT` uses WRK's in-memory nonpersistent registry path. The `Core` hive mode
has no boot services and cannot provide the filesystem needed for native process
startup. The loader's normal `SYSTEM.ALT` fallback is recovery behavior, not an
extra mandatory hive when SYSTEM is valid. Registry hives and NLS files cannot
be replaced with empty files bearing the expected names.

## Native user-mode components

WRK maps `System32/ntdll.dll` and starts `System32/smss.exe` after kernel/driver
initialization. The experiment substitutes these deliberately narrow modules:

| Component / entry point | Major function |
|---|---|
| `ntdll.dll`: `KiUserApcDispatcher`, `LdrInitializeThunk`, `MiniLdrInitializeThunk` | Accept the initial user APC/context, resolve the executable's named NTDLL imports against the already mapped DLL, change/restore IAT protection and use `NtContinue` to resume the executable entry. [startup.asm](../hello_world/ntdll/startup.asm), [ntdll.c](../hello_world/ntdll/ntdll.c) |
| NTDLL syscall wrappers | Six WRK-specific `INT 2E` wrappers: `NtContinue`, `NtDelayExecution`, `NtDisplayString`, `NtProtectVirtualMemory`, `NtRaiseException`, `NtTerminateProcess`. Syscall numbers/argument counts come from WRK's [SYSTABLE.ASM](../WRK-V1.2/BASE/NTOS/KE/I386/SYSTABLE.ASM), not the host OS. [Export definition](../hello_world/ntdll/ntdll.def) |
| Other required NTDLL exports | Names WRK resolves for exception/callback/SLIST/syscall dispatch. Some are unsupported-operation handlers, not complete Windows facilities. See [NTDLL limitations](../hello_world/ntdll/README.md). |
| `smss.exe`: `NtProcessStartup` | Waits one second, calls `NtDisplayString` with `Hello world from WRK SMSS!`, records status in `SmssDisplayStatus`, and loops in `NtDelayExecution` so the initial process stays alive. [smss.c](../hello_world/smss/smss.c) |

This NTDLL has no imported DLLs and the native demo does not use a C runtime,
KERNEL32 or a Win32 console. It requires preferred image addresses and omits
general relocation/TLS/DLL loading, process heaps and complete exception/thread
support. The demo does not execute the real Session Manager's Windows startup
tasks. A normal full Windows system additionally needs the environment's real
SMSS, configured BootExecute/subsystem programs, DLLs, services and logon
components; CSRSS/WINLOGON and a desktop are outside this assembled experiment.

## Build, packaging and verification tools

| Repository component | Major function |
|---|---|
| [Build-WrkX86.cmd](../tools/Build-WrkX86.cmd), `WRK.sln`, bundled `TOOLS/X86` | Build WRK with the supplied nmake/compiler/assembler/linker; kernel outputs are under `BASE/NTOS/BUILD/EXE`. |
| [Build-WrkFreeLoader.cmd](../tools/Build-WrkFreeLoader.cmd) | Build/collect a matching FreeLoader pair and boot image from the sibling ReactOS checkout. |
| [Build-WrkSetupLoader.ps1](../tools/Build-WrkSetupLoader.ps1) | Build the isolated explicit NT 5.2 text-mode setup lab loader with provenance. |
| [Build-WrkRuntime.ps1](../tools/Build-WrkRuntime.ps1) | Build BOOTVID/KDCOM/CDFS/RAMDISK and apply isolated RAMDISK source corrections. |
| [Build-HelloWorld.ps1](../hello_world/Build-HelloWorld.ps1), [verify_build.py](../hello_world/verify_build.py) | Generate WRK syscall wrappers, compile/link the native pair, and verify PE headers/checksums/imports/exports and syscall instructions. |
| [New-WrkHelloHives.ps1](../tools/New-WrkHelloHives.ps1) | Generate/validate isolated binary hives and early NLS files. |
| [New-WrkHelloIso.ps1](../tools/New-WrkHelloIso.ps1), [Verify-WrkHelloIso.ps1](../tools/Verify-WrkHelloIso.ps1) | Stage the inner/outer ISOs and manifests; validate boot metadata, payload contents and hashes. |
| [New-WrkFreeLoaderIso.ps1](../tools/New-WrkFreeLoaderIso.ps1) | Package the original installed-disk loader/payload disc; it does not stage a complete selected system root. |
| [New-WrkVirtualBox.ps1](../tools/New-WrkVirtualBox.ps1), [Test-WrkHelloVm.ps1](../tools/Test-WrkHelloVm.ps1) | Provision the VM/payload path and run disposable headless Hello World VM checks with retained evidence. |
| [Inspect-WrkVmCore.py](../tools/Inspect-WrkVmCore.py) | Inspect VirtualBox core/register/memory evidence to support WRK execution/failure analysis. |
| `_bootldr_ex` host tooling | `mkhive`, `txt2nls` and build/SDK support produce registry/NLS data; export/source verification tools maintain the focused snapshot. They are build tools, not guest runtime services. |
| [Build-Bootloader.ps1](../bootloader/Build-Bootloader.ps1) | Assemble the independent educational BIOS floppy bootstrap. |
| [PREBUILD.PY](../PREBUILD.PY) | Prepare output directories expected by the original WRK/ProjectOZ build layout. |
| [Clean-GeneratedFiles.ps1](../tools/Clean-GeneratedFiles.ps1) | Preview/remove generated output while preserving source and build prerequisites. |

The remaining educational material does not participate in this boot:
[`ProjectOZ`](../ProjectOZ/README.TXT) implements user-mode SPACE hardware
abstractions and BasicOZ above Native NT services;
[`CRK`](../CRK/), [`NT DESIGN WORKBOOK`](../NT%20DESIGN%20WORKBOOK/) and the
Windows Internals CHM are teaching/reference material. `artifacts` stores build
outputs, VM media, manifests and verification evidence rather than another
kernel subsystem. Apply the individual WRK, ProjectOZ and ReactOS source/license
notices to their respective components.
