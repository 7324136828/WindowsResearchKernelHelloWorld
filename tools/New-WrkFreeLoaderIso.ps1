#Requires -Version 5.1
<#
.SYNOPSIS
  Package the already-built FreeLoader (wrkboot/isoboot) plus the frozen
  WRK payload into a BIOS no-emulation boot ISO. Does NOT build, download,
  or modify any source or existing VM/image.
.PARAMETER BuildDirectory
  ReactOS build tree (default: <repo>\artifacts\freeldr-build-x86).
.PARAMETER OutputDirectory
  Fresh dir for iso-root + ISO (default: <repo>\artifacts\wrk-freeldr).
.PARAMETER SystemPath
  ARC SystemPath for the installed Windows (validated before use).
#>
[CmdletBinding()]
param(
    [string]$BuildDirectory = '',
    [string]$OutputDirectory = '',
    [string]$SystemPath = 'multi(0)disk(0)rdisk(0)partition(1)\WINDOWS'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not $BuildDirectory)  { $BuildDirectory  = Join-Path $RepoRoot 'artifacts\freeldr-build-x86' }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $RepoRoot 'artifacts\wrk-freeldr' }
$ReactOSRoot = (Resolve-Path -LiteralPath (Join-Path $RepoRoot '..\reactos')).Path
$LogDir  = Join-Path $RepoRoot 'artifacts\logs'
$LogFile = Join-Path $LogDir ('new-wrkfreeloader-iso-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

function Write-Log([string]$Msg) {
    $line = '{0:HH:mm:ss} {1}' -f (Get-Date), $Msg
    Add-Content -LiteralPath $LogFile -Value $line
    Write-Host $line
}
function Fail([string]$Msg) { Write-Log "ERROR: $Msg"; Write-Log "Stopped; log: $LogFile"; exit 1 }

function Invoke-Native([string]$Exe, [string[]]$ArgList) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = (($ArgList | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    }) -join ' ')
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    $p.WaitForExit()
    $out = $outTask.Result; $err = $errTask.Result
    Write-Log ("{0} {1}" -f (Split-Path $Exe -Leaf), ($ArgList -join ' '))
    foreach ($l in ($out.TrimEnd() -split "`r?`n")) { if ($l) { Write-Log "  | $l" } }
    foreach ($l in ($err.TrimEnd() -split "`r?`n")) { if ($l) { Write-Log "  ! $l" } }
    Write-Log "  -> exit $($p.ExitCode)"
    if ($p.ExitCode -ne 0) { Fail "$Exe exited $($p.ExitCode)" }
}

Write-Log "New-WrkFreeLoaderIso starting; log: $LogFile"

# ---- SystemPath validation (no INI injection, no traversal) --------------
$segRx = '[^\\<>:"|?*\x00-\x1f]+'
$arcRx = "^multi\(0\)disk\(0\)rdisk\([0-9]+\)partition\([0-9]*[1-9][0-9]*\)\\($segRx\\)*$segRx`$"
if ($SystemPath -notmatch $arcRx -or $SystemPath -match '\.\.' -or $SystemPath -match '[\x00-\x1f"'']') {
    Fail "invalid -SystemPath '$SystemPath' (need multi(0)disk(0)rdisk(N)partition(N>=1)\WINDOWS-style ARC path)"
}
foreach ($seg in ($SystemPath -split '\\' | Select-Object -Skip 1)) {
    if ($seg -notmatch "^$segRx`$" -or $seg -in @('.', '..')) { Fail "bad SystemPath component '$seg'" }
}
Write-Log "SystemPath: $SystemPath"

# ---- preflight all inputs -------------------------------------------------
$need = @{
    Freeldr = Join-Path $BuildDirectory '_bootldr\wrk\freeldr.sys'
    Rosload = Join-Path $BuildDirectory '_bootldr\wrk\rosload.exe'
    Isoboot = Join-Path $BuildDirectory '_bootldr\freeldr\bootsect\isoboot.bin'
    Mkisofs = Join-Path $BuildDirectory 'host-tools\bin\mkisofs.exe'
    Kernel  = Join-Path $RepoRoot 'WRK-V1.2\BASE\NTOS\BUILD\EXE\wrkx86.exe'
    Ksym    = Join-Path $RepoRoot 'WRK-V1.2\BASE\NTOS\BUILD\EXE\wrkx86.pdb'
    Hal     = Join-Path $RepoRoot 'WRK-V1.2\WS03SP1HALS\X86\HALMACPI\HALMACPI.DLL'
    License = Join-Path $RepoRoot 'WRK-V1.2\LICENSE.TXT'
    Install = Join-Path $RepoRoot 'tools\guest\INSTALL.TXT'
    IniTpl  = Join-Path $RepoRoot '_bootldr\wrk\freeldr-vbox.ini'
    Gpl     = Join-Path $ReactOSRoot 'COPYING'
}
foreach ($k in $need.Keys) {
    $p = $need[$k]
    if (-not (Test-Path -LiteralPath $p -PathType Leaf) -or (Get-Item -LiteralPath $p).Length -eq 0) {
        Fail "required input missing/empty: $k = $p"
    }
}
if ((Get-Item -LiteralPath $need.Isoboot).Length -ne 2048) {
    Fail "isoboot.bin is $((Get-Item -LiteralPath $need.Isoboot).Length) bytes, expected 2048"
}

