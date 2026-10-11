"""Read a VirtualBox ELF core using x86 paging; never execute guest code.

Example: py tools/Inspect-WrkVmCore.py guest.core --registers registers.txt
"""

import argparse
import json
import mmap
import re
import struct
from pathlib import Path


class MemoryErrorInCore(ValueError):
    pass


class Core:
    def __init__(self, path, cr3, pae=False):
        self.file = Path(path).open("rb")
        self.data = mmap.mmap(self.file.fileno(), 0, access=mmap.ACCESS_READ)
        if self.data[:6] != b"\x7fELF\x02\x01":
            raise ValueError("Expected little-endian ELF64 VirtualBox core")
        h = struct.unpack_from("<16sHHIQQQIHHHHHH", self.data, 0)
        self.segments = []
        for i in range(h[10]):
            p = struct.unpack_from("<IIQQQQQQ", self.data, h[5] + i * h[9])
            if p[0] == 1:
                self.segments.append((p[4], p[2], p[5], p[6]))
        self.cr3 = cr3
        self.pae = pae

    def physical(self, address, length):
        result = bytearray()
        while length:
            for physical, offset, file_size, memory_size in self.segments:
                delta = address - physical
                if 0 <= delta < memory_size:
                    count = min(length, memory_size - delta)
                    if delta + count > file_size:
                        raise MemoryErrorInCore(f"Physical bytes absent at {address:#x}")
                    result.extend(self.data[offset + delta:offset + delta + count])
                    address += count
                    length -= count
                    break
            else:
                raise MemoryErrorInCore(f"Physical address outside core: {address:#x}")
        return bytes(result)

    def physical_integer(self, address, width):
        return int.from_bytes(self.physical(address, width), "little")

    @staticmethod
    def present(entry, address):
        if not entry & 1:
            raise MemoryErrorInCore(f"Virtual page absent at {address:#x}")

    def translate(self, address):
        address &= 0xFFFFFFFF
        if self.pae:
            pdpte = self.physical_integer((self.cr3 & ~31) + (address >> 30) * 8, 8)
            self.present(pdpte, address)
            pde = self.physical_integer((pdpte & 0xFFFFFF000) + ((address >> 21) & 511) * 8, 8)
            self.present(pde, address)
            if pde & 128:
                return (pde & 0xFFFE00000) + (address & 0x1FFFFF)
            pte = self.physical_integer((pde & 0xFFFFFF000) + ((address >> 12) & 511) * 8, 8)
            self.present(pte, address)
            return (pte & 0xFFFFFF000) + (address & 4095)
        pde = self.physical_integer((self.cr3 & 0xFFFFF000) + (address >> 22) * 4, 4)
        self.present(pde, address)
        if pde & 128:
            return (pde & 0xFFC00000) + (address & 0x3FFFFF)
        pte = self.physical_integer((pde & 0xFFFFF000) + ((address >> 12) & 1023) * 4, 4)
        self.present(pte, address)
        return (pte & 0xFFFFF000) + (address & 4095)

    def virtual(self, address, length):
        result = bytearray()
        while length:
            count = min(length, 4096 - (address & 4095))
            result.extend(self.physical(self.translate(address), count))
            address += count
            length -= count
        return bytes(result)

    def integer(self, address, width=4):
        return int.from_bytes(self.virtual(address, width), "little")

    def string(self, address, maximum=256):
        result = bytearray()
        for i in range(maximum):
            c = self.virtual(address + i, 1)
            if c == b"\0":
                return result.decode("ascii", errors="replace")
            result.extend(c)
        return result.decode("ascii", errors="replace")

    def pe(self, base):
        h = self.virtual(base, 64)
        if h[:2] != b"MZ":
            return None
        nt = struct.unpack_from("<I", h, 60)[0]
        if not 64 <= nt <= 4096:
            return None
        h = self.virtual(base + nt, 128)
        if h[:4] != b"PE\0\0" or struct.unpack_from("<H", h, 24)[0] != 0x10B:
            return None
        export = struct.unpack_from("<I", h, 120)[0]
        name = ""
        if export:
            name_rva = self.integer(base + export + 12)
            name = self.string(base + name_rva)
        return {
            "base": base,
            "name": name,
            "size": struct.unpack_from("<I", h, 80)[0],
            "entry": base + struct.unpack_from("<I", h, 40)[0],
            "preferred_base": struct.unpack_from("<I", h, 52)[0],
            "timestamp": struct.unpack_from("<I", h, 8)[0],
            "checksum": struct.unpack_from("<I", h, 88)[0],
        }


