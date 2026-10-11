#Requires -Version 5.1
<#
.SYNOPSIS
  Provision an isolated VirtualBox VM with a blank VDI and a non-bootable
  WRK x86 payload ISO. Does NOT build the kernel and does NOT start the VM.

.DESCRIPTION
  Creates <repo>\artifacts\VirtualBox\<Name>\ containing <Name>.vbox,
  <Name>.vdi (20 GB dynamic), a payload\ staging dir, and WRK-X86.iso
  (ISO9660+Joliet data disc - explicitly not bootable). A licensed 32-bit
  Windows Server 2003 SP1 install ISO may be attached via -WindowsIso;
  otherwise that DVD drive is left empty. Refuses to reuse or modify any
  existing VM, folder, disk, or ISO.

.PARAMETER Name
  VM name (^[A-Za-z0-9][A-Za-z0-9_.-]*$). Default WRK-Server2003-SP1-x86.

.PARAMETER WindowsIso
  Optional path to a licensed Windows Server 2003 SP1 x86 install ISO.

.PARAMETER VBoxManagePath
  Path to VBoxManage.exe (default: %ProgramFiles%\Oracle\VirtualBox).
#>
[CmdletBinding()]
param(
    [string]$Name = 'WRK-Server2003-SP1-x86',
    [string]$WindowsIso,
    [string]$VBoxManagePath = (Join-Path $env:ProgramFiles 'Oracle\VirtualBox\VBoxManage.exe')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot   = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$BaseFolder = Join-Path $RepoRoot 'artifacts\VirtualBox'
$LogDir     = Join-Path $RepoRoot 'artifacts\logs'
$LogFile    = Join-Path $LogDir ('New-WrkVirtualBox-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))

function Write-Log([string]$Msg) {
    $line = '{0:HH:mm:ss} {1}' -f (Get-Date), $Msg
    Add-Content -LiteralPath $LogFile -Value $line
    Write-Host $line
}
function Fail([string]$Msg) {
    Write-Log "ERROR: $Msg"
    Write-Log "Provisioning stopped; log retained at $LogFile"
    exit 1
}

# Runs VBoxManage capturing stdout/stderr/exit code; avoids PS5.1 turning
# native stderr into a terminating ErrorRecord before status can be read.
function Invoke-VBoxManage([string[]]$ArgList) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $VBoxManagePath
    $psi.Arguments = (($ArgList | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    }) -join ' ')
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $out = $proc.StandardOutput.ReadToEnd()
    $err = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    Write-Log ('VBoxManage {0}' -f ($ArgList -join ' '))
    foreach ($l in ($out.TrimEnd() -split "`r?`n")) { if ($l) { Write-Log "  | $l" } }
    foreach ($l in ($err.TrimEnd() -split "`r?`n")) { if ($l) { Write-Log "  ! $l" } }
    Write-Log "  -> exit $($proc.ExitCode)"
    if ($proc.ExitCode -ne 0) {
        Fail "VBoxManage $($ArgList[0]) failed with exit code $($proc.ExitCode) (see log). New artifacts left in place for inspection."
    }
    return $out
}

if (-not (Test-Path -LiteralPath $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
Write-Log "New-WrkVirtualBox starting; log: $LogFile"

# ---- validation: everything below runs before any mutation ------------
if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$') {
    Fail "Invalid -Name '$Name' (must match ^[A-Za-z0-9][A-Za-z0-9_.-]*$)"
}
if (-not (Test-Path -LiteralPath $VBoxManagePath -PathType Leaf)) {
    Fail "VBoxManage.exe not found at '$VBoxManagePath' (-VBoxManagePath)"
}
$required = @(
    'WRK-V1.2\BASE\NTOS\BUILD\EXE\wrkx86.exe',
    'WRK-V1.2\BASE\NTOS\BUILD\EXE\wrkx86.pdb',
    'WRK-V1.2\WS03SP1HALS\X86\HALMACPI\HALMACPI.DLL',
    'WRK-V1.2\LICENSE.TXT',
    'tools\guest\INSTALL.TXT'
)
foreach ($rel in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $rel) -PathType Leaf)) {
        Fail "Required file missing: $rel (build the kernel first with tools\Build-WrkX86.cmd)"
    }
}
if ($WindowsIso) {
    if (-not (Test-Path -LiteralPath $WindowsIso -PathType Leaf)) {
        Fail "-WindowsIso not found: '$WindowsIso'"
    }
    $WindowsIso = (Resolve-Path -LiteralPath $WindowsIso).Path
    Write-Log "Windows install ISO: $WindowsIso"
} else {
    Write-Log 'No -WindowsIso supplied; install DVD drive will be empty (blank VDI is not bootable).'
}

$MachineDir = Join-Path $BaseFolder $Name
$DiskPath   = Join-Path $MachineDir "$Name.vdi"
$IsoPath    = Join-Path $MachineDir 'WRK-X86.iso'
$PayloadDir = Join-Path $MachineDir 'payload'

