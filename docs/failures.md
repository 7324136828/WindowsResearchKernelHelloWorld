# WRK boot and runtime failures

Historical build/VM results below describe the recorded experiments. Generated
evidence, media, VM files, and build outputs were removed during cleanup; rebuild
and rerun to collect fresh evidence.

This guide covers the failures recorded in this checkout and the adjacent
failure paths visible in WRK 1.2. It is based on the source and retained VM
evidence reviewed on **2026-10-03 (America/New_York)**. The documentation work
did not rerun the kernel. For the execution sequence see [boot.md](boot.md);
for module responsibilities see [components.md](components.md).

The latest verified setup-mode RAM-disk image displays
`Hello world from WRK SMSS!`. That result verifies this native demo, including
the storage/filesystem path needed to start it. Ordinary installed-system
startup and a complete Windows desktop are separate outcomes.

## Recorded failures and their current status

These are different images and experiments, rather than four simultaneous
faults in the latest image.

| Image / stage | Observed symptom | Cause established here | Solution / result |
|---|---|---|---|
| Original `wrk-freeldr` loader/payload ISO | `Could not load SYSTEM.ALT hive!` | Selected hard disk is blank; no SYSTEM hive at the selected system root | Supply a compatible installed system, or build a separate complete RAM-disk system root. Original ISO remains a payload disc and still has this limitation. |
| `wrk-hello-20261003-r2`, normal mode | `0x9A (4, C0000034, 0, 0)` | Generated SYSTEM lacks `Setup\SystemPrefix` | Normal startup needs valid compatible installation/setup state. The separate explicit setup-mode experiment takes WRK's existing setup path and passes this stop; normal-mode state is still unresolved. |
| `wrk-hello-20261003-setup` | `0x69 (0, 0, 0, 0)`; `IopInitFailCode = 4` | Missing root/PCI arbiter allocation and reservation registry data during PnP phase 0 | Include the complete supplied arbiter records when generating hives. The following run passes PnP phase 0. |
| `wrk-hello-20261003-setup-arbiters` | `0x19 (20, 806A68FF, 806A6F1F, E8C475FF)` | RAMDISK PDO returns success for an unsupported PnP request without completing it or returning its incoming status | Rebuild the isolated RAMDISK override with corrected completion/status handling. Latest setup/PnP image reaches native SMSS. |
| `wrk-hello-20261003-setup-pnp` | Native greeting; no captured bugcheck | Previous arbiter and RAMDISK faults no longer stop this run | Captured `KiBugCheckData` is zero and `IopInitFailCode = 0`; native execution is independently audited. |

Evidence: original loader failure (`artifacts/checks/wrk-freeldr-current-20261003-033907/screen-after-selection.png`),
normal-mode stop (`artifacts/wrk-hello-20261003-r2/verification/screen-extended-60s.png`),
setup I/O trace (`artifacts/wrk-hello-20261003-setup/verification/io-init-core-analysis.json`),
arbiter-run pool stop (`artifacts/wrk-hello-20261003-setup-arbiters/verification/core-analysis.json`),
and successful native audit (`artifacts/wrk-hello-20261003-setup-pnp/verification/native-smss-audit.json`).

## First identify the failing stage

1. Capture the exact loader message or stop code and all four parameters.
   Record the selected boot entry, ISO, hive, loader, kernel, HAL and driver
   hashes. A previous image's fix does not prove the selected image contains it.
2. A FreeLoader menu proves BIOS/loader execution. A missing-hive dialog is
   before kernel loading. The WRK banner establishes kernel startup; it does
   not establish driver initialization or native user-mode execution.
3. For a kernel stop, use the matching `wrkx86.map`/PDB and actual load base.
   Inspect `KiBugCheckData`, the stack, and stage-specific state such as
   `IopInitFailCode` or `ExpInTextModeSetup` before changing dependencies.
