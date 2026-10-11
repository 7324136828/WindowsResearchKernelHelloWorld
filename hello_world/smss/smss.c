#include "native.h"

/* Inspect this in a debugger if the greeting is not visible. */
volatile NTSTATUS SmssDisplayStatus = (NTSTATUS)0x00000103L;

/*
 * WRK's RtlInitializeContext supplies the PEB pointer in the initial user
 * context, which NTDLL resumes after loader initialization. No main(),
 * console, Win32 subsystem, or C runtime is involved.
 */
void __stdcall NtProcessStartup(PPEB Peb)
{
    static WCHAR message[] = L"Hello world from WRK SMSS!\n";
    UNICODE_STRING text;
    LARGE_INTEGER delay;

    (void)Peb;
    text.Length = (USHORT)(sizeof(message) - sizeof(message[0]));
    text.MaximumLength = (USHORT)sizeof(message);
    text.Buffer = message;

    /* Relative NT time is negative, in units of 100 nanoseconds. */
    delay.QuadPart = -10000000i64;

    /* WRK enables boot display output just after it resumes this thread. */
    (void)NtDelayExecution((BOOLEAN)0, &delay);
    SmssDisplayStatus = NtDisplayString(&text);

    /*
     * WRK bugchecks if its initial SMSS exits during the five-second
     * startup check. Keep this demo alive even after that check.
     */
    for (;;) {
        (void)NtDelayExecution((BOOLEAN)0, &delay);
    }
}
