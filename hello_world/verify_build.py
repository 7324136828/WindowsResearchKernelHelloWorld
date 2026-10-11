"""Inspect the built native pair without executing its WRK-specific syscalls.

Run with Python 3: py hello_world/verify_build.py
Only the Python standard library is needed.
"""

import json
import re
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent


class PE:
    def __init__(self, path):
        self.path = path
        self.data = path.read_bytes()
        assert self.data[:2] == b"MZ", f"{path}: missing MZ signature"
        self.pe = self.u32(0x3C)
        assert self.data[self.pe:self.pe + 4] == b"PE\0\0"
        assert self.u16(self.pe + 4) == 0x14C, "Expected x86 machine"
        self.opt = self.pe + 24
        assert self.u16(self.opt) == 0x10B, "Expected PE32"
        assert self.u16(self.opt + 68) == 1, "Expected native subsystem"
        assert (self.u16(self.opt + 48), self.u16(self.opt + 50)) == (5, 2)
        self.base = self.u32(self.opt + 28)
        self.entry = self.u32(self.opt + 16)
        self.characteristics = self.u16(self.pe + 22)
        self.sections = []
        section_offset = self.opt + self.u16(self.pe + 20)
        for index in range(self.u16(self.pe + 6)):
            at = section_offset + index * 40
            self.sections.append({
                "name": self.data[at:at + 8].split(b"\0")[0].decode("ascii"),
                "rva": self.u32(at + 12),
                "raw_size": self.u32(at + 16),
                "raw": self.u32(at + 20),
                "flags": self.u32(at + 36),
            })

    def u16(self, offset):
        return struct.unpack_from("<H", self.data, offset)[0]

    def u32(self, offset):
        return struct.unpack_from("<I", self.data, offset)[0]

    def offset(self, rva, size=1):
        if rva < self.u32(self.opt + 60) and rva + size <= len(self.data):
            return rva
        for section in self.sections:
            delta = rva - section["rva"]
            if 0 <= delta and delta + size <= section["raw_size"]:
                result = section["raw"] + delta
                assert result + size <= len(self.data)
                return result
        raise AssertionError(f"Unmapped RVA {rva:#x} in {self.path}")

    def string(self, rva):
        start = self.offset(rva)
        end = self.data.index(b"\0", start)
        return self.data[start:end].decode("ascii")

    def directory(self, number):
        return self.u32(self.opt + 96 + number * 8), self.u32(self.opt + 100 + number * 8)

    def exports(self):
        rva, size = self.directory(0)
        if not rva:
            return {}
        at = self.offset(rva, 40)
        function_count, name_count = self.u32(at + 20), self.u32(at + 24)
        functions, names, ordinals = (self.u32(at + field) for field in (28, 32, 36))
        result = {}
        for index in range(name_count):
            name = self.string(self.u32(self.offset(names + index * 4, 4)))
            ordinal = self.u16(self.offset(ordinals + index * 2, 2))
            assert ordinal < function_count
            value = self.u32(self.offset(functions + ordinal * 4, 4))
            assert not rva <= value < rva + size, "Forwarded exports unsupported"
            assert name not in result
            result[name] = value
        return result

    def imports(self):
        rva, size = self.directory(1)
        if not rva:
            return {}
        result = {}
        for index in range(size // 20):
            fields = struct.unpack_from("<5I", self.data, self.offset(rva + index * 20, 20))
            if not any(fields):
                break
            original_thunk, _, _, name_rva, first_thunk = fields
            module = self.string(name_rva).lower()
            entries = []
            thunk = original_thunk or first_thunk
            while True:
                value = self.u32(self.offset(thunk, 4))
                if not value:
                    break
                assert not value & 0x80000000, "Ordinal import unsupported by demo loader"
                entries.append(self.string(value + 2))
                thunk += 4
            assert module not in result
            result[module] = entries
        return result

    def checksum(self):
        checksum_offset = self.opt + 64
        total = 0
        for index in range(0, len(self.data), 2):
            if checksum_offset <= index < checksum_offset + 4:
                continue
            word = self.data[index]
            if index + 1 < len(self.data):
                word |= self.data[index + 1] << 8
            total += word
            total = (total & 0xFFFF) + (total >> 16)
        total = (total & 0xFFFF) + (total >> 16)
        return total + len(self.data)

    def entry_is_code(self):
        return any(
            section["rva"] <= self.entry < section["rva"] + section["raw_size"]
            and section["flags"] & 0x20000000
            for section in self.sections
        )


def verify():
    ntdll = PE(ROOT / "ntdll" / "ntdll.dll")
    smss = PE(ROOT / "smss" / "smss.exe")
    assert ntdll.characteristics & 0x2000, "NTDLL must be a DLL"
    assert not smss.characteristics & 0x2000, "SMSS must be an executable"
    assert ntdll.base == 0x7C900000 and smss.base == 0x400000
    assert ntdll.entry_is_code() and smss.entry_is_code()
    for image in (ntdll, smss):
        stored = image.u32(image.opt + 64)
        assert stored and stored == image.checksum(), f"Invalid checksum: {image.path}"

    assert ntdll.imports() == {}, "Minimal NTDLL must have no DLL dependencies"
    imports = smss.imports()
    assert set(imports) == {"ntdll.dll"}, "SMSS may import only NTDLL"
    assert set(imports["ntdll.dll"]) == {"NtDisplayString", "NtDelayExecution"}
    exports = ntdll.exports()
    lookup_source = (REPO / "WRK-V1.2" / "BASE" / "NTOS" / "PS" / "KULOOKUP.C").read_text()
    required = set(re.findall(r'EntryName\s*=\s*"([A-Za-z0-9_]+)"', lookup_source))
    required.add("LdrInitializeThunk")
    assert required <= exports.keys(), f"Missing WRK exports: {required - exports.keys()}"
    assert set(imports["ntdll.dll"]) <= exports.keys()
    for name in required:
        assert any(
            section["rva"] <= exports[name] < section["rva"] + section["raw_size"]
            and section["flags"] & 0x20000000
            for section in ntdll.sections
        ), f"Required function {name} is not executable"

    table = (REPO / "WRK-V1.2" / "BASE" / "NTOS" / "KE" / "I386" / "SYSTABLE.ASM").read_text()
    rows = re.findall(r'^\s*TABLE_ENTRY\s+(\w+),\s*\d+,\s*(\d+)\s*$', table, re.MULTILINE)
    services = {"Nt" + name: (index, int(arguments) * 4)
                for index, (name, arguments) in enumerate(rows)}
    calls = ["NtContinue", "NtDelayExecution", "NtDisplayString", "NtProtectVirtualMemory",
             "NtRaiseException", "NtTerminateProcess"]
    verified_calls = {}
    for name in calls:
        number, argument_bytes = services[name]
        start = ntdll.offset(exports[name])
        # The direct INT 2E ABI needs EAX=service and EDX=&first argument.
        prefix = b"\xb8" + struct.pack("<I", number) + b"\x8d\x54\x24\x04\xcd\x2e"
        assert ntdll.data[start:start + len(prefix)] == prefix, f"Incorrect syscall ABI: {name}"
        tail = ntdll.data[start + len(prefix):start + len(prefix) + 3]
        assert tail == b"\xc2" + struct.pack("<H", argument_bytes)
        verified_calls[name] = {"number": number, "argumentBytes": argument_bytes}
    assert "Hello world from WRK SMSS!\n".encode("utf-16-le") in smss.data
    assert (exports["ExpInterlockedPopEntrySListResume"]
            <= exports["ExpInterlockedPopEntrySListFault"]
            < exports["ExpInterlockedPopEntrySListEnd"])
    fast = ntdll.offset(exports["KiFastSystemCall"], 5)
    assert ntdll.data[fast:fast + 5] == b"\x8b\xd4\x0f\x34\xc3"
    assert exports["KiFastSystemCallRet"] == exports["KiFastSystemCall"] + 4

    report = {
        "structuralVerification": "passed",
        "architecture": "x86 PE32",
        "subsystem": "Native 5.2",
        "checksumsValid": True,
        "smssImports": imports,
        "ntdllImports": {},
        "requiredKernelExports": sorted(required),
        "syscallsVerifiedAgainstWrk": verified_calls,
        "guestExecutionVerified": False,
    }
    (ROOT / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    verify()
