#Requires -Version 5.1
<#
.SYNOPSIS
Build the experimental native x86 SMSS/NTDLL pair with WRK's compiler.
.PARAMETER ToolDirectory
Directory containing CL.EXE, ML.EXE and LINK.EXE. Defaults to WRK TOOLS\X86.
#>
[CmdletBinding()]
param([string]$ToolDirectory = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$sampleRoot = $PSScriptRoot
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $sampleRoot '..')).Path
if (-not $ToolDirectory) {
    $ToolDirectory = Join-Path $repoRoot 'WRK-V1.2\TOOLS\X86'
}
$ToolDirectory = (Resolve-Path -LiteralPath $ToolDirectory).Path
$ntdllRoot = Join-Path $sampleRoot 'ntdll'
$smssRoot = Join-Path $sampleRoot 'smss'
$ntdllBuild = Join-Path $ntdllRoot 'build'
$smssBuild = Join-Path $smssRoot 'build'
$tablePath = Join-Path $repoRoot 'WRK-V1.2\BASE\NTOS\KE\I386\SYSTABLE.ASM'

foreach ($toolName in @('CL.EXE', 'ML.EXE', 'LINK.EXE')) {
    if (-not (Test-Path -LiteralPath (Join-Path $ToolDirectory $toolName) -PathType Leaf)) {
        throw "Missing build tool: $toolName in $ToolDirectory"
    }
}
foreach ($sourcePath in @(
    $tablePath,
    (Join-Path $ntdllRoot 'ntdll.c'), (Join-Path $ntdllRoot 'native.h'),
    (Join-Path $ntdllRoot 'startup.asm'), (Join-Path $ntdllRoot 'syscalls.asm'),
    (Join-Path $ntdllRoot 'ntdll.def'),
    (Join-Path $smssRoot 'smss.c'), (Join-Path $smssRoot 'native.h')
)) {
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Missing source: $sourcePath"
    }
}

# Parse actual table entries, excluding the TABLE_ENTRY macro definition.
# Service numbers are specific to this WRK kernel, not the host Windows OS.
$services = @([regex]::Matches(
    (Get-Content -LiteralPath $tablePath -Raw),
    '(?m)^\s*TABLE_ENTRY\s+([A-Za-z0-9_]+),\s*[0-9]+,\s*([0-9]+)\s*$'
))
$tableEnd = [regex]::Match((Get-Content -LiteralPath $tablePath -Raw),
    '(?m)^\s*TABLE_END\s+([0-9]+)\s*$')
if (-not $tableEnd.Success -or $services.Count -ne ([int]$tableEnd.Groups[1].Value + 1)) {
    throw 'Cannot validate the WRK system service table.'
}
$requiredCalls = [ordered]@{
    Continue = 2
    DelayExecution = 2
    DisplayString = 1
    ProtectVirtualMemory = 5
    RaiseException = 3
    TerminateProcess = 2
}
$includeLines = @('; Generated from WRK KE\I386\SYSTABLE.ASM. Do not edit.')
$manifest = @()
foreach ($callName in $requiredCalls.Keys) {
    $serviceNumber = -1
    for ($index = 0; $index -lt $services.Count; $index++) {
        if ($services[$index].Groups[1].Value -ceq $callName) {
            if ($serviceNumber -ne -1) { throw "Duplicate service: Nt$callName" }
            $serviceNumber = $index
            if ([int]$services[$index].Groups[2].Value -ne $requiredCalls[$callName]) {
                throw "Unexpected argument count for Nt$callName"
            }
        }
    }
    if ($serviceNumber -lt 0) { throw "Missing WRK service: Nt$callName" }
    $includeLines += ('WRK_NT{0} EQU {1}' -f $callName.ToUpperInvariant(), $serviceNumber)
    $manifest += [PSCustomObject]@{
        Name = "Nt$callName"
        Number = $serviceNumber
        ArgumentBytes = $requiredCalls[$callName] * 4
    }
}

New-Item -ItemType Directory -Path $ntdllBuild, $smssBuild -Force | Out-Null
$logPath = Join-Path $sampleRoot 'build.log'
Set-Content -LiteralPath $logPath -Value 'Building native WRK x86 Hello World pair.' -Encoding ASCII
[IO.File]::WriteAllLines((Join-Path $ntdllBuild 'wrk_syscalls.inc'), $includeLines,
    [Text.Encoding]::ASCII)
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $ntdllBuild 'syscalls.json')
Get-FileHash -LiteralPath $tablePath -Algorithm SHA256 |
    Select-Object Path, Hash | ConvertTo-Json |
    Set-Content -LiteralPath (Join-Path $ntdllBuild 'syscall-table.json')

