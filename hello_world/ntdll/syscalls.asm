; Minimal NT5.2 x86 syscall wrappers. The build script generates the service
; indices from this checkout's KE/I386/SYSTABLE.ASM, not host Windows values.
.386
.model flat
option casemap:none

include wrk_syscalls.inc

.code

NATIVE_SYSCALL macro Symbol, Service, ArgumentBytes
    public Symbol
Symbol proc
    mov eax, Service
    ; INT 2E works on WRK without assuming SYSENTER support. EDX points to the
    ; first argument (unlike KiIntSystemCall, there is no extra CALL frame).
    lea edx, [esp + 4]
    int 2eh
    ret ArgumentBytes
Symbol endp
endm

NATIVE_SYSCALL _NtContinue@8, WRK_NTCONTINUE, 8
NATIVE_SYSCALL _NtDelayExecution@8, WRK_NTDELAYEXECUTION, 8
NATIVE_SYSCALL _NtDisplayString@4, WRK_NTDISPLAYSTRING, 4
NATIVE_SYSCALL _NtProtectVirtualMemory@20, WRK_NTPROTECTVIRTUALMEMORY, 20
NATIVE_SYSCALL _NtRaiseException@12, WRK_NTRAISEEXCEPTION, 12
NATIVE_SYSCALL _NtTerminateProcess@8, WRK_NTTERMINATEPROCESS, 8

end
