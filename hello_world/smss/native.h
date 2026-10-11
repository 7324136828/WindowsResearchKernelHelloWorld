#ifndef WRK_HELLO_SMSS_NATIVE_H
#define WRK_HELLO_SMSS_NATIVE_H

/* The x86 NT ABI, without the Windows SDK or a C runtime dependency. */
typedef signed long NTSTATUS;
typedef unsigned char BOOLEAN;
typedef unsigned short USHORT;
typedef unsigned short WCHAR;

typedef struct _UNICODE_STRING {
    USHORT Length;
    USHORT MaximumLength;
    WCHAR *Buffer;
} UNICODE_STRING, *PUNICODE_STRING;

typedef union _LARGE_INTEGER {
    struct {
        unsigned long LowPart;
        signed long HighPart;
    } Parts;
    __int64 QuadPart;
} LARGE_INTEGER, *PLARGE_INTEGER;

typedef struct _PEB *PPEB;

__declspec(dllimport) NTSTATUS __stdcall NtDisplayString(
    PUNICODE_STRING String);

__declspec(dllimport) NTSTATUS __stdcall NtDelayExecution(
    BOOLEAN Alertable,
    PLARGE_INTEGER DelayInterval);

#endif
