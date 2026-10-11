#include "native.h"

/*
 * A bootstrap for the adjacent SMSS hello-world image, not a Windows NTDLL.
 * WRK maps the executable and this DLL before delivering its initial user APC.
 * We bind only imports from this already mapped DLL, then resume the original
 * x86 CONTEXT with NtContinue. No DLL search, heap, SEH, TLS, or CRT is provided.
 */

#define IMAGE_DIRECTORY_EXPORT 0
#define IMAGE_DIRECTORY_IMPORT 1
#define IMAGE_DIRECTORY_TLS 9
#define IMAGE_DIRECTORY_DELAY_IMPORT 13
#define PAGE_READWRITE 4

typedef struct _IMAGE_VIEW {
    UCHAR *Base;
    ULONG Size;
    ULONG PreferredBase;
    ULONG Directories;
    ULONG DirectoryCount;
} IMAGE_VIEW;

static USHORT Read16(const UCHAR *Address)
{
    return *(const USHORT *)Address;
}

static ULONG Read32(const UCHAR *Address)
{
    return *(const ULONG *)Address;
}

static int InImage(const IMAGE_VIEW *Image, ULONG Rva, ULONG Length)
{
    return Rva <= Image->Size && Length <= Image->Size - Rva;
}

static NTSTATUS ReadImage(PVOID Base, IMAGE_VIEW *Image)
{
    UCHAR *Bytes = (UCHAR *)Base;
    ULONG NtOffset;
    ULONG OptionalSize;
    ULONG ImageSize;
    ULONG Count;

    if (Base == 0 || Read16(Bytes) != 0x5A4D) {
        return STATUS_INVALID_IMAGE_FORMAT;
    }
    NtOffset = Read32(Bytes + 0x3C);
    /* These inputs are the two trusted images mapped by WRK, not raw files. */
    if (NtOffset < 0x40 || NtOffset > 0x1000 ||
        Read32(Bytes + NtOffset) != 0x00004550 ||
        Read16(Bytes + NtOffset + 4) != 0x014C ||
        Read16(Bytes + NtOffset + 24) != 0x010B) {
        return STATUS_INVALID_IMAGE_FORMAT;
    }
    OptionalSize = Read16(Bytes + NtOffset + 20);
    ImageSize = Read32(Bytes + NtOffset + 24 + 56);
    Count = Read32(Bytes + NtOffset + 24 + 92);
    if (OptionalSize < 96 || Count > 16 ||
        Count > (OptionalSize - 96) / 8 ||
        ImageSize < 0x1000 || ImageSize > 0x01000000 ||
        NtOffset + 24 + OptionalSize > ImageSize) {
        return STATUS_INVALID_IMAGE_FORMAT;
    }
    Image->Base = Bytes;
    Image->Size = ImageSize;
    Image->PreferredBase = Read32(Bytes + NtOffset + 24 + 28);
    Image->Directories = NtOffset + 24 + 96;
    Image->DirectoryCount = Count;
    return STATUS_SUCCESS;
}

static NTSTATUS Directory(const IMAGE_VIEW *Image, ULONG Index,
    ULONG *Rva, ULONG *Size)
{
    *Rva = 0;
    *Size = 0;
    if (Index < Image->DirectoryCount) {
        *Rva = Read32(Image->Base + Image->Directories + Index * 8);
        *Size = Read32(Image->Base + Image->Directories + Index * 8 + 4);
    }
    if (!InImage(Image, *Rva, *Size) || (*Rva == 0 && *Size != 0)) {
        return STATUS_INVALID_IMAGE_FORMAT;
    }
    return STATUS_SUCCESS;
}

static const char *ImageString(const IMAGE_VIEW *Image, ULONG Rva)
{
    ULONG End;
    if (!InImage(Image, Rva, 1)) {
        return 0;
    }
    for (End = Rva; End < Image->Size; ++End) {
        if (Image->Base[End] == 0) {
            return (const char *)(Image->Base + Rva);
        }
    }
    return 0;
}

static int SameString(const char *Left, const char *Right, int FoldCase)
{
    UCHAR A;
    UCHAR B;
    do {
        A = (UCHAR)*Left++;
        B = (UCHAR)*Right++;
        if (FoldCase) {
            if (A >= 'A' && A <= 'Z') A = (UCHAR)(A + ('a' - 'A'));
            if (B >= 'A' && B <= 'Z') B = (UCHAR)(B + ('a' - 'A'));
        }
        if (A != B) return 0;
    } while (A != 0);
    return 1;
}

