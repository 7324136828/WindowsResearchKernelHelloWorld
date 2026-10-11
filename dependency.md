# WRK / FreeLoader boot dependencies

Historical build/VM results below describe the recorded experiments. Generated
evidence, media, VM files, and build outputs were removed during cleanup; rebuild
and rerun to collect fresh evidence.

Verified on **2026-10-03 (America/New_York)** against the local WRK 1.2
x86 build and the provided FreeLoader sources.

**The experimental RAM-disk ISO now starts the actual WRK kernel and displays
the native SMSS Hello World greeting. A Windows installation on a hard disk is
not inherently
required, but compatible runtime components and registry data are
still required.** The original `artifacts/wrk-freeldr/WRK-FreeLoader.iso`
contains a loader and kernel payload,
not that runtime environment. Its WRK entry
points at a blank disk and fails before loading the kernel.

## New experimental runtime availability

A separate native Hello World environment now compiles from the supplied boot
components and the full sibling ReactOS checkout. It uses the existing WRK
kernel and supplied Microsoft Server 2003 SP1 HAL, newly built ReactOS BOOTVID,
KDCOM, RAMDISK and CDFS modules, fresh minimal test hives/NLS data, and the
`hello_world` native NTDLL/SMSS pair. Its packager stages an inner system-root
ISO for FreeLoader RAM-disk boot instead of selecting the blank hard disk.

See [WRK native Hello World boot experiment](docs/WRK_HELLO_BOOT.md) for source
provenance, the isolated RAMDISK fix, build/package commands and verification
limits. **Compilation and registry/NLS validation have passed. The original
normal-mode experiment reaches WRK, then stops at 0x9A subcode 4 because its
SYSTEM hive lacks Setup\SystemPrefix. The explicit NT 5.2 setup-mode
experiment passes that check. Adding the missing arbiter allocation and
reservation data also passes Plug and Play phase 0, resolving its previous
IO1_INITIALIZATION_FAILED (0x69) stop. Repairing RAMDISK PDO request completion
also passes the later BAD_POOL_HEADER (0x19) stop. The latest VirtualBox test
displays `Hello world from WRK SMSS!`.**
These ReactOS modules
are experimental compatibility candidates, not supplied Microsoft system
binaries. `_bootldr_ex` alone lacks the RAMDISK/CDFS source trees, so the current
runtime build also uses `../reactos`.

The latest verified setup-mode experimental disc is
`artifacts/wrk-hello-20261003-setup-pnp/WRK-HelloWorld.iso` (`artifacts/wrk-hello-20261003-setup-pnp/WRK-HelloWorld.iso`).
Its greeting screen (`artifacts/wrk-hello-20261003-setup-pnp/verification/screen-final.png`)
confirms the native demo runs after the arbiter and RAMDISK completion repairs.
The previous normal-mode disc remains in `artifacts/wrk-hello-20261003-r2`.
Its external boot catalog and all 16 inner system payload files passed checks.
See the WRK banner (`artifacts/wrk-hello-20261003-r2/verification/screen-extended-30s.png`)
and later stop screen (`artifacts/wrk-hello-20261003-r2/verification/screen-extended-60s.png`).
The greeting verifies the storage/filesystem and NTDLL/SMSS startup path needed
by this small demo; general driver and filesystem behavior has not been tested.
The disposable VM is powered off; original kernel/HAL/ISO and new ISO hashes
remain unchanged.

