# ReactOS boot components for WRK integration

Copy this **entire source directory** into your other repository, excluding
ignored `build*/` and `output*/` validation directories. It contains a portable
source snapshot of HAL, `bootvid.dll`, `kdcom.dll`, hive/NLS tooling, and their
source dependencies, including the existing `_bootldr` loader. Paths retain the
ReactOS layout so includes and build references stay meaningful. Original files
in the parent repository are retained.

The focused CMake entry point builds host tools independently and configures the
i386/amd64 PC boot components with the copied ReactOS build infrastructure.
It does not require the parent checkout. Build it as a separate project; WRK's
native build files are not automatically modified.

## Included source and dependency map

| Component | Source | Main dependencies |
| --- | --- | --- |
| HAL variants and loader minihal | `hal/` | SDK/private kernel headers, ACPICA headers, arbiter, fast486, libcntpr, setjmp, PSEH |
| Boot video DLLs | `drivers/base/bootvid/` | SDK headers, bootvid interfaces, HAL/kernel imports |
| Serial kernel debugger DLL | `drivers/base/kdcom/` | cportlib, CRT strtol routines, SDK debugger interfaces, HAL/kernel imports |
| SYSTEM and other hive seeds | `boot/bootdata/` | mkhive, INF parsing, registry library, Unicode/bitmap helpers |
| Hive generation and loading | `sdk/tools/mkhive/`, `sdk/lib/cmlib/`, `sdk/lib/inflib/`, `_bootldr/freeldr/freeldr/ntldr/` | Host headers/Unicode library, loader runtime, `ntoskrnl/config/cmboot.c` |
| NLS data, mappings and generators | `media/nls/`, `sdk/tools/txt2nls/`, `sdk/tools/unicode/` | C++ host compiler; copied binary language/locale tables |
| NLS initialization/runtime | `_bootldr/rtl/nlsboot.c`, `sdk/lib/rtl/nls.c`, `media/inf/intl.inf` | Shared NLS/NT headers, selected NLS tables |
| Bootloader | `_bootldr/` | blrtl, blcmlib, libcntpr, cportlib, minihal, kernel configuration helpers |
| Shared support | `sdk/include/`, `sdk/cmake/`, selected `sdk/lib/` and `sdk/tools/` | Compiler, assembler, resource/message tools, Bison/Flex for IDL generators |

`ntoskrnl/include/` supplies private types. `ntoskrnl/ntoskrnl.spec` supplies
kernel import-library definitions; the bundle does not build a replacement
kernel. `sdk/tools/create_nls/` is retained as legacy reference code; the current
NLS build uses `txt2nls`. That legacy tool needs separate Unicode input data.

## Build hives and NLS files

With CMake 3.20+, Ninja, and a working native C/C++ compiler, run from this directory:

```powershell
cmake -S . -B build-host -G Ninja "-DARCH=i386"
cmake --build build-host --target bootldr_data
```

The build produces:

- `build-host/bin/`: `mkhive`, `txt2nls`, and `utf16le` host executables.
- `build-host/stage/reactos-hives/`: `SYSTEM`, `SOFTWARE`, `DEFAULT`, `SAM`,
  `SECURITY`, `SETUPREG.HIV`, and `BCD`.
- `build-host/stage/nls/`: generated codepage tables and copied binary NLS tables.

These are **ReactOS example hives**. Their default inputs are `hivecls.inf`,
`hivedef.inf`, `hivesft.inf`, and `hivesys.inf`; setup and BCD use their respective
additional seeds. A complete installed system also needs hardware/service
registration and account/security state. For an existing Windows system booting
WRK, retain its matching installed hives and boot-start drivers.

To use your own registry seeds, set `BOOTLDR_EX_REGISTRY_INF_FILES` to a quoted,
semicolon-separated list. `BOOTLDR_EX_EXTRA_REGISTRY_INF_FILES` adds files after
the core seeds. Paths may be absolute or relative to this directory. For example:

```powershell
cmake -S . -B build-host "-DBOOTLDR_EX_EXTRA_REGISTRY_INF_FILES=wrk/registry.inf"
cmake --build build-host --target bootldr_hives
```

Supply that INF yourself. The build converts every input to UTF-16LE. Full
ReactOS registry creation also includes driver registry fragments; the parent
build's recipe is retained in `sdk/cmake/CMakeMacros.cmake`.

The loader reads `SYSTEM\CurrentControlSet\Control\NLS` to select ANSI, OEM,
and language tables. The default boot tables are `c_1252.nls`, `c_437.nls`, and
`l_intl.nls`. NLS files belong under the installed system's `System32`; installed
hives belong under `System32\Config`.

