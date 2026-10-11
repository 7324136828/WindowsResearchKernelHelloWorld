# Native WRK Hello World

This directory builds two experimental **x86 NT 5.2 native** binaries:

| Output | Role |
|---|---|
| [`smss/smss.exe`](smss/smss.exe) | A first-process demo: waits one second, prints `Hello world from WRK SMSS!`, then sleeps indefinitely |
| [`ntdll/ntdll.dll`](ntdll/ntdll.dll) | Minimal system-call wrappers and startup support for this particular executable |

Both use standalone C/assembly declarations and WRK's bundled compiler;
neither requires Windows SDK headers, a C runtime, KERNEL32, or a Win32
console. The DLL supports binding SMSS's named NTDLL imports and continuing
the initial thread context supplied by WRK. It also exports the names
WRK's process initialization looks up.

## Build

From the repository root:

```bat
hello_world\build.cmd
```

Or use PowerShell:

```powershell
.\hello_world\Build-HelloWorld.ps1
```

The script uses `WRK-V1.2\TOOLS\X86\CL.EXE`, `ML.EXE`, and `LINK.EXE`.
C is compiled with `/W4 /WX`; both outputs are PE32 images with
the Native subsystem version set to 5.2. `/RELEASE` generates the image
checksums used by WRK's image validation. Intermediate objects, import
libraries, maps, and debug symbols go into each component's `build\`
directory. Rebuilding replaces only these demo outputs.

The SMSS link also supplies two `/alternatename` mappings to bridge LINK
7's import-library names to the compiler's stdcall names; the actual DLL
imports remain the undecorated `NtDisplayString` and `NtDelayExecution`.

System-call numbers are generated from
`WRK-V1.2\BASE\NTOS\KE\I386\SYSTABLE.ASM`, including validation of argument
counts. They are specific to this WRK source tree; they are not host
Windows system-call numbers. Rebuild the demo if that table changes.

Inspect the compiled pair with Python 3 (standard library only):

```bat
py hello_world\verify_build.py
```

This checks the x86/native headers, entry points, checksums, SMSS imports,
absence of NTDLL imports, required kernel exports, and the compiled syscall
instructions against WRK's table. Results are written to
`hello_world\verification.json`.

## How the demonstration would run

The [RAM-disk boot experiment](../docs/WRK_HELLO_BOOT.md) packages this pair
with WRK and rebuilt runtime components. Its VirtualBox test confirms WRK
kernel startup. The setup-mode, arbiter-registry and RAMDISK PnP completion
fixes pass the earlier stops. The latest VirtualBox test displays
`Hello world from WRK SMSS!`, verifying this native demo's startup and greeting.

WRK opens `\SystemRoot\System32\ntdll.dll` and maps it into the initial
process. Its initial user APC enters `KiUserApcDispatcher`, which calls
`LdrInitializeThunk`. The small loader binds the executable's imports to
this already mapped NTDLL, then `NtContinue` resumes the original context
at SMSS's `NtProcessStartup` entry point.

SMSS waits briefly for WRK to enable boot display output, calls
`NtDisplayString` with a Unicode greeting, and remains alive with
`NtDelayExecution`. The status of the print call is retained in
`SmssDisplayStatus` for debugger inspection. Remaining alive avoids WRK's
`SESSION5_INITIALIZATION_FAILED` check when the initial process exits
during its first five seconds.

For a future test, place both files in **a disposable guest's** selected
`System32` directory after preserving its original files. The boot-video
path must still be present and available; use `/SOS` and avoid
`/NOGUIBOOT`. These are native boot components, so double-clicking SMSS or
copying either file into the host Windows directory is not a test of this
experiment.

## Scope and verification limits

The sample replaces the initial process only for a greeting demonstration.
It does not implement Windows Session Manager, start CSRSS/WINLOGON,
initialize a desktop, or provide a usable Windows session.

The minimal NTDLL supports only this pair at its preferred image addresses
(`smss.exe`: `0x00400000`; `ntdll.dll`: `0x7c900000`). It does not provide a
general DLL loader, relocation processing, TLS, process heaps, or complete
exception/callback/thread support. Some kernel-required exports are
explicit unsupported-operation handlers. See
[`ntdll/README.md`](ntdll/README.md) and [`smss/README.md`](smss/README.md)
for details.

**Compilation and binary checks do not establish guest execution.** These
two components are used after WRK's registry, NLS, HAL, filesystem and boot
drivers have initialized. They cannot fix the current ISO's earlier
`Could not load SYSTEM.ALT hive!` failure. See
[`dependency.md`](../dependency.md) for those requirements. The ISO and
kernel are not modified by this build.