$vms = Invoke-VBoxManage @('list', 'vms')
$escaped = [regex]::Escape($Name)
if ($vms -split "`r?`n" | Where-Object { $_ -match "^`"$escaped`"\s+\{" }) {
    Fail "A registered VM named '$Name' already exists; refusing to modify it."
}
foreach ($p in @($MachineDir, $DiskPath, $IsoPath)) {
    if (Test-Path -LiteralPath $p) { Fail "Target already exists: $p" }
}

# ---- IMAPI2 capability loaded before any VM mutation ------------------
if (-not ('WrkIsoWriter' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
public static class WrkIsoWriter {
    public static void Save(object comStream, string path) {
        IStream stm = (IStream)comStream;
        using (FileStream fs = new FileStream(path, FileMode.CreateNew, FileAccess.Write)) {
            byte[] buf = new byte[65536];
            IntPtr pcb = Marshal.AllocHGlobal(4);
            try {
                for (;;) {
                    stm.Read(buf, buf.Length, pcb);
                    int n = Marshal.ReadInt32(pcb);
                    if (n <= 0) break;
                    fs.Write(buf, 0, n);
                }
            } finally { Marshal.FreeHGlobal(pcb); }
        }
    }
}
'@
}
try {
    $fsi = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
    $fsi.ChooseImageDefaultsForMediaType(2)      # IMAPI_MEDIA_TYPE_CDR
    $fsi.FileSystemsToCreate = 3                 # ISO9660 | Joliet
    $fsi.VolumeName = 'WRK_X86'
} catch {
    Fail "IMAPI2 (IMAPI2FS.MsftFileSystemImage) unavailable: $_"
}
Write-Log 'IMAPI2 file system image ready (ISO9660+Joliet, volume WRK_X86, no boot image).'

# ---- create and configure the VM --------------------------------------
New-Item -ItemType Directory -Path $BaseFolder -Force | Out-Null
Invoke-VBoxManage @('createvm', '--name', $Name, '--platform-architecture', 'x86',
    '--ostype', 'Windows2003', '--basefolder', $BaseFolder, '--register') | Out-Null

$desc = 'WRK x86 test VM. A licensed 32-bit Windows Server 2003 SP1 install ISO is required (not supplied); the blank VDI is NOT bootable until Windows is installed. See docs\VIRTUALBOX.md.'
Invoke-VBoxManage @('modifyvm', $Name,
    '--memory', '1024', '--cpus', '1', '--firmware', 'bios', '--chipset', 'piix3',
    '--acpi', 'on', '--apic', 'on', '--ioapic', 'on', '--x86-pae', 'off', '--x86-hpet', 'off',
    '--x86-x2apic', 'off', '--paravirt-provider', 'none',
    '--graphicscontroller', 'vboxvga', '--vram', '16', '--accelerate-3d', 'off',
    '--nic1', 'none', '--audio-enabled', 'off',
    '--usb-ohci', 'off', '--usb-ehci', 'off', '--usb-xhci', 'off',
    '--boot1', 'dvd', '--boot2', 'disk', '--boot3', 'none', '--boot4', 'none',
    '--clipboard-mode', 'disabled', '--drag-and-drop', 'disabled',
    '--description', $desc) | Out-Null

# ---- payload ISO inside the machine folder -----------------------------
New-Item -ItemType Directory -Path $PayloadDir -Force | Out-Null
$payloadFiles = @(
    @{ Src = 'WRK-V1.2\BASE\NTOS\BUILD\EXE\wrkx86.exe';            Dst = 'WRKX86.EXE' },
    @{ Src = 'WRK-V1.2\BASE\NTOS\BUILD\EXE\wrkx86.pdb';            Dst = 'WRKX86.PDB' },
    @{ Src = 'WRK-V1.2\WS03SP1HALS\X86\HALMACPI\HALMACPI.DLL';     Dst = 'HALMACPI.DLL' },
    @{ Src = 'WRK-V1.2\LICENSE.TXT';                             Dst = 'LICENSE.TXT' },
    @{ Src = 'tools\guest\INSTALL.TXT';                          Dst = 'INSTALL.TXT' }
)
foreach ($f in $payloadFiles) {
    Copy-Item -LiteralPath (Join-Path $RepoRoot $f.Src) -Destination (Join-Path $PayloadDir $f.Dst)
    Write-Log "staged $($f.Dst)"
}
try {
    $fsi.Root.AddTree($PayloadDir, $false)
    $resultImage = $fsi.CreateResultImage()
    [WrkIsoWriter]::Save($resultImage.ImageStream, $IsoPath)
} catch {
    Fail "ISO creation failed: $_"
} finally {
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($fsi)
}
Write-Log "payload ISO written: $IsoPath ($((Get-Item $IsoPath).Length) bytes)"

# ---- storage -----------------------------------------------------------
Invoke-VBoxManage @('storagectl', $Name, '--name', 'IDE', '--add', 'ide',
    '--controller', 'PIIX4', '--hostiocache', 'on') | Out-Null
Invoke-VBoxManage @('createmedium', 'disk', '--filename', $DiskPath,
    '--format', 'VDI', '--size', '20480', '--variant', 'Standard') | Out-Null
Invoke-VBoxManage @('storageattach', $Name, '--storagectl', 'IDE', '--port', '0',
    '--device', '0', '--type', 'hdd', '--medium', $DiskPath) | Out-Null
$dvd0 = if ($WindowsIso) { $WindowsIso } else { 'emptydrive' }
Invoke-VBoxManage @('storageattach', $Name, '--storagectl', 'IDE', '--port', '1',
    '--device', '0', '--type', 'dvddrive', '--medium', $dvd0) | Out-Null
Invoke-VBoxManage @('storageattach', $Name, '--storagectl', 'IDE', '--port', '1',
    '--device', '1', '--type', 'dvddrive', '--medium', $IsoPath) | Out-Null

Write-Log "Done. VM '$Name' registered (powered off, NOT started)."
Write-Log "  machine : $MachineDir\$Name.vbox"
Write-Log "  disk    : $DiskPath (blank 20 GB VDI - not bootable)"
Write-Log "  payload : $IsoPath"
Write-Log 'Next: attach a licensed Windows Server 2003 SP1 x86 ISO (see docs\VIRTUALBOX.md), then install Windows before WRK can be tried.'
exit 0
