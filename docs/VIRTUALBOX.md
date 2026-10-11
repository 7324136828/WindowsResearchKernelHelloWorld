# Running the WRK x86 kernel in VirtualBox

This guide provisions a local VirtualBox VM and a non-bootable WRK payload
ISO, then explains how to install a licensed Windows base OS and add the
WRK kernel as a second boot entry inside the guest.

This is the installed-system route. The separate
[setup-mode RAM-disk experiment](WRK_HELLO_BOOT.md) has reached native SMSS
without a hard-disk Windows installation. [boot.md](boot.md) documents both
routes; [failures.md](failures.md) covers their startup diagnostics.

> **License reminder:** the Windows Research Kernel is for authorized
> academic/noncommercial use only (see `WRK-V1.2/LICENSE.TXT`). Distribute
> the kernel only to eligible users and only as the license permits.

## Prerequisites

- **Licensed 32-bit Windows Server 2003 SP1 install media and your own
  product key.** Windows 11 and Windows XP x86 do NOT work; SP2
  compatibility is not promised. The WRK tree ships no boot loader,
  filesystem, storage/network drivers, or userland. The installed-system
  route in this guide requires that base OS; the separate lab supplies
  experimental runtime modules and registry data for its native demo.
- Built kernel: `tools\Build-WrkX86.cmd` produces
  `WRK-V1.2\BASE\NTOS\BUILD\EXE\wrkx86.exe` (+ `.pdb`, `.map`, `.lib`).
  The VS2026 project and the build script both invoke the bundled
  MSVC 13.10.4035 / LINK 7.10.4035 toolchain under `WRK-V1.2\TOOLS\X86`
  (not the installed MSVC 19.51). `cvtres.exe` is supplied by the
  installed .NET Framework 4.x runtime (`%SystemRoot%\Microsoft.NET\Framework\v4.0.30319`).
- VirtualBox 7.2+ with `VBoxManage.exe`.

## 1. Provision the VM (host, run once)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\New-WrkVirtualBox.ps1
```

Optional parameters:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\New-WrkVirtualBox.ps1 -Name MyWrk -WindowsIso "C:\path\to\your-windows-server-2003-sp1.iso"
```

`-WindowsIso` must be a licensed Windows Server 2003 SP1 x86 install ISO
you own. The script refuses to modify an existing VM, folder, disk, or
ISO - pick a new `-Name` or remove the old artifacts deliberately first.

Creates under `artifacts\VirtualBox\<Name>\`:

| Path | Purpose |
|---|---|
| `<Name>.vbox` | VM config: x86, BIOS, PIIX3, 1024 MB, 1 CPU, ACPI+I/O APIC on, PAE off, no NIC/audio/USB, VBoxVGA |
| `<Name>.vdi` | Blank 20 GB dynamically allocated VDI - **not bootable** until Windows is installed |
| `payload\` | Staged files: `WRKX86.EXE`, `WRKX86.PDB`, `HALMACPI.DLL`, `LICENSE.TXT`, `INSTALL.TXT` |
| `WRK-X86.iso` | ISO9660+Joliet data ISO built from `payload\` - **not a boot disc** |

Storage layout (IDE, PIIX4): port 0/device 0 = blank VDI;
port 1/device 0 = Windows install ISO or empty drive;
port 1/device 1 = `WRK-X86.iso`. Boot order: DVD then disk.

The VM is offline (NIC disabled) and needs no Guest Additions.

## 2. Attach your licensed install ISO later

With the VM **powered off** - never re-run provisioning for an existing VM
(PowerShell, using the prepared VM name and your own ISO path):

```powershell
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" storageattach WRK-Server2003-SP1-x86 `
    --storagectl IDE --port 1 --device 0 --type dvddrive `
    --medium "C:\path\to\your-windows-server-2003-sp1.iso"
```

## 3. Install Windows Server 2003 SP1

Start the VM, boot from the install ISO, and install Windows normally
onto the blank VDI using your own product key (do not share keys).

## 4. Add the WRK boot entry (inside the guest)

Follow `INSTALL.TXT` on the `WRK_X86` data CD, summarized:

1. As Administrator, copy `WRKX86.EXE` and `HALMACPI.DLL` to
   `%SystemRoot%\System32`. Never replace the stock `ntoskrnl.exe` or
   `hal.dll`.
2. Back up `C:\boot.ini` first (`attrib -s -h -r` to edit).
3. Duplicate the real stock ARC-path line; never hardcode a partition
   number. Keep the stock entry and `default=` untouched.
4. On the new line: change the label, remove `/PAE` and conflicting
   `/noexecute` flags, append
   `/fastdetect /noexecute=alwaysoff /kernel=wrkx86.exe /hal=halmacpi.dll`.
5. `timeout=` at least 30, restore `attrib +s +h +r`, eject the CDs,
   reboot, select the WRK entry. The untouched stock entry is the
   recovery path if the WRK kernel fails to boot.

`HALMACPI.DLL` (ACPI APIC MP HAL) is the required match because the VM is
configured with ACPI and I/O APIC enabled.

## Honest limitations

- The host-side smoke test (headless start + BIOS screenshot) observed the
  VM starting under VirtualBox's NEM backend on this host - `VBox.log`
  shows `NEM: Created partition`, `PGM: Enabling NEM mode`,
  `NEMR3Init: Snail execution mode is active!`, and
  `NEM: Successfully set up partition`. That proves host VM startup only.
  **WRK boot through this installed-system route has not been verified**;
  the blank VDI still needs the compatible Windows installation described
  above. The separate RAM-disk demo's verification does not establish
  this route or measure performance.
- WRK sources and the produced kernel are unmodified.

## Hyper-V / host notes

Windows Hypervisor is active on this host, and the observed headless
startup ran through VirtualBox's NEM backend (the log lines above). Do not
disable Hyper-V, VBS, or Secure Boot to make this work; if a startup smoke
test fails, keep `VBox.log` (under `artifacts\VirtualBox\<Name>\Logs\`)
and report the error instead of changing host security settings.

## Logs and evidence

Provisioning transcripts land in `artifacts\logs\New-WrkVirtualBox-*.log`;
build logs in `artifacts\logs\build-wrk-x86.log`. Nothing under
`artifacts\` is tracked by git.
