# WRK native Hello World boot data

`tools/New-WrkHelloHives.ps1` builds five isolated binary registry hives and
three early NLS files using `_bootldr_ex`'s existing host tools and source data.
It leaves the original ReactOS seeds, example hives, kernel and ISO intact.

From the repository root:

```powershell
.\tools\New-WrkHelloHives.ps1
.\tools\New-WrkHelloHives.ps1 -BootMode Core -OutputDirectory artifacts\wrk-hello-hives-core
```

The default `Ramdisk` mode adds boot-start `ramdisk.sys` and `cdfs.sys` services.
Outputs are `artifacts/wrk-hello-hives/Config` and `artifacts/wrk-hello-hives/Nls`.
A separate `Core` mode contains no boot services and is only useful for testing
loader/core handoff; it cannot open NTDLL or SMSS through a filesystem.

Stage the default outputs beneath the RAM-disk system root (`WRK/System32`),
alongside WRK, HAL, BOOTVID, KDCOM, the native demo pair, and compatible RAM-disk
and CDFS drivers. The external boot CD must supply the inner filesystem image
via FreeLoader `RDPATH` and select `SystemPath=ramdisk(0)\WRK`. Use `/MININT /INRAM
/SOS /RDEXPORTASCD`. The loader preserves the image in `LoaderXIPRom` memory;
WRK's RAM-disk initialization must make it accessible after kernel handoff.

The seed selects control set 1, `c_1252.nls`, `c_437.nls`, and `l_intl.nls`.
The Session Manager boot/subsystem lists and paging-file list are empty because
the custom native SMSS only prints its greeting and waits. It does not start a
Windows subsystem or desktop. SAM and SECURITY are valid empty seed hives, not
account or security databases for a functional Windows session.

WRK's `/MININT` path loads machine hives into memory with read-only backing-file
access and disables persistence. RAM-disk ISO export avoids an IDE/CD-ROM
controller driver dependency for the system root. This still requires a
compatible kernel/HAL/driver/loader ABI; successful generation alone does not
prove a boot or native Hello World execution.

`manifest.json` records modes, file hashes, and validation results. The generator
checks each hive's clean sequence numbers, base-block checksum, root cell and
contiguous hive-bin chain, plus the generated codepage identifiers.