static NTSTATUS FindExport(const IMAGE_VIEW *Dll, const char *Name,
    ULONG *Address)
{
    ULONG Rva;
    ULONG Size;
    ULONG Count;
    ULONG FunctionCount;
    ULONG Names;
    ULONG Ordinals;
    ULONG Functions;
    ULONG Index;
    ULONG Ordinal;
    ULONG Function;
    const char *Candidate;
    NTSTATUS Status;

    Status = Directory(Dll, IMAGE_DIRECTORY_EXPORT, &Rva, &Size);
    if (!NT_SUCCESS(Status) || Rva == 0 || Size < 40) {
        return STATUS_INVALID_IMAGE_FORMAT;
    }
    FunctionCount = Read32(Dll->Base + Rva + 20);
    Count = Read32(Dll->Base + Rva + 24);
    Functions = Read32(Dll->Base + Rva + 28);
    Names = Read32(Dll->Base + Rva + 32);
    Ordinals = Read32(Dll->Base + Rva + 36);
    if (Count > Dll->Size / 4 || FunctionCount > Dll->Size / 4 ||
        !InImage(Dll, Names, Count * 4) ||
        !InImage(Dll, Ordinals, Count * 2) ||
        !InImage(Dll, Functions, FunctionCount * 4)) {
        return STATUS_INVALID_IMAGE_FORMAT;
    }
    for (Index = 0; Index < Count; ++Index) {
        Candidate = ImageString(Dll, Read32(Dll->Base + Names + Index * 4));
        if (Candidate == 0) return STATUS_INVALID_IMAGE_FORMAT;
        if (!SameString(Name, Candidate, 0)) continue;
        Ordinal = Read16(Dll->Base + Ordinals + Index * 2);
        if (Ordinal >= FunctionCount) return STATUS_INVALID_IMAGE_FORMAT;
        Function = Read32(Dll->Base + Functions + Ordinal * 4);
        if (Function == 0 || !InImage(Dll, Function, 1)) {
            return STATUS_ENTRYPOINT_NOT_FOUND;
        }
        /* Forwarders would require loading another module; reject them. */
        if (Function >= Rva && Function - Rva < Size) {
            return STATUS_NOT_SUPPORTED;
        }
        *Address = (ULONG)(Dll->Base + Function);
        return STATUS_SUCCESS;
    }
    return STATUS_ENTRYPOINT_NOT_FOUND;
}

static NTSTATUS BindThunks(const IMAGE_VIEW *Image, const IMAGE_VIEW *Dll,
    ULONG Source, ULONG Target)
{
    ULONG Count = 0;
    ULONG Index;
    ULONG NameRva;
    ULONG Address;
    ULONG RegionSize;
    ULONG OldProtection;
    ULONG DiscardProtection;
    PVOID Region;
    const char *Name;
    NTSTATUS Status;
    NTSTATUS RestoreStatus;

    if (Source == 0 || Target == 0) return STATUS_INVALID_IMAGE_FORMAT;
    while (Count < Image->Size / 4) {
        if (!InImage(Image, Source, (Count + 1) * 4) ||
            !InImage(Image, Target, (Count + 1) * 4)) {
            return STATUS_INVALID_IMAGE_FORMAT;
        }
        if (Read32(Image->Base + Source + Count * 4) == 0) break;
        ++Count;
    }
    if (Count == 0 || Count == Image->Size / 4) {
        return STATUS_INVALID_IMAGE_FORMAT;
    }
    Region = Image->Base + Target;
    RegionSize = (Count + 1) * 4;
    Status = NtProtectVirtualMemory(CURRENT_PROCESS, &Region, &RegionSize,
        PAGE_READWRITE, &OldProtection);
    if (!NT_SUCCESS(Status)) return Status;

    for (Index = 0; Index < Count; ++Index) {
        NameRva = Read32(Image->Base + Source + Index * 4);
        if ((NameRva & 0x80000000) != 0) {
            Status = STATUS_NOT_SUPPORTED; /* Named imports only. */
            break;
        }
        if (!InImage(Image, NameRva, 3)) {
            Status = STATUS_INVALID_IMAGE_FORMAT;
            break;
        }
        Name = ImageString(Image, NameRva + 2); /* Skip the import hint. */
        if (Name == 0) {
            Status = STATUS_INVALID_IMAGE_FORMAT;
            break;
        }
        Status = FindExport(Dll, Name, &Address);
        if (!NT_SUCCESS(Status)) break;
        *(ULONG *)(Image->Base + Target + Index * 4) = Address;
    }
    RestoreStatus = NtProtectVirtualMemory(CURRENT_PROCESS, &Region,
        &RegionSize, OldProtection, &DiscardProtection);
    return NT_SUCCESS(Status) ? RestoreStatus : Status;
}

