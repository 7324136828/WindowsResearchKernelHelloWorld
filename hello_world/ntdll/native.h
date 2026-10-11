#ifndef WRK_HELLO_NTDLL_NATIVE_H
#define WRK_HELLO_NTDLL_NATIVE_H

/* Independent, minimal x86 declarations; no Windows SDK or C runtime needed. */
#if !defined(_M_IX86)
#error This bootstrap library supports x86 WRK only.
#endif

typedef unsigned char UCHAR;
typedef unsigned char BOOLEAN;
typedef unsigned short USHORT;
typedef unsigned short WCHAR;
typedef unsigned long ULONG;
typedef long NTSTATUS;
typedef void *PVOID;
typedef void *HANDLE;

typedef union _LARGE_INTEGER {
    struct {
        ULONG LowPart;
        long HighPart;
    } Parts;
    __int64 QuadPart;
} LARGE_INTEGER;

typedef struct _UNICODE_STRING {
    USHORT Length;
    USHORT MaximumLength;
    WCHAR *Buffer;
} UNICODE_STRING;

#define NT_SUCCESS(Status) ((NTSTATUS)(Status) >= 0)
#define STATUS_SUCCESS ((NTSTATUS)0)
#define STATUS_INVALID_IMAGE_FORMAT ((NTSTATUS)0xC000007BL)
#define STATUS_NOT_SUPPORTED ((NTSTATUS)0xC00000BBL)
#define STATUS_ENTRYPOINT_NOT_FOUND ((NTSTATUS)0xC0000139L)
#define CURRENT_PROCESS ((HANDLE)-1)

NTSTATUS __stdcall NtContinue(PVOID Context, BOOLEAN TestAlert);
NTSTATUS __stdcall NtDelayExecution(BOOLEAN Alertable, LARGE_INTEGER *Interval);
NTSTATUS __stdcall NtDisplayString(UNICODE_STRING *String);
NTSTATUS __stdcall NtProtectVirtualMemory(HANDLE Process, PVOID *Base,
    ULONG *RegionSize, ULONG Protection, ULONG *OldProtection);
NTSTATUS __stdcall NtRaiseException(PVOID Record, PVOID Context,
    BOOLEAN FirstChance);
NTSTATUS __stdcall NtTerminateProcess(HANDLE Process, NTSTATUS ExitStatus);

__declspec(noreturn) void __stdcall MiniLdrInitializeThunk(PVOID Context,
    PVOID DllBase);
__declspec(noreturn) void __stdcall MiniLdrFatal(NTSTATUS Status);

#endif
