#Requires -Version 5.1
<#
.SYNOPSIS
  Assemble the WRK BIOS bootstrap (stage1 + stage2) and pack a raw
  1.44 MB floppy image. No network, no elevation, no disk writes beyond
  new files inside -OutputDirectory.

.DESCRIPTION
  Outputs: stage1.bin (512 B), stage2.bin (4096 B), stage1.lst,
  stage2.lst, bootloader.img (1474560 B: stage1 at sector 0, stage2 at
  sectors 1-8, rest zero). Refuses to run if the target files or a
  nonempty output directory already exist - pick a fresh
  -OutputDirectory for rebuilds. This image is a fixed-sector-layout RAW
  floppy, not a FAT filesystem and not an OS.
#>
[CmdletBinding()]
param(
    [string]$NasmPath = '',
    [string]$OutputDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $RepoRoot 'artifacts\bootloader'
}
$LogDir   = Join-Path $RepoRoot 'artifacts\logs'
$LogFile  = Join-Path $LogDir ('build-bootloader-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))

function Write-Log([string]$Msg) {
    $line = '{0:HH:mm:ss} {1}' -f (Get-Date), $Msg
    Add-Content -LiteralPath $LogFile -Value $line
    Write-Host $line
}
function Fail([string]$Msg) {
    Write-Log "ERROR: $Msg"
    exit 1
}

function Invoke-Native([string]$Exe, [string[]]$ArgList) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
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
    Write-Log ('{0} {1}' -f (Split-Path $Exe -Leaf), ($ArgList -join ' '))
    foreach ($l in ($out.TrimEnd() -split "`r?`n")) { if ($l) { Write-Log "  | $l" } }
    foreach ($l in ($err.TrimEnd() -split "`r?`n")) { if ($l) { Write-Log "  ! $l" } }
    Write-Log "  -> exit $($proc.ExitCode)"
    if ($proc.ExitCode -ne 0) { Fail "$Exe exited $($proc.ExitCode)" }
}

if (-not (Test-Path -LiteralPath $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
Write-Log "Build-Bootloader starting; log: $LogFile"

# ---- locate NASM --------------------------------------------------------
if (-not $NasmPath) {
    $candidates = @('C:\Strawberry\c\bin\nasm.exe')
    $onPath = Get-Command nasm.exe -ErrorAction SilentlyContinue
    if ($onPath) { $candidates += $onPath.Source }
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c -PathType Leaf) { $NasmPath = $c; break }
    }
}
if (-not $NasmPath -or -not (Test-Path -LiteralPath $NasmPath -PathType Leaf)) {
    Fail 'nasm.exe not found - install NASM or pass -NasmPath.'
}
Write-Log "NASM: $NasmPath"

# ---- sources + output dir ------------------------------------------------
$src1 = Join-Path $PSScriptRoot 'stage1.asm'
$src2 = Join-Path $PSScriptRoot 'stage2.asm'
foreach ($s in @($src1, $src2)) {
    if (-not (Test-Path -LiteralPath $s -PathType Leaf)) { Fail "missing source: $s" }
}
$targets = @('stage1.bin','stage2.bin','stage1.lst','stage2.lst','bootloader.img') |
    ForEach-Object { Join-Path $OutputDirectory $_ }
foreach ($t in $targets) {
    if (Test-Path -LiteralPath $t) { Fail "output already exists: $t (use a fresh -OutputDirectory)" }
}
if (Test-Path -LiteralPath $OutputDirectory) {
    if (@(Get-ChildItem -LiteralPath $OutputDirectory -Force).Count -gt 0) {
        Fail "output directory is not empty: $OutputDirectory"
    }
} else {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

# ---- assemble ------------------------------------------------------------
Invoke-Native $NasmPath @('-f','bin','-o',(Join-Path $OutputDirectory 'stage1.bin'),
    '-l',(Join-Path $OutputDirectory 'stage1.lst'), $src1)
Invoke-Native $NasmPath @('-f','bin','-o',(Join-Path $OutputDirectory 'stage2.bin'),
    '-l',(Join-Path $OutputDirectory 'stage2.lst'), $src2)

# ---- validate layout ------------------------------------------------------
$s1 = [IO.File]::ReadAllBytes((Join-Path $OutputDirectory 'stage1.bin'))
$s2 = [IO.File]::ReadAllBytes((Join-Path $OutputDirectory 'stage2.bin'))
if ($s1.Length -ne 512)  { Fail "stage1.bin is $($s1.Length) bytes, expected 512" }
if ($s2.Length -ne 4096) { Fail "stage2.bin is $($s2.Length) bytes, expected 4096" }
if ($s1[510] -ne 0x55 -or $s1[511] -ne 0xAA) { Fail 'stage1.bin missing 55AA signature' }
if ([Text.Encoding]::ASCII.GetString($s1[5..8]) -ne 'WRK1') { Fail 'stage1.bin missing WRK1 marker at 5..8' }
if ([Text.Encoding]::ASCII.GetString($s2[2..5]) -ne 'WRK2') { Fail 'stage2.bin missing WRK2 magic at 2..5' }
Write-Log 'validated: stage1=512B sig=55AA marker=WRK1; stage2=4096B magic=WRK2'

# ---- write 1.44 MB raw floppy image ----------------------------------------
$imgPath = Join-Path $OutputDirectory 'bootloader.img'
$fs = New-Object IO.FileStream($imgPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
try {
    $fs.SetLength(1474560)          # 2880 * 512
    $fs.Position = 0
    $fs.Write($s1, 0, $s1.Length)
    $fs.Position = 512              # stage2 at sector 1 (CHS 0/0/2)
    $fs.Write($s2, 0, $s2.Length)
} finally {
    $fs.Close()
}
Write-Log "wrote $imgPath (1474560 bytes: stage1@0, stage2@512, rest zero)"
Write-Log 'Done.'
exit 0
