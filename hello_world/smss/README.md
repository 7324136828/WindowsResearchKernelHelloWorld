# Minimal native SMSS

`smss.c` builds as the x86 native-subsystem executable `smss.exe` through
`..\build.cmd`. Its entry point prints `Hello world from WRK SMSS!` with
`NtDisplayString`, then sleeps repeatedly with `NtDelayExecution` to keep
the initial process alive. A one-second delay before the greeting gives WRK
time to enable boot display output. Both functions are imported from
`ntdll.dll`. The debugger-visible `SmssDisplayStatus` records the display
call's NTSTATUS; it starts as `STATUS_PENDING` (`0x00000103`).

This is a boot experiment, not a Windows Session Manager implementation.
It does not initialize sessions, CSRSS, WINLOGON, or a usable Windows desktop.
Its message requires WRK to reach user-mode initialization with working boot
drivers and boot-video support. The sibling NTDLL sample has a deliberately
limited ABI; see `..\README.md` for compatibility and deployment details.

Keep deployment inside a disposable guest. Do not replace the host's SMSS.