def read_map(path):
    symbols = {}
    functions = {}
    for line in Path(path).read_text().splitlines():
        m = re.match(r"\s*\S+:\S+\s+(\S+)\s+([0-9A-Fa-f]{8})\s", line)
        if m:
            symbols[m[1]] = int(m[2], 16)
            if re.search(r"\s[0-9A-Fa-f]{8}\s+f\s", line):
                functions[m[1]] = int(m[2], 16)
    return symbols, functions


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("core", type=Path)
    parser.add_argument("--registers", type=Path)
    parser.add_argument("--cr3", type=lambda s: int(s, 0))
    parser.add_argument("--pae", action="store_true")
    parser.add_argument("--map", type=Path, default=Path("WRK-V1.2/BASE/NTOS/BUILD/EXE/wrkx86.map"))
    parser.add_argument("--base", type=lambda s: int(s, 0))
    parser.add_argument("--scan-start", type=lambda s: int(s, 0), default=0x80000000)
    parser.add_argument("--scan-end", type=lambda s: int(s, 0), default=0x81000000)
    parser.add_argument("--scan-driver-images", action="store_true", help="Also scan mapped driver headers from 0xf8000000 to 0xfc000000")
    parser.add_argument("--address", type=lambda s: int(s, 0), action="append", default=[])
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    registers = {}
    if args.registers:
        registers = {m[1].lower(): int(m[2], 16) for m in re.finditer(r"(\w+)\s*=\s*(0x[0-9a-fA-F]+)", args.registers.read_text())}
    cr3 = args.cr3 if args.cr3 is not None else registers.get("cr3")
    if cr3 is None:
        parser.error("Provide --cr3 or a register file containing cr3")
    core = Core(args.core, cr3, args.pae)
    result = {"core": str(args.core), "registers": registers, "cr3": cr3, "pae": args.pae, "images": [], "reads": []}
    scan_addresses = list(range(args.scan_start, args.scan_end, 4096))
    if args.scan_driver_images:
        scan_addresses.extend(range(0xF8000000, 0xFC000000, 4096))
    for address in sorted(set(scan_addresses)):
        try:
            pe = core.pe(address)
            if pe:
                result["images"].append(pe)
        except (ValueError, struct.error):
            pass
    symbols, functions = read_map(args.map)
    candidates = [p for p in result["images"] if p["name"].lower() in ("ntoskrnl.exe", "wrkx86.exe")]
    base = args.base if args.base is not None else (candidates[0]["base"] if len(candidates) == 1 else None)
    if base is not None:
        preferred = next((p["preferred_base"] for p in result["images"] if p["base"] == base), 0x400000)
        result["kernel_base"] = base
        result["kernel_symbols"] = {}
        for name, width, count in [("_KiBugCheckData", 4, 5), ("_IopInitFailCode", 4, 1), ("_ExpInTextModeSetup", 1, 1), ("_ExpSetupSystemPrefix", 4, 2), ("_InbvBootDriverInstalled", 1, 1), ("_InbvDisplayState", 4, 1), ("_KeLoaderBlock", 4, 1)]:
            if name in symbols:
                address = base + symbols[name] - preferred
                try:
                    values = [core.integer(address + width * i, width) for i in range(count)]
                    result["kernel_symbols"][name] = {"address": address, "values": values}
                except ValueError as error:
                    result["kernel_symbols"][name] = {"address": address, "error": str(error)}
        kernel_size = next((p["size"] for p in result["images"] if p["base"] == base), 0x300000)
        sorted_symbols = sorted((base + address - preferred, name) for name, address in functions.items())
        def nearest(value):
            if not base <= value < base + kernel_size:
                return ""
            previous = [s for s in sorted_symbols if s[0] <= value]
            if previous and value - previous[-1][0] < 0x10000:
                return previous[-1][1] + "+" + hex(value - previous[-1][0])
            return ""
        def module(value):
            containing = [p for p in result["images"] if p["base"] <= value < p["base"] + p["size"]]
            if containing:
                p = min(containing, key=lambda image: image["size"])
                return (p["name"] or "image") + "+" + hex(value - p["base"])
            return ""
        if "eip" in registers:
            result["eip_symbol"] = nearest(registers["eip"])
            result["eip_module"] = module(registers["eip"])
        if "esp" in registers:
            try:
                values = struct.unpack("<64I", core.virtual(registers["esp"], 256))
                result["stack"] = [{"address": registers["esp"] + i * 4, "value": value, "kernel_symbol": nearest(value), "module": module(value)} for i, value in enumerate(values)]
            except ValueError as error:
                result["stack_error"] = str(error)
        if "ebp" in registers and "esp" in registers:
            result["frame_chain"] = []
            frame = registers["ebp"]
            for _ in range(64):
                if frame & 3 or not registers["esp"] <= frame < registers["esp"] + 0x10000:
                    break
                try:
                    next_frame, return_address = struct.unpack("<II", core.virtual(frame, 8))
                except ValueError:
                    break
                result["frame_chain"].append({"frame": frame, "return_address": return_address, "kernel_symbol": nearest(return_address), "module": module(return_address)})
                if next_frame <= frame:
                    break
                frame = next_frame
    for address in args.address:
        try:
            result["reads"].append({"address": address, "physical": core.translate(address), "bytes": core.virtual(address, 64).hex()})
        except ValueError as error:
            result["reads"].append({"address": address, "error": str(error)})
    text = json.dumps(result, indent=2)
    print(text)
    if args.output:
        args.output.write_text(text + "\n")


if __name__ == "__main__":
    main()