4. Package and validate a new image, then observe it in a fresh VM. Confirm the
   earlier failure is passed and record any later failure separately.

[Test-WrkHelloVm.ps1](../tools/Test-WrkHelloVm.ps1) collects screenshots,
registers, optional memory, VM configuration and pre/post hashes. It refuses
an existing VM name or evidence directory. From the repository root, after
building the image described in [boot.md](boot.md):

```powershell
.\tools\Test-WrkHelloVm.ps1 `
  -IsoPath artifacts\wrk-hello-repro\WRK-HelloWorld.iso `
  -Name WRK-HelloWorld-diagnostics-new `
  -EvidenceDirectory artifacts\wrk-hello-diagnostics-new `
  -ObservationSeconds 180 -CaptureCore

python .\tools\Inspect-WrkVmCore.py `
  artifacts\wrk-hello-diagnostics-new\guest.core `
  --registers artifacts\wrk-hello-diagnostics-new\registers.txt `
  --map WRK-V1.2\BASE\NTOS\BUILD\EXE\wrkx86.map `
  --scan-driver-images `
  --output artifacts\wrk-hello-diagnostics-new\core-analysis.json
```

Choose unused names/paths. The runner powers off the disposable VM after
capture. Its default result is conservative: screenshots and memory evidence
must establish greeting execution. The retained success result also includes
a separate native-process audit.

After initialization WRK can discard its PE header/init pages, so the
[core inspector](../tools/Inspect-WrkVmCore.py) may not automatically identify
the kernel. In that case establish the base from the loaded-module list and
matching instruction bytes, then rerun with `--base <actual-address>`.
`0x80528000` is the retained demo's base, not a universal address. A raw stack
scan contains candidate return addresses; corroborate it with frames and code.

## Missing SYSTEM hive, NLS data or imported modules

The normal loader calls `WinLdrInitSystemHive`, tries SYSTEM then SYSTEM.ALT,
selects a control set, and scans registry/NLS/boot drivers before loading WRK.
See [wlregistry.c](../_bootldr/freeldr/freeldr/ntldr/wlregistry.c) and
[winldr.c](../_bootldr/freeldr/freeldr/ntldr/winldr.c). Thus the exact original
`Could not load SYSTEM.ALT hive!` message means both attempts failed; it does
not mean that a healthy SYSTEM always needs a second SYSTEM.ALT file.

**Solution:** verify `SystemPath` points to a real system root containing a
valid `System32\Config\SYSTEM`, its selected control set, registry-named NLS
files, and its boot-driver dependencies. For ordinary WRK x86 startup use a
compatible Server 2003 SP1 guest environment. For the lab use the hive and
RAM-disk packagers in [boot.md](boot.md). Merely placing `wrkx86.exe` and HAL
under the original disc's `payload` directory cannot satisfy the selected
blank-disk system root.

The following are source/build-diagnosable possibilities, **not additional
failures demonstrated by the retained VM runs**:

| Symptom / check | What to inspect | Corrective action |
|---|---|---|
| NLS load error or early kernel fault | Selected `Control\NLS\CodePage` and `Language` values; loader NLS pointers | Supply valid files under the exact registry-selected names. The lab generates `c_1252.nls`, `c_437.nls` and copies `l_intl.nls`. A successful hive read alone does not prove NLS loading. |
| Core DLL missing or imports unresolved | WRK imports `HAL.dll`, `BOOTVID.dll`, `KDCOM.dll`; every selected driver's imports also matter | Stage compatible x86 modules at the selected system root. The selected HAL/kernel physical names may differ from canonical loader module names. `/NODEBUG` or `/NOGUIBOOT` does not remove static DLL imports. |
| Invalid PE image or entry point | Machine type, native subsystem, imports/exports and version/interface compatibility | Rebuild/select the proper x86 binary and its matching dependency set. `0xC000007B` is `STATUS_INVALID_IMAGE_FORMAT`; `0xC0000139` is `STATUS_ENTRYPOINT_NOT_FOUND`. Filename equality alone does not establish compatibility. |
| Kernel loads but cannot reach boot volume | Boot-start Services, GroupOrderList/ServiceGroupOrder, actual device path and drivers | Supply the kernel-side storage/filesystem stack for that medium. FreeLoader's filesystem reader stops serving WRK after handoff. RAM-disk boot needs RAMDISK plus CDFS in this configuration. |

Use [Verify-WrkHelloIso.ps1](../tools/Verify-WrkHelloIso.ps1) for ISO/payload
checks and [verify_build.py](../hello_world/verify_build.py) for native demo
PE/syscall checks. NTSTATUS constants are in
[NTSTATUS.H](../WRK-V1.2/PUBLIC/SDK/INC/NTSTATUS.H); runtime inventory and import
evidence are in [components.md](components.md) and [dependency.md](../dependency.md).

## SYSTEM_LICENSE_VIOLATION (0x9A)

The retained normal-mode stop is:

```text
SYSTEM_LICENSE_VIOLATION
0x0000009A (0x00000004, 0xC0000034, 0x00000000, 0x00000000)
```

Parameter 1 selects the reason. Here subcode 4 identifies a missing
`SystemPrefix` value under `\Registry\Machine\System\Setup`; parameter 2 is
`STATUS_OBJECT_NAME_NOT_FOUND`. The exact generated/staged hive omits that
value. This diagnosis follows the parameters and hive contents, rather than
assuming every 0x9A is the same problem. See WRK's
[BUGCODES.TXT](../WRK-V1.2/PUBLIC/INTERNAL/BASE/INC/BUGCODES.TXT) and
[Microsoft's 0x9A parameter reference](https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/bug-check-0x9a--system-license-violation).

**Solution for ordinary installed-system startup:** restore/use a valid
compatible installation's SYSTEM and associated setup/product state inside
the guest. A generated empty value, ReactOS placeholder, or unrelated modern
Windows hive is not a verified substitute. No valid populated SystemPrefix
was found in the experiment's inputs, so a normal-mode repair is not claimed.

**Verified path for this setup lab:** select explicit NT 5.2 text-mode setup
consistently in the loader, generated hives and packager. WRK initializes
`ExpInTextModeSetup` from `LoaderBlock->SetupLdrBlock->Flags` in
[INITOS.C](../WRK-V1.2/BASE/NTOS/INIT/INITOS.C). `/MININT` alone does not set it.
[Build-WrkSetupLoader.ps1](../tools/Build-WrkSetupLoader.ps1) builds the separate
loader with corrected setup ABI; its assertions require remote-boot flag
`0x1`, text-mode flag `0x2`, and i386 `Flags` offset `0x22c`.
[New-WrkHelloHives.ps1](../tools/New-WrkHelloHives.ps1) and
[New-WrkHelloIso.ps1](../tools/New-WrkHelloIso.ps1) both need `-TextModeSetup`.
The core confirms `ExpInTextModeSetup = 1` in the setup experiment. This uses
the existing kernel setup path; it does not establish valid normal installed
license state or patch the kernel's checks. Use the full recipe in
[boot.md](boot.md#reproduce-the-current-native-demo).

Other 0x9A parameters require their own diagnosis:

| Parameter 1 | Meaning to investigate | Repair direction |
|---|---|---|
| `2` | Setup key cannot be opened | Restore compatible Setup registry state; inspect parameter 2 status. |
| `3` | Setup-mode detection fails; WRK describes missing SetupType | Restore matching setup state; verify expected value names/types. |
| `4` | SystemPrefix missing | Resolve installed-state dependency or use the explicit setup experiment above. |
| `6`, `7` | ProductOptions open or ProductType read failed | Restore matching product configuration and inspect parameter 2 status. |
| `0`, `1`, `5`, `0A` | Product/evaluation/processor policy inconsistency | Restore original compatible installation state rather than inventing values. |
| Other values | Notification, worker, suite or allocation failures | Decode the exact parameters using the WRK/Microsoft table and trace that path. |

The kernel is built partly from supplied opaque libraries; not every licensing
routine has WRK source. The parameters, actual hive, setup flag and binary
evidence are the basis for the diagnosis here.

## IO1_INITIALIZATION_FAILED (0x69)

`Phase1InitializationDiscard` calls `ExInitSystemPhase2`, then `IoInitSystem`.
If the latter returns FALSE, it calls `KeBugCheck(IO1_INITIALIZATION_FAILED)`
without status arguments. Therefore four zero parameters do not identify the
cause. This agrees with
[Microsoft's 0x69 reference](https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/bug-check-0x69--io1-initialization-failed).
The specific failing stage must come from source/state, as in this trace:

```text
IoInitSystem
  IopInitializePlugPlayServices(LoaderBlock, 0)
    IopPortInitialize
      ArbInitializeArbiterInstance
        ArbBuildAssignmentOrdering
          ZwOpenKey(...\CurrentControlSet\Control\Arbiters)
