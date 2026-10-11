# Minimal WRK NTDLL bootstrap

This is an experimental **x86 WRK-specific** DLL for the native hello-world
application in `../smss`. It is not a general replacement for Windows NTDLL.
Build the pair with `../Build-HelloWorld.ps1`; its output here is `ntdll.dll`.
Do not copy this DLL to the host operating system's Windows directories.

The build uses the WRK x86 service table to generate syscall numbers. Its six
system-call wrappers use `INT 2E` and the x86 `__stdcall` convention. No C runtime,
Win32 DLL, Windows SDK headers, or imported DLL is needed by this library.

The DLL exports undecorated Native API names. The bundled linker's generated
import library uses those names as COFF symbols; the build script adds explicit
linker aliases for the sample's two `__stdcall` IAT references. This preserves
the correct x86 calling convention and undecorated PE import names.

## What startup does

1. WRK maps the process executable and NTDLL, then delivers an initial user APC.
2. `KiUserApcDispatcher` calls `LdrInitializeThunk`, which obtains the original
   `CONTEXT` from the APC stack and the already mapped DLL base from its argument.
3. The small loader reads `PEB.ImageBaseAddress`, accepts only named imports from
   `ntdll.dll`, resolves them against this DLL's PE export table, temporarily
   makes the IAT writable with `NtProtectVirtualMemory`, and restores protection.
4. `NtContinue` resumes the original process context. WRK's
   `RtlInitializeContext` already set the executable entry address and its PEB
   stack argument. The native hello-world entry can then call its resolved imports.

The executable and DLL must map at their preferred addresses. Relocations, TLS,
delay imports, ordinal imports, other DLLs, DLL initialization callbacks, loader
lists, process heaps, general exception handling, and Windows subsystems are not
implemented. The adjacent sample avoids those features. This bootstrap is
designed for the first native process; it supplies no complete thread lifecycle.

## Kernel-required exports

`ntdll.def` also exposes the names WRK looks up during system DLL initialization:

- `LdrInitializeThunk`
- `KiUserApcDispatcher`, `KiUserExceptionDispatcher`
- `KiUserCallbackDispatcher`, `KiRaiseUserExceptionDispatcher`
- `ExpInterlockedPopEntrySListResume`, `ExpInterlockedPopEntrySListFault`,
  `ExpInterlockedPopEntrySListEnd`
- `KiFastSystemCall`, `KiFastSystemCallRet`, `KiIntSystemCall`

User APC delivery and the syscall trampolines are implemented for the narrow
sample. The retained setup-mode RAM-disk run verifies that this NTDLL starts
the native SMSS demo; the historical native execution audit was generated at
`artifacts/wrk-hello-20261003-setup-pnp/verification/native-smss-audit.json`
and [boot guide](../../docs/boot.md). Broader Windows NTDLL behavior is not established.
Unhandled exceptions are sent to WRK as second-chance exceptions through
`NtRaiseException`; no user SEH handlers are run. Callback, raised-exception, and
SLIST placeholder entries explicitly stop the process with `STATUS_NOT_SUPPORTED`.
They are not implementations of those Windows facilities.

A bootstrap failure prints a short diagnostic and terminates the native process.
If this is the initial session-manager process, WRK may bugcheck as part of its
startup failure handling. A successful hello-world sample stays alive instead.

## Local source evidence

- `WRK-V1.2/base/ntos/ps/PSINIT.C`: maps NTDLL and looks up `LdrInitializeThunk`.
- `WRK-V1.2/base/ntos/ps/KULOOKUP.C`: required trampoline export names.
- `WRK-V1.2/base/ntos/ps/CREATE.C`: initial loader APC arguments.
- `WRK-V1.2/base/ntos/ke/i386/APCUSER.C`: `KAPC_RECORD` followed by `CONTEXT`.
- `WRK-V1.2/base/ntos/rtl/i386/CONTEXT.C`: entry address and stack parameter.
- `WRK-V1.2/base/ntos/rtl/RTLEXEC.C`: passes the PEB to the initial native entry.
- `WRK-V1.2/base/ntos/ke/i386/SYSTABLE.ASM`: zero-based syscall ordering.
- `WRK-V1.2/base/ntos/ke/i386/EXCEPTN.C`: exception dispatcher stack layout.
- `WRK-V1.2/public/sdk/inc/PEBTEB.H`: x86 PEB image-base field.

Building the pair checks its PE structure and linkage. It does not prove a WRK
boot. A compatible SYSTEM hive, HAL, boot drivers, NLS files, and other kernel
startup dependencies described in the repository's `dependency.md` remain
necessary before this DLL or the hello-world process can run.
