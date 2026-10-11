; Kernel-entered x86 trampolines. No CRT startup or Win32 dependencies.
.386
.model flat
option casemap:none

extrn _MiniLdrInitializeThunk@8:proc
extrn _MiniLdrFatal@4:proc
extrn _NtContinue@8:proc
extrn _NtRaiseException@12:proc

.code

public _KiUserApcDispatcher
_KiUserApcDispatcher proc
    ; WRK KE/I386/APCUSER.C builds KAPC_RECORD (four DWORDs), then CONTEXT:
    ; [esp] Routine, +4 NormalContext, +8 Argument1, +12 Argument2, +16 CONTEXT.
    pop eax
    call eax
    ; The stdcall APC routine consumed three arguments, leaving CONTEXT at ESP.
    mov eax, esp
    push 1
    push eax
    call _NtContinue@8
    push eax
    call _MiniLdrFatal@4
_KiUserApcDispatcher endp

public _LdrInitializeThunk@12
_LdrInitializeThunk@12 proc
    ; CREATE.C queues the loader with NormalContext=NULL, Argument1=DllBase.
    ; At this call entry: return address, three APC arguments, then CONTEXT.
    lea eax, [esp + 16]
    mov edx, [esp + 8]
    push edx
    push eax
    call _MiniLdrInitializeThunk@8
    ; The C bootstrap always continues the original context or stops on error.
    push 0C00000BBh
    call _MiniLdrFatal@4
_LdrInitializeThunk@12 endp

public _KiUserExceptionDispatcher
_KiUserExceptionDispatcher proc
    ; EXCEPTN.C enters without a return address: [esp] exception, +4 CONTEXT.
    ; No frame-based SEH is supplied. Report an unhandled, second-chance fault.
    mov eax, [esp]
    mov edx, [esp + 4]
    push 0
    push edx
    push eax
    call _NtRaiseException@12
    push eax
    call _MiniLdrFatal@4
_KiUserExceptionDispatcher endp

public _KiUserCallbackDispatcher
_KiUserCallbackDispatcher proc
    push 0C00000BBh
    call _MiniLdrFatal@4
_KiUserCallbackDispatcher endp

public _KiRaiseUserExceptionDispatcher
_KiRaiseUserExceptionDispatcher proc
    push 0C00000BBh
    call _MiniLdrFatal@4
_KiRaiseUserExceptionDispatcher endp

; KULOOKUP.C insists these symbols exist. This pair never uses SLIST routines;
; each unsupported entry stops explicitly rather than pretending to implement it.
public _ExpInterlockedPopEntrySListResume
_ExpInterlockedPopEntrySListResume proc
    push 0C00000BBh
    call _MiniLdrFatal@4
_ExpInterlockedPopEntrySListResume endp

public _ExpInterlockedPopEntrySListFault
_ExpInterlockedPopEntrySListFault proc
    push 0C00000BBh
    call _MiniLdrFatal@4
_ExpInterlockedPopEntrySListFault endp

public _ExpInterlockedPopEntrySListEnd
_ExpInterlockedPopEntrySListEnd proc
    push 0C00000BBh
    call _MiniLdrFatal@4
_ExpInterlockedPopEntrySListEnd endp

; WRK installs these addresses into KUSER_SHARED_DATA depending on CPU features.
; Calls through that shared pointer add one return address to the syscall stack.
public _KiFastSystemCall
public _KiFastSystemCallRet
_KiFastSystemCall proc
    mov edx, esp
    ; Bundled legacy ML does not recognize SYSENTER: encode its 0F 34 opcode.
    db 0fh, 34h
_KiFastSystemCallRet::
    ret
_KiFastSystemCall endp

public _KiIntSystemCall
_KiIntSystemCall proc
    lea edx, [esp + 8]
    int 2eh
    ret
_KiIntSystemCall endp

end