# rosload.exe must be a well-formed PE32, machine 0x14C, subsystem Native(1)
$pe = [IO.File]::ReadAllBytes($need.Rosload)
if ($pe.Length -lt 64 -or $pe[0] -ne 0x4D -or $pe[1] -ne 0x5A) { Fail 'rosload.exe: no MZ header' }
$peOfs = [BitConverter]::ToInt32($pe, 0x3c)
if ($peOfs -le 0 -or ($peOfs + 24) -gt $pe.Length) { Fail 'rosload.exe: e_lfanew out of range' }
if (-not ($pe[$peOfs] -eq 0x50 -and $pe[$peOfs+1] -eq 0x45 -and $pe[$peOfs+2] -eq 0 -and $pe[$peOfs+3] -eq 0)) {
    Fail 'rosload.exe: bad PE\0\0 signature'
}
$mach    = [BitConverter]::ToUInt16($pe, $peOfs + 4)
$optSize = [BitConverter]::ToUInt16($pe, $peOfs + 20)
$optBase = $peOfs + 24
if ($optSize -lt 70 -or ($optBase + $optSize) -gt $pe.Length) { Fail 'rosload.exe: optional header truncated' }
$magic  = [BitConverter]::ToUInt16($pe, $optBase)
$subsys = [BitConverter]::ToUInt16($pe, $optBase + 68)
if ($magic -ne 0x10B)  { Fail ('rosload.exe: optional magic 0x{0:X} != PE32 0x10B' -f $magic) }
if ($mach  -ne 0x14C)  { Fail ('rosload.exe machine 0x{0:X} != x86' -f $mach) }
if ($subsys -ne 1)     { Fail "rosload.exe subsystem $subsys != Native" }
Write-Log 'rosload.exe: PE32 x86 Native - OK'

# ---- output collision guards ----------------------------------------------
$isoPath = Join-Path $OutputDirectory 'WRK-FreeLoader.iso'
if (Test-Path -LiteralPath $isoPath) { Fail "target ISO exists: $isoPath" }
if (Test-Path -LiteralPath $OutputDirectory) {
    if (@(Get-ChildItem -LiteralPath $OutputDirectory -Force).Count -gt 0) {
        Fail "output directory not empty: $OutputDirectory"
    }
} else {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}
# Atomically reserve the ISO path - CreateNew fails if another invocation
# created it meanwhile. mkisofs may then overwrite only this file.
try {
    $reserved = New-Object IO.FileStream($isoPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $reserved.Close()
} catch { Fail "cannot reserve target ISO (race or permission): $_" }

# ---- stage iso-root --------------------------------------------------------
$root   = Join-Path $OutputDirectory 'iso-root'
$loader = Join-Path $root 'loader'
$paydir = Join-Path $root 'payload'
New-Item -ItemType Directory -Path $loader, $paydir -Force | Out-Null

Copy-Item -LiteralPath $need.Freeldr -Destination (Join-Path $loader 'freeldr.sys')
Copy-Item -LiteralPath $need.Rosload -Destination (Join-Path $loader 'rosload.exe')
Copy-Item -LiteralPath $need.Isoboot -Destination (Join-Path $loader 'isoboot.bin')

# Render template: literal replacement of ONLY the two SystemPath lines
# (MatchEvaluator avoids .NET $-substitution in the replacement string).
$tpl = Get-Content -LiteralPath $need.IniTpl -Raw
$evaluator = [Text.RegularExpressions.MatchEvaluator]{ param($match) 'SystemPath=' + $SystemPath }
$ini = [regex]::Replace($tpl, '(?m)^SystemPath=[^\r\n]*', $evaluator)
if ([regex]::Matches($tpl, '(?m)^SystemPath=').Count -ne 2) { Fail 'template does not contain exactly two SystemPath lines' }
$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $root 'freeldr.ini'), $ini, $utf8)
[IO.File]::WriteAllText((Join-Path $loader 'freeldr.ini'), $ini, $utf8)

Copy-Item -LiteralPath $need.Kernel  -Destination (Join-Path $paydir 'WRKX86.EXE')
Copy-Item -LiteralPath $need.Ksym    -Destination (Join-Path $paydir 'WRKX86.PDB')
Copy-Item -LiteralPath $need.Hal     -Destination (Join-Path $paydir 'HALMACPI.DLL')
Copy-Item -LiteralPath $need.License -Destination (Join-Path $paydir 'LICENSE.TXT')
Copy-Item -LiteralPath $need.Install -Destination (Join-Path $paydir 'INSTALL.TXT')
Copy-Item -LiteralPath $need.Gpl     -Destination (Join-Path $root 'COPYING-GPL.TXT')

$readme = @'
WRK FreeLoader BOOT DISC - not a Windows installer, not a standalone WRK OS.

BOOTS: ReactOS FreeLoader (GPL - see COPYING-GPL.TXT; WRK license in
payload\LICENSE.TXT) from loader\freeldr.sys with freeldr.ini menu.

This disc alone CANNOT boot WRK. It expects a licensed Windows Server
2003 SP1 x86 installation already present at the SystemPath in
freeldr.ini, with its SYSTEM hive, NLS data, boot drivers, BOOTVID/KDCOM
and smss.exe on that disk, plus WRKX86.EXE and HALMACPI.DLL copied into
the installed System32 (see payload\INSTALL.TXT). A missing-hive or
missing-file error means the base OS is absent - it does not mean WRK
loaded.
'@
[IO.File]::WriteAllText((Join-Path $root 'README.TXT'), $readme, $utf8)
Write-Log "staged iso-root under $root"

# ---- mkisofs ----------------------------------------------------------------
Invoke-Native $need.Mkisofs @('-iso-level','3','-J','-V','WRK_BOOT',
    '-b','loader/isoboot.bin','-no-emul-boot','-boot-load-size','4',
    '-c','loader/boot.catalog','-o',$isoPath,$root)

Write-Log "ISO written: $isoPath ($((Get-Item -LiteralPath $isoPath).Length) bytes)"
Write-Log 'Done. This is a bootable FreeLoader disc; WRK still requires a licensed installed Server 2003 SP1 base.'
exit 0