static NTSTATUS BindImage(const IMAGE_VIEW *Image, const IMAGE_VIEW *Dll)
{
    ULONG Rva;
    ULONG Size;
    ULONG Offset;
    ULONG Source;
    ULONG Target;
    ULONG NameRva;
    const UCHAR *Descriptor;
    const char *Name;
    NTSTATUS Status;

    if ((ULONG)Image->Base != Image->PreferredBase ||
        (ULONG)Dll->Base != Dll->PreferredBase) {
        return STATUS_NOT_SUPPORTED; /* No relocation implementation. */
    }
    Status = Directory(Image, IMAGE_DIRECTORY_TLS, &Rva, &Size);
    if (!NT_SUCCESS(Status)) return Status;
    if (Rva != 0 || Size != 0) return STATUS_NOT_SUPPORTED;
    Status = Directory(Image, IMAGE_DIRECTORY_DELAY_IMPORT, &Rva, &Size);
    if (!NT_SUCCESS(Status)) return Status;
    if (Rva != 0 || Size != 0) return STATUS_NOT_SUPPORTED;
    Status = Directory(Image, IMAGE_DIRECTORY_IMPORT, &Rva, &Size);
    if (!NT_SUCCESS(Status)) return Status;
    if (Rva == 0 || Size < 20) return STATUS_INVALID_IMAGE_FORMAT;

    for (Offset = 0; Offset <= Size - 20; Offset += 20) {
        Descriptor = Image->Base + Rva + Offset;
        Source = Read32(Descriptor);
        NameRva = Read32(Descriptor + 12);
        Target = Read32(Descriptor + 16);
        if (Source == 0 && NameRva == 0 && Target == 0 &&
            Read32(Descriptor + 4) == 0 && Read32(Descriptor + 8) == 0) {
            return STATUS_SUCCESS;
        }
        Name = ImageString(Image, NameRva);
        if (Name == 0) return STATUS_INVALID_IMAGE_FORMAT;
        if (!SameString(Name, "ntdll.dll", 1)) return STATUS_NOT_SUPPORTED;
        if (Source == 0) Source = Target;
        Status = BindThunks(Image, Dll, Source, Target);
        if (!NT_SUCCESS(Status)) return Status;
    }
    return STATUS_INVALID_IMAGE_FORMAT;
}

__declspec(noreturn) void __stdcall MiniLdrFatal(NTSTATUS Status)
{
    static WCHAR Message[] =
        L"Minimal NTDLL: bootstrap failed; process stopped.\r\n";
    UNICODE_STRING Text;
    LARGE_INTEGER Interval;

    Text.Buffer = Message;
    Text.Length = (USHORT)(sizeof(Message) - sizeof(WCHAR));
    Text.MaximumLength = (USHORT)sizeof(Message);
    NtDisplayString(&Text);
    NtTerminateProcess(CURRENT_PROCESS, Status);
    /* A failed termination must never resume a half-initialized program. */
    Interval.QuadPart = -10000000;
    for (;;) NtDelayExecution(0, &Interval);
}

__declspec(noreturn) void __stdcall MiniLdrInitializeThunk(PVOID Context,
    PVOID DllBase)
{
    PVOID Peb;
    PVOID ImageBase;
    IMAGE_VIEW Image;
    IMAGE_VIEW Dll;
    NTSTATUS Status;

    __asm {
        mov eax, fs:[30h]
        mov Peb, eax
    }
    if (Peb == 0 || Context == 0) MiniLdrFatal(STATUS_INVALID_IMAGE_FORMAT);
    ImageBase = *(PVOID *)((UCHAR *)Peb + 8); /* x86 PEB.ImageBaseAddress. */
    Status = ReadImage(ImageBase, &Image);
    if (!NT_SUCCESS(Status)) MiniLdrFatal(Status);
    Status = ReadImage(DllBase, &Dll);
    if (!NT_SUCCESS(Status)) MiniLdrFatal(Status);
    Status = BindImage(&Image, &Dll);
    if (!NT_SUCCESS(Status)) MiniLdrFatal(Status);

    /* RtlInitializeContext already supplies EIP, ESP, and the PEB argument. */
    Status = NtContinue(Context, 0);
    MiniLdrFatal(Status); /* A successful NtContinue does not return. */
}

int __stdcall NtdllEntry(PVOID Module, ULONG Reason, PVOID Reserved)
{
    (void)Module;
    (void)Reason;
    (void)Reserved;
    return 1;
}
