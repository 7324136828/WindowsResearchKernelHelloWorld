#Requires -Version 5.1
<#
.SYNOPSIS
Generate isolated experimental WRK registry hives and early NLS boot files.
.DESCRIPTION
Uses the supplied ReactOS host generators without changing their sources,
example hives, or the original ISO. SYSTEM includes the supplied root/PCI
arbiter allocation and reservation data needed by WRK Plug and Play phase 0.
Default SYSTEM contains ramdisk and cdfs boot-start services.
A Core mode without drivers is also available for early handoff diagnostics.
.PARAMETER BootMode
Ramdisk (default) selects ramdisk and cdfs. Core selects no boot drivers.
.PARAMETER BootDriver
Optional ramdisk and cdfs boot services; matching binaries and supported
loader/kernel ramdisk handoff must be supplied separately by the packager.
#>
[CmdletBinding()]
param(
    [string]$OutputDirectory = '',
    [ValidateSet('Ramdisk', 'Core')][string]$BootMode = 'Ramdisk',
    [ValidateSet('ramdisk', 'cdfs')][string[]]$BootDriver = @(),
    [switch]$TextModeSetup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$selectedDrivers = @()
if ($PSBoundParameters.ContainsKey('BootDriver')) {
    $selectedDrivers = @($BootDriver)
} elseif ($BootMode -eq 'Ramdisk') {
    $selectedDrivers = @('ramdisk', 'cdfs')
}
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$artifactRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'artifacts'))
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $artifactRoot 'wrk-hello-hives'
} elseif (-not [IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory = Join-Path $repoRoot $OutputDirectory
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if (-not $OutputDirectory.StartsWith($artifactRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Hive output must be a subdirectory of this repository artifacts directory.'
}
$bundleRoot = Join-Path $repoRoot '_bootldr_ex'
$hostToolRoot = Join-Path $bundleRoot 'build-host\bin'
$mkhive = Join-Path $hostToolRoot 'mkhive.exe'
$txt2nls = Join-Path $hostToolRoot 'txt2nls.exe'
$seed = Join-Path $repoRoot 'hello_world\boot\wrk-hello.inf'
$arbiterSeed = Join-Path $bundleRoot 'boot\bootdata\hivesys.inf'
$nlsRoot = Join-Path $bundleRoot 'media\nls'
foreach ($inputFile in @($mkhive, $txt2nls, $seed, $arbiterSeed,
    (Join-Path $nlsRoot 'src\c_1252.txt'),
    (Join-Path $nlsRoot 'src\c_437.txt'),
    (Join-Path $nlsRoot 'l_intl.nls'))) {
    if (-not (Test-Path -LiteralPath $inputFile -PathType Leaf)) {
        throw "Missing input: $inputFile. Build _bootldr_ex bootldr_data first."
    }
}
$hiveDirectory = Join-Path $OutputDirectory 'Config'
$nlsDirectory = Join-Path $OutputDirectory 'Nls'
$infDirectory = Join-Path $OutputDirectory 'inf'
New-Item -ItemType Directory -Path $hiveDirectory, $nlsDirectory, $infDirectory -Force | Out-Null
$logPath = Join-Path $OutputDirectory 'generation.log'
Set-Content -LiteralPath $logPath -Value 'Generating experimental WRK hives and NLS data.' -Encoding UTF8

function Invoke-Generator([string]$Executable, [string[]]$Arguments) {
    $output = & $Executable @Arguments 2>&1
    $result = $LASTEXITCODE
    $output | Out-String | Add-Content -LiteralPath $logPath -Encoding UTF8
    if ($result -ne 0) { throw "Generator failed with exit code ${result}: $Executable" }
}
$convertedSeed = Join-Path $infDirectory 'wrk-hello.inf'
[IO.File]::WriteAllText($convertedSeed, [IO.File]::ReadAllText($seed), [Text.Encoding]::Unicode)
# Import complete AddReg records, including all resource-list continuation
# lines. Using the existing data avoids duplicating opaque binary descriptors
# or importing unrelated settings from the full ReactOS SYSTEM seed.
$arbiterInf = Join-Path $infDirectory 'arbiters.inf'
$arbiterLines = @('[Version]', 'Signature = "$Windows NT$"', '', '[AddReg]')
$arbiterRecords = 0
$continuation = $false
foreach ($line in [IO.File]::ReadAllLines($arbiterSeed)) {
    $isArbiter = $line -match '^HKLM,"SYSTEM\\CurrentControlSet\\Control\\Arbiters(?:\\|")'
    if ($isArbiter -or $continuation) {
        if ($isArbiter) { $arbiterRecords++ }
        $arbiterLines += $line
        $continuation = $line.TrimEnd().EndsWith('\')
    }
}
if ($continuation -or $arbiterRecords -ne 6) {
    throw 'Expected six complete arbiter AddReg records in the supplied hivesys.inf.'
}
[IO.File]::WriteAllLines($arbiterInf, $arbiterLines, [Text.Encoding]::Unicode)
$driverInf = Join-Path $infDirectory 'boot-drivers.inf'
$driverLines = @('[Version]', 'Signature = "$Windows NT$"', '', '[AddReg]')
foreach ($driver in @($selectedDrivers | Select-Object -Unique)) {
    $serviceKey = 'SYSTEM\CurrentControlSet\Services\' + $driver
    $driverLines += 'HKLM,"' + $serviceKey + '","Start",0x00010001,0'
    $driverLines += 'HKLM,"' + $serviceKey + '","Type",0x00010001,' + $(if ($driver -eq 'cdfs') { '2' } else { '1' })
    $driverLines += 'HKLM,"' + $serviceKey + '","ErrorControl",0x00010001,3'
    $driverLines += 'HKLM,"' + $serviceKey + '","ImagePath",0x00020000,"System32\Drivers\' + $driver + '.sys"'
    $driverLines += 'HKLM,"' + $serviceKey + '","Group",0x00000000,"' + $(if ($driver -eq 'cdfs') { 'Boot File System' } else { 'Boot Bus Extender' }) + '"'
}
if ($TextModeSetup) {
    # Pair the generated registry state with the explicit setup loader handoff.
    $driverLines += 'HKLM,"SYSTEM\Setup","SetupType",0x00010001,1'
    $driverLines += 'HKLM,"SYSTEM\Setup","SystemSetupInProgress",0x00010001,1'
}
[IO.File]::WriteAllLines($driverInf, $driverLines, [Text.Encoding]::Unicode)
Invoke-Generator $mkhive @('-h:SYSTEM,SOFTWARE,DEFAULT,SAM,SECURITY', '-u', ('-d:' + $hiveDirectory), $convertedSeed, $arbiterInf, $driverInf)
foreach ($codePage in @('1252', '437')) {
    Invoke-Generator $txt2nls @((Join-Path $nlsRoot ('src\c_' + $codePage + '.txt')), (Join-Path $nlsDirectory ('c_' + $codePage + '.nls')))
}
Copy-Item -LiteralPath (Join-Path $nlsRoot 'l_intl.nls') -Destination (Join-Path $nlsDirectory 'l_intl.nls') -Force

# Check the actual binary hive header, root cell, and contiguous hbin chain.
# This detects invalid or truncated outputs before ISO assembly.
function Test-Hive([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 8192 -or [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne 'regf') {
        throw "Not a binary hive: $Path"
    }
    if ([BitConverter]::ToUInt32($bytes, 4) -ne [BitConverter]::ToUInt32($bytes, 8)) {
        throw "Dirty hive sequence numbers: $Path"
    }
    [uint32]$checksum = 0
    for ($offset = 0; $offset -lt 508; $offset += 4) {
        $checksum = $checksum -bxor [BitConverter]::ToUInt32($bytes, $offset)
    }
    if ($checksum -eq [uint32]::MaxValue) { $checksum-- }
    if ($checksum -eq 0) { $checksum = 1 }
    if ($checksum -ne [BitConverter]::ToUInt32($bytes, 508)) { throw "Invalid hive checksum: $Path" }
    $rootCell = 4096 + [BitConverter]::ToUInt32($bytes, 36)
    if ($rootCell + 6 -gt $bytes.Length -or [Text.Encoding]::ASCII.GetString($bytes, $rootCell + 4, 2) -ne 'nk') {
        throw "Invalid hive root cell: $Path"
    }
    $hiveEnd = 4096 + [BitConverter]::ToUInt32($bytes, 40)
    if ($hiveEnd -ne $bytes.Length) { throw "Unexpected hive length: $Path" }
    for ($binOffset = 4096; $binOffset -lt $hiveEnd;) {
        if ([Text.Encoding]::ASCII.GetString($bytes, $binOffset, 4) -ne 'hbin' -or
            [BitConverter]::ToUInt32($bytes, $binOffset + 4) -ne ($binOffset - 4096)) {
            throw "Invalid hive bin chain: $Path"
        }
        $binSize = [BitConverter]::ToUInt32($bytes, $binOffset + 8)
        if ($binSize -lt 4096 -or ($binSize % 4096) -ne 0 -or $binOffset + $binSize -gt $hiveEnd) {
            throw "Invalid hive bin size: $Path"
        }
        $binOffset += $binSize
    }
    [PSCustomObject]@{ Name = [IO.Path]::GetFileName($Path); Size = $bytes.Length;
        Major = [BitConverter]::ToUInt32($bytes, 20); Minor = [BitConverter]::ToUInt32($bytes, 24);
        HeaderRootAndBinsValid = $true; SHA256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
}
$hiveResults = @(foreach ($hive in @('SYSTEM', 'SOFTWARE', 'DEFAULT', 'SAM', 'SECURITY')) {
    Test-Hive (Join-Path $hiveDirectory $hive)
})
foreach ($codePage in @('1252', '437')) {
    $tableBytes = [IO.File]::ReadAllBytes((Join-Path $nlsDirectory ('c_' + $codePage + '.nls')))
    if ([BitConverter]::ToUInt16($tableBytes, 2) -ne [int]$codePage) { throw "Wrong NLS codepage header: $codePage" }
}
[ordered]@{
    Purpose = 'Experimental WRK native Hello World boot; runtime execution unverified'
    BootMode = $BootMode
    TextModeSetup = [bool]$TextModeSetup
    BootDrivers = @($selectedDrivers)
    RequiresOptions = $(if ($selectedDrivers -contains 'ramdisk') { '/MININT /SOS /INRAM /RDEXPORTASCD' } else { '/MININT /SOS' })
    NativeProgram = '\SystemRoot\System32\smss.exe'
    Hives = $hiveResults
    Nls = @(Get-ChildItem -LiteralPath $nlsDirectory -File | ForEach-Object {
        [PSCustomObject]@{ Name = $_.Name; Size = $_.Length;
            SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    })
    SeedSHA256 = (Get-FileHash -LiteralPath $seed -Algorithm SHA256).Hash
    ArbiterSeed = [ordered]@{
        Source = $arbiterSeed
        SourceSHA256 = (Get-FileHash -LiteralPath $arbiterSeed -Algorithm SHA256).Hash
        AddRegRecords = $arbiterRecords
        GeneratedINF = $arbiterInf
        GeneratedINFSHA256 = (Get-FileHash -LiteralPath $arbiterInf -Algorithm SHA256).Hash
    }
    Limitations = 'Without matching storage and filesystem drivers, these hives cannot make native SMSS reachable. Optional RAM-disk services require supported loader and WRK handoff.'
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'manifest.json') -Encoding UTF8
Write-Host "Generated and validated experimental hives and NLS: $OutputDirectory"