[Microsoft's 0x9A reference](https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/bug-check-0x9a--system-license-violation)
and WRK's `BUGCODES.TXT` identify subcode 4 as a missing SystemPrefix setup
value. The supplied ReactOS SYSTEM has only an empty REG_BINARY placeholder
for this value; it does not provide verified Server 2003 license/setup state.
The current seed omits it. A compatible valid source SYSTEM/setup state is
still required; no licensing data is fabricated and no checks are patched.

The original ISO and its verified missing-hive failure remain unchanged. The
inventory below describes that original ISO, not the newly generated runtime.

## What is present, and what is missing in the original ISO

The supported x86 target stated in [WRK's README](WRK-V1.2/README.TXT) is
**Windows Server 2003 SP1**, with a multiprocessor HAL. Windows XP x86 is
explicitly incompatible. Do not substitute Windows 10/11 files or assume
that a ReactOS component is a compatible Windows binary merely because its
filename or exports match. Other service packs have not been verified here.

| Dependency | Purpose / required stage | Original ISO / selected blank-disk system root |
|---|---|---|
| BIOS El Torito boot image, `freeldr.sys`, matching `rosload.exe`, `freeldr.ini` | Start FreeLoader and select the NT 5.2 path | Present; booted in VirtualBox |
| `System32\wrkx86.exe` beneath the selected system root | WRK kernel PE image | Built; ISO has it in `payload\`, **not** at the selected system root |
| Compatible MP HAL, selected as `Hal=halmacpi.dll` | Interrupts, clocks, memory/platform initialization | Supplied in WRK and ISO `payload\`; not at the selected system root |
| `System32\bootvid.dll` | Static kernel imports; VGA boot display | Missing from the original ISO and selected system root |
| `System32\kdcom.dll` | Static kernel/HAL imports; debugger transport | Missing from the original ISO and selected system root |
| `System32\Config\SYSTEM` | Control-set selection, NLS names, driver enumeration; kernel registry initialization | Missing; the attached VDI is blank |
| Registry-selected NLS files in `System32\` | ANSI/OEM code pages and Unicode case tables, used in early kernel initialization | Missing from the original ISO and selected system root |
| Registry-selected boot drivers and their imports | Kernel disk/partition/filesystem access and hardware initialization | Missing; exact set depends on the boot medium, registry and devices |
| `System32\ntdll.dll` and `System32\smss.exe` | Continue into the initial native user process | Missing from the original ISO and selected system root |
| Remaining registry hives, native programs, DLLs and drivers | Continue through Session Manager and Windows startup | No base OS is present |

The observed `HALMACPI.DLL` is Server 2003 SP1 version
`5.2.3790.1830 (srv03_sp1_rtm.050324-1447)`. WRK identifies itself as
`5.2.3800.1807`; numeric versions need not be identical. The supported
platform and binary interfaces must match.

`wrkx86.pdb` is useful for proving execution in a debugger, but is not a
guest boot dependency. NTLDR, `boot.ini`, Windows MBR and partition boot
code are not required for the **FreeLoader-from-CD** loader route. They
are needed only if separately using the original Windows disk boot route.

## Verified binary imports

`WRK-V1.2\TOOLS\X86\LINK.EXE /dump /imports` on the actual binary reports
three imported modules:

- `HAL.dll`: platform initialization and interrupt/timing/DMA interfaces.
- `BOOTVID.dll`: `VidInitialize`, `VidDisplayString`, `VidSetTextColor`,
  `VidSolidColorFill`, `VidBitBlt`, `VidBufferToScreenBlt`,
  `VidScreenToBufferBlt`, `VidResetDisplay`, `VidCleanUp`, `VidSetScrollRegion`.
- `KDCOM.dll`: `KdDebuggerInitialize0`, `KdDebuggerInitialize1`,
  `KdSendPacket`, `KdReceivePacket`, `KdSave`, `KdRestore`,
  `KdD0Transition`, `KdD3Transition`.

`HALMACPI.DLL` in turn imports `ntoskrnl.exe` and `KDCOM.dll`. FreeLoader
loads the selected WRK image under the canonical `ntoskrnl.exe` module
identity and the selected HAL under `hal.dll`; their physical filenames
can differ. See `LoadWindowsCore` in
[winldr.c](_bootldr/freeldr/freeldr/ntldr/winldr.c).

Turning debugging off does not remove WRK's PE dependency on KDCOM.
Disabling graphics does not remove its PE dependency on BOOTVID. Imports
must resolve before control reaches WRK. These three modules also do not
constitute a complete Windows runtime: registry data, NLS data and any
selected boot drivers are separate requirements.

Retained binary evidence:
WRK imports (`artifacts/checks/wrk-freeldr-current-20261003-033907/wrk-pe-imports.txt`)
and HAL imports (`artifacts/checks/wrk-freeldr-current-20261003-033907/hal-pe-imports.txt`).

## SYSTEM hive and NLS requirements

FreeLoader's normal `BootType=Windows2003` route performs these operations
before loading the kernel:

1. Open `<SystemRoot>\System32\Config\SYSTEM` and import a valid binary
   registry hive. If absent/corrupt, try `SYSTEM.ALT`.
2. Select the current control set using `Select\Default`. This normal
   path calls `RegInitCurrentControlSet(FALSE)`.
3. Read NLS configuration and construct the boot-driver list.
4. Load the kernel/HAL/debugger core, resolve imports and load boot drivers.
5. Finalize the loader block, establish the x86 execution environment and
   call the kernel entry point.

Source: [winldr.c](_bootldr/freeldr/freeldr/ntldr/winldr.c), lines
1343, 1356, 1404-1412 and 1508; and
[wlregistry.c](_bootldr/freeldr/freeldr/ntldr/wlregistry.c),
`WinLdrInitSystemHive`, `WinLdrScanSystemHive` and `WinLdrGetNLSNames`.
`SYSTEM.ALT` is a recovery fallback, not a second mandatory hive to obtain
when a good SYSTEM hive is available. An empty file named SYSTEM will not
satisfy the loader.

At the loader level the selected `ControlSet00N` must supply:

- `Services`: boot-driver services selected by `Start`, with `ImagePath`,
  `ErrorControl`, `Group` and `Tag` metadata; preserve additional service
  configuration required by the kernel and drivers.
- `Control\GroupOrderList` and `Control\ServiceGroupOrder\List`:
  boot-driver ordering; `List` is a valid `REG_MULTI_SZ`.
- `Control\NLS\CodePage`: `ACP`, `OEMCP` and the corresponding numeric
  code-page values mapped to filenames. `OEMHAL` is also queried.
- `Control\NLS\Language`: `Default` and its locale-to-filename mapping.

For a typical English system the three NLS files are `c_1252.nls`,
`c_437.nls` and `l_intl.nls`. **Use the filenames specified by the actual
hive**, not a universal hardcoded list. The OEM font path in this
FreeLoader version has an explicitly marked implementation hack; its
presence is another compatibility detail to validate during a real WRK
test. Likewise `WinLdrScanSystemHive` does not consistently propagate NLS
load failure, so passing that stage alone does not prove valid NLS data.

These are loader requirements, not a complete recipe for constructing a
WRK-compatible SYSTEM hive. Kernel/HAL initialization reads additional
configuration. A compatible existing hive is the practical baseline.
Never copy the host Windows 11 SYSTEM hive into this environment.

## Drivers and continued Windows startup

FreeLoader enumerates boot-start services (`Start=0`), includes the boot
filesystem service, and orders drivers by configured groups and tags.
Preserve the compatible environment's service and driver dependencies.
When no `ImagePath` is supplied, the loader's registry support constructs
`System32\Drivers\<service>.sys`. Resolve every selected driver's PE
imports as well.

For this BIOS/PIIX3/PIIX4 IDE VM, a normal Server 2003 installation
typically uses an IDE controller stack (`pciide.sys`, `pciidex.sys`,
`atapi.sys`), `disk.sys`/`classpnp.sys`, the appropriate filesystem
(`ntfs.sys` or `fastfat.sys`), and platform/bus drivers such as `acpi.sys`
and `pci.sys`. **This is an illustrative inventory, not a verified minimal
set.** CD boot introduces the corresponding CD/filesystem stack, such as
`cdrom.sys` and `cdfs.sys`. The actual SYSTEM hive, controller configuration
and boot device determine what is required. Preserve applicable filters
and dependencies from the compatible source environment.

FreeLoader's own ISO9660/NTFS reader only reads files while the loader is
running. WRK needs kernel-mode drivers to access the medium after handoff.
A missing storage/filesystem stack can fail later even if kernel entry
was reached.

For normal continued startup, WRK initializes its registry, memory and I/O
subsystems, loads NTDLL and creates `\SystemRoot\System32\smss.exe`.
Session Manager then needs the configuration and executables selected by
the environment (including the usual SYSTEM/SOFTWARE/SAM/SECURITY/DEFAULT
hives, and configured BootExecute and subsystem programs). Full logon
adds further binaries and services. It cannot be reconstructed accurately
as a short list of the kernel's three PE imports.

Source: [INITOS.C](WRK-V1.2/BASE/NTOS/INIT/INITOS.C), lines 167 and
1646-1780; [PSINIT.C](WRK-V1.2/BASE/NTOS/PS/PSINIT.C), `NTDLL_PATH_NAME`;
[CMSYSINI.C](WRK-V1.2/BASE/NTOS/CONFIG/CMSYSINI.C),
`CmpInitializeSystemHive` and `CmpInitializeHiveList`.

## Booting without installing Windows on the hard disk

FreeLoader already supports loading a system directory from its boot
volume. [bootcd.ini](_bootldr/bootdata/bootcd.ini), lines 34-43, uses
`BootType=Windows2003`, `SystemPath=\reactos`, and `/MININT`; it also has
a `ramdisk(0)` example. This is evidence of a loader capability, **not**
proof that substituting WRK into a ReactOS LiveCD will boot successfully.

A separate WRK disc can stage a compatible system root on the CD,
including the kernel, HAL, BOOTVID, KDCOM, registry, NLS data and
appropriate drivers. A RAM-disk variant would additionally need verified
kernel-side RAM-disk support and handoff; FreeLoader's RAM-disk file reader
alone is insufficient. Its boot entry would
then select that root instead of `rdisk(0)partition(1)\WINDOWS`. The new
experimental packager stages this kind of system root; runtime execution
still requires verification beyond the observed WRK startup.
Read-only media, `/MININT`, hive handling and kernel device paths also need
validation. The original [packager](tools/New-WrkFreeLoaderIso.ps1) accepts
only installed-disk ARC paths and does not stage a system root. The new
[experimental packager](tools/New-WrkHelloIso.ps1) implements a separate
RAM-disk image route; the original ISO remains unchanged.

Use compatible Server 2003 SP1 x86 files you are entitled to use. At the
original-ISO verification, no compatible installed Windows SYSTEM hive,
BOOTVID or KDCOM binary was available in the inspected locations. ReactOS
sources and NLS data were present. The separate experiment above now
generates test hives and builds candidate runtime modules; their compatibility
with WRK beyond early startup still requires guest verification.

## What an actual WRK Hello World would prove

The loader must provide a correct NT 5.2 `LOADER_PARAMETER_BLOCK`, memory
descriptors, module/driver lists, registry/NLS pointers and hardware data,
with paging, stack and CPU structures set up. WRK dereferences its NLS
data early in phase 0; a direct BIOS jump to the PE entry is insufficient.
See [ARC.H](WRK-V1.2/PUBLIC/INTERNAL/BASE/INC/ARC.H) and
[NEWSYSBG.ASM](WRK-V1.2/BASE/NTOS/KE/I386/NEWSYSBG.ASM).

A kernel greeting could be added **after** `InbvDriverInitialize` and
`DisplayBootBitmap` in [INITOS.C](WRK-V1.2/BASE/NTOS/INIT/INITOS.C),
around lines 1050-1081, using `InbvDisplayString` with `/SOS` and without
`/NOGUIBOOT`. Capture it before subsequent screen updates. An intentional
early-halt demonstration could stop before later disk/user-mode startup;
that would prove WRK reached the greeting, not a completed Windows boot.
The files and registry needed to reach that point still must be supplied
and tested. There is no validated minimal subset in this repository yet.

The WRK kernel has not been changed to emit a kernel greeting; the separate demo uses native SMSS to print its message. A greeting
printed by FreeLoader would only prove loader execution. Completion must
be supported by a message executing inside the identified WRK image,
ideally corroborated by a debugger breakpoint/symbols at its entry or
greeting routine.

## Fresh verification of the provided ISO

Tested `artifacts\wrk-freeldr\WRK-FreeLoader.iso` in the existing
`WRK-FreeLoader-x86` VM with VirtualBox **7.2.20r175154**, headless, on
2026-10-03. The attached disk remained the existing blank VDI. VirtualBox
ran through its NEM backend; no host hypervisor/security settings changed.

| Check | Result |
|---|---|
| ISO9660 primary descriptor | PASS; `CD001`, volume `WRK_BOOT` |
| El Torito boot catalog | PASS; x86, no emulation, valid checksum/signature, four 512-byte sectors |
| Boot image and all staged file contents | PASS; identical to the supplied build/staging files |
| BIOS -> FreeLoader menu | PASS; WRK and original Windows menu entries visible |
| Select WRK -> NT loader path | PASS; observed missing-hive dialog |
| WRK image loaded / kernel entry reached | **NOT REACHED**; hive failure precedes core loading |
| WRK Hello World | **NOT REACHED** |
| Final VM state | `poweroff` |
| Pre/post SHA-256 | Eight checked files unchanged: kernel, PDB, HAL, both loader binaries, boot image, ISO and blank VDI |

The exact observed failure is **`Could not load SYSTEM.ALT hive!`**.
This confirms the ISO is bootable, and confirms the current runtime
dependency blocker. It does not establish that WRK itself boots.

Evidence directory:
`artifacts/checks/wrk-freeldr-current-20261003-033907` (`artifacts/checks/wrk-freeldr-current-20261003-033907/`).
Key files:
menu screenshot (`artifacts/checks/wrk-freeldr-current-20261003-033907/screen-12s.png`),
failure screenshot (`artifacts/checks/wrk-freeldr-current-20261003-033907/screen-after-selection.png`),
ISO validation (`artifacts/checks/wrk-freeldr-current-20261003-033907/iso-validation.log`),
integrity results (`artifacts/checks/wrk-freeldr-current-20261003-033907/integrity-result.json`),
VM final configuration (`artifacts/checks/wrk-freeldr-current-20261003-033907/vm-after.txt`)
and VirtualBox log (`artifacts/checks/wrk-freeldr-current-20261003-033907/VBox.log`).
These artifacts are local and excluded from git.

## Upstream corroboration

The local source and binary inspection above describe this particular
build. Primary upstream references corroborate the general mechanisms:

- [ReactOS boot-CD configuration](https://github.com/reactos/reactos/blob/master/boot/bootdata/bootcd.ini#L34-L43)
  shows a Windows2003 loader entry using a relative CD root and `/MININT`.
- [ReactOS SYSTEM hive handling](https://github.com/reactos/reactos/blob/master/boot/freeldr/freeldr/ntldr/wlregistry.c#L125-L228)
  shows primary-hive loading, alternate recovery and control-set setup.
- [Microsoft: specifying driver load order](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/specifying-driver-load-order)
  describes loader preloading of boot-start drivers before kernel control.