function Invoke-BuildTool([string]$ToolName, [string[]]$Arguments) {
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = Join-Path $ToolDirectory $ToolName
    # Arguments here are flags and Windows paths; none contain embedded quotes
    # or a trailing slash. No shell is involved.
    $startInfo.Arguments = (($Arguments | ForEach-Object {
        if ($_ -match '"') { throw 'Embedded quote in a build argument.' }
        if ($_ -match '\s') { '"' + $_ + '"' } else { $_ }
    }) -join ' ')
    $startInfo.WorkingDirectory = $sampleRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($variable in @('CL', '_CL_', 'LINK', '_LINK_', 'LIB', 'LIBPATH', 'INCLUDE')) {
        $startInfo.EnvironmentVariables.Remove($variable)
    }
    $commandText = "$ToolName $($startInfo.Arguments)"
    Write-Host $commandText
    Add-Content -LiteralPath $logPath -Value $commandText
    $process = [Diagnostics.Process]::Start($startInfo)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        foreach ($output in @($stdout.Result, $stderr.Result)) {
            if ($output) {
                Write-Host $output.TrimEnd()
                Add-Content -LiteralPath $logPath -Value $output.TrimEnd()
            }
        }
        if ($process.ExitCode -ne 0) {
            throw "$ToolName failed with exit code $($process.ExitCode). See $logPath"
        }
    } finally {
        $process.Dispose()
    }
}

# VC7.1's /GS is opt-in; /GS- is not recognized by this bundled compiler.
$compileFlags = @('/nologo', '/TC', '/c', '/W4', '/WX', '/Zl', '/Od', '/Zi')
Invoke-BuildTool 'CL.EXE' ($compileFlags + @(
    ('/Fo' + (Join-Path $ntdllBuild 'ntdll.obj')),
    ('/Fd' + (Join-Path $ntdllBuild 'compiler.pdb')),
    (Join-Path $ntdllRoot 'ntdll.c')
))
foreach ($assemblyName in @('startup', 'syscalls')) {
    Invoke-BuildTool 'ML.EXE' @('/nologo', '/c', '/coff',
        ('/I' + $ntdllBuild),
        ('/Fo' + (Join-Path $ntdllBuild "$assemblyName.obj")),
        (Join-Path $ntdllRoot "$assemblyName.asm"))
}
$linkFlags = @('/nologo', '/nodefaultlib', '/machine:x86', '/subsystem:native,5.02',
    '/incremental:no', '/opt:ref', '/release', '/debug')
Invoke-BuildTool 'LINK.EXE' ($linkFlags + @('/dll', '/entry:NtdllEntry@12', '/base:0x7c900000',
    ('/def:' + (Join-Path $ntdllRoot 'ntdll.def')),
    ('/out:' + (Join-Path $ntdllRoot 'ntdll.dll')),
    ('/implib:' + (Join-Path $ntdllBuild 'ntdll.lib')),
    ('/pdb:' + (Join-Path $ntdllBuild 'ntdll.pdb')),
    ('/map:' + (Join-Path $ntdllBuild 'ntdll.map')),
    (Join-Path $ntdllBuild 'ntdll.obj'),
    (Join-Path $ntdllBuild 'startup.obj'),
    (Join-Path $ntdllBuild 'syscalls.obj')
))
Invoke-BuildTool 'CL.EXE' ($compileFlags + @(
    ('/Fo' + (Join-Path $smssBuild 'smss.obj')),
    ('/Fd' + (Join-Path $smssBuild 'compiler.pdb')),
    (Join-Path $smssRoot 'smss.c')
))
Invoke-BuildTool 'LINK.EXE' ($linkFlags + @('/entry:NtProcessStartup@4', '/base:0x00400000',
    # LINK 7's .def aliases make undecorated import-library symbols. Bridge
    # them to the stdcall IAT symbols emitted by the C compiler.
    '/alternatename:__imp__NtDisplayString@4=__imp_NtDisplayString',
    '/alternatename:__imp__NtDelayExecution@8=__imp_NtDelayExecution',
    ('/out:' + (Join-Path $smssRoot 'smss.exe')),
    ('/pdb:' + (Join-Path $smssBuild 'smss.pdb')),
    ('/map:' + (Join-Path $smssBuild 'smss.map')),
    (Join-Path $smssBuild 'smss.obj'),
    (Join-Path $ntdllBuild 'ntdll.lib')
))

foreach ($binaryPath in @((Join-Path $ntdllRoot 'ntdll.dll'), (Join-Path $smssRoot 'smss.exe'))) {
    $image = [IO.File]::ReadAllBytes($binaryPath)
    $peOffset = [BitConverter]::ToInt32($image, 0x3c)
    if ([Text.Encoding]::ASCII.GetString($image, $peOffset, 4) -ne "PE`0`0" -or
        [BitConverter]::ToUInt16($image, $peOffset + 4) -ne 0x14c -or
        [BitConverter]::ToUInt16($image, $peOffset + 24) -ne 0x10b -or
        [BitConverter]::ToUInt16($image, $peOffset + 24 + 68) -ne 1) {
        throw "Output is not an x86 native PE32 image: $binaryPath"
    }
    Get-FileHash -LiteralPath $binaryPath -Algorithm SHA256 | Format-List
}
Write-Host 'Built hello_world\ntdll\ntdll.dll and hello_world\smss\smss.exe.'
Write-Host 'This is an experimental pair; guest boot execution has not been verified.'