## Build HAL, the boot DLLs, and the loader

Use the ReactOS Build Environment (RosBE) for the selected architecture, or a
compatible toolchain with ReactOS's required tools. Start with i386 PC BIOS:

```powershell
cmake -S . -B build-i386 -G Ninja "-DARCH=i386" "-DCMAKE_TOOLCHAIN_FILE=cmake/toolchain-gcc.cmake"
cmake --build build-i386 --target bootldr_components
```

Use `ARCH=amd64` with an amd64 toolchain and a separate build directory. The GCC
wrapper forwards explicit `MINGW_TOOLCHAIN_PREFIX`/`MINGW_TOOLCHAIN_SUFFIX` values
to compiler probes. GNU amd64 also requires matching GCC plugin development
headers for the copied PSEH plugin. Bison and Flex are needed for the host IDL
generators. Use the Ninja generator with the supplied MSVC toolchain in a
compatible developer environment if adapting the build for MSVC.

`BOOTLDR_EX_HAL_TARGET` selects the target staged as `hal.dll`, defaulting to
`hal`; for example, an i386 build can select `halacpi`, `halaacpi`, or `halmacpi`.
The default `hal` target uses the upstream architecture-specific implementation.

`build-i386/stage/components/` contains `freeldr.sys`, `rosload.exe`, the WRK
`freeldr.ini` example, boot-sector binaries, and
`system32/{hal.dll,bootvid.dll,kdcom.dll}`. The preserved `_bootldr/README.md`
describes the parent checkout's `wrkboot` target; this focused build uses
`bootldr_components` instead. Individual targets such as `kdcom` also work.

## WRK integration boundary

These ReactOS sources need adaptation and validation against your WRK build.
HAL depends on private kernel structures and checks the PRCB version/build type.
The DLLs import kernel/HAL exports, and FreeLoader passes NT loader structures.
Match architecture, exports, calling conventions, private layouts, and kernel
configuration before treating the resulting binaries as compatible with WRK.
Set `BOOTLDR_EX_KERNEL_IMPORT_LIBRARY` to an absolute path to your matching
WRK/toolchain kernel import library to replace the default ReactOS import
definitions. The current sources contain incomplete PAE and `/3GB` loader handling.

The bundle supplies source and data-generation tools. It does not establish a
successful WRK boot or supply Windows system binaries. Boot-sector staging does
not install a boot sector. Validate integration using your WRK installation and
a VM disk image.

## Provenance and verification

The WRK setup-mode lab adapts `sdk/include/reactos/arc/setupblk.h`: NT 5.2
uses `0x1` for remote boot and `0x2` for text-mode setup. The original snapshot
had those values reversed. `tools/Build-WrkSetupLoader.ps1` in the WRK workspace
copies this header into an isolated loader build and records its hash alongside
the local loader source and output hashes. The original source manifest remains
a record of the imported snapshot, so its verification reports this adaptation
as a changed file. See [the boot experiment guide](../docs/WRK_HELLO_BOOT.md).

`source-paths.json` lists the copied paths. `source-manifest.json` records their
SHA-256 hashes, sizes, parent HEAD, and the origins of the two adapted CMake
helpers. Original per-file license notices and the root COPYING files are retained;
those licenses apply when reusing the code alongside WRK.

From the parent ReactOS repository, refresh the copied paths and verify them:

```powershell
./_bootldr_ex/tools/Export-Sources.ps1
./_bootldr_ex/tools/Verify-Sources.ps1
```

Export overwrites the selected snapshot files and the two derived build helpers.
Keep adaptations in your own commits before refreshing. In another repository,
pass `-SourceRoot` pointing at the original ReactOS checkout.

To inspect the portable source graph without an NT compiler:

```powershell
cmake -S tools/validate-source-graph -B output-validation-i386 -G Ninja "-DARCH=i386"
cmake -S tools/validate-source-graph -B output-validation-amd64 -G Ninja "-DARCH=amd64"
```

These checks inspect source/include/dependency references using explicit helper
stubs. They do not compile or link modules. The upstream obsolete
`sdk/lib/crt/libm_sse2` include path is documented as an exception; its actual
sources exist under `sdk/lib/crt/math/libm_sse2`.

Validation in this checkout: all 3,953 source hashes verified; host generators
built and produced all seven example hives and 127 NLS files; hive checksums, bin
chains, root cells, codepage headers, and copied table hashes passed; i386/amd64 source
graphs passed; the real amd64 target build configured. HAL/DLL compilation stopped
at the host generator configuration because Bison is absent locally. No WRK boot
was performed.