```

The setup run has `IopInitFailCode = 4`. Its root-port arbiter reaches ordering
buffer setup, but ordering counts remain zero and later root arbiters remain
uninitialized. The actual packaged hive lacks the entire `Control\Arbiters`
tree. The precise failing NTSTATUS was not captured; a missing-name status is
an inference from the missing key and inspected code, not a bugcheck parameter.

**Verified solution:** the hive generator includes six complete seed records
from [hivesys.inf](../_bootldr_ex/boot/bootdata/hivesys.inf): allocation-order
requirements for `Root`/`Pci`, reservation data and aliases. An empty Arbiters
key would still leave subsequent value queries unsatisfied. Regenerate the
setup hives with the current script, package them into a new image and validate
it. The arbiter rerun confirms signatures and populated ordering lists for all
five root arbiters and progress past phase 0. Its later 0x19 is a separate fault.

Evidence: hive audit (`artifacts/wrk-hello-20261003-setup/verification/hive-arbiters-audit.json`),
source/binary trace (`artifacts/wrk-hello-20261003-setup/verification/io-init-trace/io-init-evidence.json`),
repaired hive validation (`artifacts/wrk-hello-hives-setup-arbiters/verification/arbiter-hive-validation.json`),
and rerun PnP state (`artifacts/wrk-hello-20261003-setup-arbiters/verification/loader-pnp-audit.json`).

### Other I/O initialization branches

[IOINIT.C](../WRK-V1.2/BASE/NTOS/IO/IOMGR/IOINIT.C) assigns the following
`IopInitFailCode` values. These are WRK-specific diagnostic markers, not
parameters of 0x69 or universal Windows error numbers.

| Marker | Failing operation | Investigation / corrective dependency |
|---|---|---|
| `0` | Initial value; also possible on an unmarked failure path | Check actual stack/status. Zero by itself is not proof of success. |
| `1` | Reserve IRP allocator | Check allocation failure and memory/loader configuration. |
| `2` | I/O object types | Inspect object-manager initialization/allocation. |
| `3` | I/O root directories | Inspect object namespace and returned status. |
| `4` | PnP phase 0 | Check arbiter registry data and root/HAL initialization. |
| `5` | PnP phase 1 / firmware mapper | Check loader hardware data and PnP mapping. |
| `6` | Boot driver initialization | Inspect the failing DriverEntry, service order and driver imports. |
| `7` | `PsLocateSystemDll(FALSE)` | Check `System32\ntdll.dll`, filesystem reachability and image compatibility. |
| `8` | System driver initialization | Inspect selected system-start services and failing driver. |
| `9` | Reassigning SystemRoot | Check ARC boot device mapping and accessible kernel device path. |
| `10` | System partition protection | Inspect boot/system partition metadata and path. |
| `11`, `12` | SystemRoot ANSI/Unicode conversion | Check NLS tables, string state and allocation status. |
| `13` | Optional IRP stack profiler | Inspect profiler initialization and allocation. |

Set a breakpoint at the failing return with the matching symbols to capture
its NTSTATUS before unwinding. Source-derived marker values narrow the stage;
they do not alone prove its root cause.

## BAD_POOL_HEADER (0x19): RAMDISK PnP completion

The repaired-arbiter run stops with subcode `0x20`. The stack ends in
`IopQueryDeviceResources -> ExFreePoolWithTag -> KeBugCheckEx` during PnP
resource assignment. It attempts to free `0x806A6907`, an address inside kernel
code, so code bytes are interpreted as a pool header. Subcode `0x20` identifies
a corrupt pool block size; the invalid-pointer cause here is established by
the local core and driver audit, rather than by the code alone. See
[Microsoft's 0x19 reference](https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/bug-check-0x19--bad-pool-header).

The affected PDO belongs to `\Driver\ramdisk`. Its unsupported
`FILTER_RESOURCE_REQUIREMENTS` request arrives with `STATUS_NOT_SUPPORTED`.
The original default PnP path returns the successful remove-lock status without
completing the IRP, allowing the kernel to consume an uninitialized result
pointer. A legacy-bus-information request is also left outstanding.

**Verified solution:** [Build-WrkRuntime.ps1](../tools/Build-WrkRuntime.ps1)
creates an isolated `ramdisk.c` override that:

- Saves and returns the incoming IRP status for resource queries before
  completion frees the IRP.
- Completes unsupported child-PDO PnP requests with that incoming status.
- Completes both child-PDO StartDevice paths before returning.
- Clears `DO_DEVICE_INITIALIZING` using `&= ~DO_DEVICE_INITIALIZING` after
  device creation; the original expression retained that flag.

Dedicated helpers that already complete requests and bus forwarding keep
their existing behavior. Rebuild with `-Targets ramdisk`, then package with
the repaired setup hives and setup loader. The script applies the override
through CMake and records hashes; it does not modify the sibling source or
WRK kernel. The flag correction was part of the earlier runtime preparation;
the captured 0x19 specifically identified the later completion/status defect.

Evidence: failing PDO/IRP audit (`artifacts/wrk-hello-20261003-setup-arbiters/verification/failing-device-audit.json`),
original driver snapshot (`artifacts/wrk-hello-20261003-setup-arbiters/verification/ramdisk-before-pnp-fix.c`),
fixed runtime provenance (`artifacts/wrk-hello-20261003-setup-pnp/runtime-provenance.json`),
and latest native audit (`artifacts/wrk-hello-20261003-setup-pnp/verification/native-smss-audit.json`).

## Native-process startup failures

The following paths are visible in
[INITOS.C](../WRK-V1.2/BASE/NTOS/INIT/INITOS.C) and
[PSINIT.C](../WRK-V1.2/BASE/NTOS/PS/PSINIT.C). They are troubleshooting guidance,
not stops observed in the current successful demo.

| Failure | Trigger | Solution / diagnostic direction |
|---|---|---|
| `SESSION1_INITIALIZATION_FAILED` (`0x6D`) | Creating initial process parameters fails | Inspect parameter 1 status and memory/string setup. |
| `SESSION2_INITIALIZATION_FAILED` (`0x6E`) | Environment allocation fails, or initial process configuration has invalid type/length | Inspect parameter 1 status; restore correct Session Manager initial command configuration when extra type/length parameters identify that branch. |
| `SESSION3_INITIALIZATION_FAILED` (`0x6F`) | `RtlCreateUserProcess` fails | Inspect parameter 1 status, SMSS native PE, NTDLL exports, image path and filesystem access. |
| `SESSION4_INITIALIZATION_FAILED` (`0x70`) | Resuming initial thread fails | Inspect parameter 1 status and created process/thread state. |
| `SESSION5_INITIALIZATION_FAILED` (`0x71`) | Initial process terminates during WRK's five-second startup wait | Keep the demo SMSS alive after printing; investigate why its loader/program terminated. This call carries no status arguments. |
| `Minimal NTDLL: bootstrap failed; process stopped.` | `MiniLdrFatal` after image bootstrap failure | Inspect import binding, relocations, PEB/context, protections and syscall ABI. It terminates the initial native process and can lead to the preceding 0x71 path. |
| Native greeting absent without a stop | Display failure, wrong image/entry, or insufficient observation | Inspect `SmssDisplayStatus`, live SMSS, bound imports and screenshots over time. WRK VGA startup took tens of seconds in retained VirtualBox runs. |

[smss.c](../hello_world/smss/smss.c) prints through `NtDisplayString`, records
its returned status, and sleeps indefinitely through `NtDelayExecution`.
[ntdll.c](../hello_world/ntdll/ntdll.c) supplies only this demo's native startup
and syscall surface. Successful compilation of the demo does not make it a
general NTDLL or Session Manager implementation.

## Build, packaging and VM preflight errors

| Error / rejected input | Solution |
|---|---|
| Missing build output directories or nmake `U1077` | Run `python PREBUILD.PY` and the bundled x86 build. Inspect the first compiler/tool error preceding U1077; check the README's path-without-spaces requirement. |
| Missing sibling ReactOS/runtime tools | Provide the full checkout through `-ReactOSRoot`; satisfy the script's MSVC/CMake/Ninja/WinFlexBison prerequisites. `_bootldr_ex` alone has no RAMDISK/CDFS sources. |
| Missing `mkhive.exe` / `txt2nls.exe` | Build `_bootldr_ex`'s `bootldr_data` host/data target as described in its [README](../_bootldr_ex/README.md). |
| Setup loader/hive hash mismatch | Rebuild the matching inputs and package their recorded manifests together. Preserve provenance; do not mix stale binaries with a newer manifest. |
| ISO validation fails | Repair the missing/mismatched staged file or boot catalog and rebuild. Validation covers packaging integrity, not runtime compatibility. |
| VM name/evidence directory already exists | Choose a fresh `WRK-HelloWorld-*` name and unused evidence directory under `artifacts`. Preserve the earlier evidence for comparison. |
| VirtualBox exits unsuccessfully | Inspect `vbox-commands.log` and `VBox.log` before changing settings; reproduce the recorded BIOS/PIIX/512 MB/one-CPU configuration. |

See [README.MD](../README.MD), [FREELOADER.md](FREELOADER.md),
[VIRTUALBOX.md](VIRTUALBOX.md), and the linked build scripts for prerequisites.
Keep kernel/HAL replacement and legacy boot configuration inside the guest.

## Evidence needed to call a repair successful

The retained success image is
WRK-HelloWorld.iso (`artifacts/wrk-hello-20261003-setup-pnp/WRK-HelloWorld.iso`).
Its greeting screenshot (`artifacts/wrk-hello-20261003-setup-pnp/verification/screen-final.png`)
is corroborated by SMSS/NTDLL code matching staged files, bound native imports,
and `NtDisplayString` returning success in the
native audit (`artifacts/wrk-hello-20261003-setup-pnp/verification/native-smss-audit.json`).
The core analysis (`artifacts/wrk-hello-20261003-setup-pnp/verification/core-analysis.json`)
has zero bugcheck data and a CPU in `KiIdleLoop`. The
integrity audit (`artifacts/wrk-hello-20261003-setup-pnp/verification/source-integrity.json`)
matches the eight recorded baseline file hashes.

These observations support the lab's repaired startup path. They do not
validate ordinary installed license state, every filesystem operation, every
driver, or full Windows logon. Further failures should be recorded with a new
image/evidence path, exact parameters, source-backed diagnosis, repair, and
rerun result, keeping the distinction between captured facts and inference.
