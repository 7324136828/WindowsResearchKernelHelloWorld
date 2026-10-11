#Requires -Version 5.1
# Read-only ISO9660 payload validation of the packaged WRKSYS.ISO RAM disk.
# Only inner-validation.log and inner-validation.json are written.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$PackageDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$package = (Resolve-Path -LiteralPath $PackageDirectory).Path.TrimEnd('\')
$isoPath = Join-Path $package 'iso-root\WRKSYS.ISO'
$systemRoot = (Resolve-Path -LiteralPath (Join-Path $package 'system-root')).Path.TrimEnd('\')
$manifest = Get-Content -LiteralPath (Join-Path $package 'manifest.json') -Raw | ConvertFrom-Json
$logPath = Join-Path $package 'inner-validation.log'
$jsonPath = Join-Path $package 'inner-validation.json'
$logLines = New-Object 'Collections.Generic.List[string]'
$results = New-Object 'Collections.Generic.List[object]'
$isoBytes = [IO.File]::ReadAllBytes($isoPath)
$sha256 = [Security.Cryptography.SHA256]::Create()
function Get-BytesHash([byte[]]$Bytes) { ([BitConverter]::ToString($sha256.ComputeHash($Bytes))).Replace('-', '') }
function Write-Check([string]$Line) { $logLines.Add($Line); Write-Output $Line }
function Assert-ImageRange([long]$Offset, [long]$Length) {
    if ($Offset -lt 0 -or $Length -lt 0 -or $Offset + $Length -gt $isoBytes.Length) {
        throw "ISO range outside image: offset=$Offset length=$Length"
    }
}
function Read-BothEndian32([int]$Offset) {
    Assert-ImageRange $Offset 8
    $le = [BitConverter]::ToUInt32($isoBytes, $Offset)
    $be = ([uint64]$isoBytes[$Offset+4] -shl 24) -bor ([uint64]$isoBytes[$Offset+5] -shl 16) -bor
          ([uint64]$isoBytes[$Offset+6] -shl 8) -bor [uint64]$isoBytes[$Offset+7]
    if ($le -ne $be) { throw "ISO endian-value mismatch at $Offset" }
    return $le
}
try {
    $isoHashBefore = Get-BytesHash $isoBytes
    Write-Check "Inner ISO: $isoPath"
    Write-Check "Image length: $($isoBytes.Length); SHA256: $isoHashBefore"
    if ($isoBytes.Length -ne $manifest.InnerImageLength -or $isoHashBefore -ne $manifest.InnerImageSHA256) {
        throw 'Inner image differs from the packaging manifest'
    }
    $pvd = 16 * 2048
    Assert-ImageRange $pvd 2048
    if ($isoBytes[$pvd] -ne 1 -or [Text.Encoding]::ASCII.GetString($isoBytes, $pvd+1, 5) -ne 'CD001' -or $isoBytes[$pvd+6] -ne 1) {
        throw 'Expected ISO9660 primary volume descriptor at sector 16'
    }
    $blockSize = [BitConverter]::ToUInt16($isoBytes, $pvd+128)
    if ($blockSize -ne 2048 -or $isoBytes[$pvd+130] -ne 8 -or $isoBytes[$pvd+131] -ne 0) {
        throw 'Unexpected ISO9660 logical block size'
    }
    $volumeBlocks = Read-BothEndian32 ($pvd+80)
    if ([long]$volumeBlocks * 2048 -ne $isoBytes.Length) { throw 'ISO image size disagrees with its volume space size' }
    $volumeId = [Text.Encoding]::ASCII.GetString($isoBytes, $pvd+40, 32).Trim()
    Write-Check "ISO9660 PVD valid; volume=$volumeId; logical-blocks=$volumeBlocks"

    # Adapted from artifacts/checks/verify-freeldr-iso.ps1; add range/endian checks.
    $files = @{}
    $visited = @{}
    function Read-IsoDirectory([uint32]$Lba, [uint32]$Length, [string]$Prefix) {
        $base = [long]$Lba * 2048
        Assert-ImageRange $base $Length
        $directoryKey = "$Lba/$Length"
        if ($visited.ContainsKey($directoryKey)) { throw "Repeated ISO directory extent: $directoryKey" }
        $visited[$directoryKey] = $true
        $pos = 0
        while ($pos -lt $Length) {
            $offset = [int]($base + $pos)
            $recordLength = [int]$isoBytes[$offset]
            if ($recordLength -eq 0) { $pos = [int]([Math]::Floor($pos/2048) * 2048 + 2048); continue }
            if ($recordLength -lt 34 -or $pos+$recordLength -gt $Length -or ($pos%2048)+$recordLength -gt 2048) {
                throw "Invalid ISO directory record at $offset"
            }
            $fileLba = Read-BothEndian32 ($offset+2)
            $fileLength = Read-BothEndian32 ($offset+10)
            $flags = $isoBytes[$offset+25]
            $nameLength = [int]$isoBytes[$offset+32]
            if ($nameLength -lt 1 -or 33+$nameLength -gt $recordLength) { throw "Invalid ISO filename at $offset" }
            $isDotEntry = $nameLength -eq 1 -and $isoBytes[$offset+33] -le 1
            if (!$isDotEntry) {
                $name = [Text.Encoding]::ASCII.GetString($isoBytes, $offset+33, $nameLength)
                $path = $Prefix + '/' + $name
                Assert-ImageRange ([long]$fileLba*2048) $fileLength
                if ($flags -band 2) { Read-IsoDirectory $fileLba $fileLength $path }
                else {
                    if ($flags -band 0x80) { throw "Unexpected multi-extent file: $path" }
                    if ($files.ContainsKey($path)) { throw "Duplicate ISO file: $path" }
                    $files[$path] = [pscustomobject]@{ Lba=$fileLba; Length=$fileLength }
                }
            }
            $pos += $recordLength
        }
    }
    Read-IsoDirectory (Read-BothEndian32 ($pvd+158)) (Read-BothEndian32 ($pvd+166)) ''
    $stagedFiles = @(Get-ChildItem -LiteralPath $systemRoot -Recurse -File)
    if ($files.Count -ne $stagedFiles.Count) { throw "ISO files=$($files.Count) differ from staged files=$($stagedFiles.Count)" }
    $expectedManifest = @($manifest.Inputs | Where-Object { $_.Name.StartsWith('WRK/') })
    if ($expectedManifest.Count -ne $stagedFiles.Count) { throw 'Manifest system-file count differs from the staged tree' }
    foreach ($file in $stagedFiles | Sort-Object FullName) {
        $relative = $file.FullName.Substring($systemRoot.Length+1).Replace('\', '/')
        $isoBase = '/' + [regex]::Replace($relative.ToUpperInvariant(), '[^A-Z0-9_./]', '_')
        $isoName = $isoBase + ';1'
        if (!$files.ContainsKey($isoName) -and $files.ContainsKey($isoBase + '.;1')) {
            throw "FreeLoader cannot find extensionless file ${relative}: ISO record has trailing period ($isoBase.;1); package with -omit-period"
        }
        if (!$files.ContainsKey($isoName)) { throw "Missing ISO payload file: $relative ($isoName)" }
        $entry = $files[$isoName]
        if ($entry.Length -ne $file.Length) { throw "File length differs: $relative" }
        $actual = New-Object byte[] $entry.Length
        [Array]::Copy($isoBytes, [long]$entry.Lba*2048, $actual, 0, $entry.Length)
        $expected = [IO.File]::ReadAllBytes($file.FullName)
        for ($byteOffset=0; $byteOffset -lt $expected.Length; $byteOffset++) {
            if ($expected[$byteOffset] -ne $actual[$byteOffset]) { throw "Payload differs: $relative at offset $byteOffset" }
        }
        $fileHash = Get-BytesHash $actual
        $manifestEntry = @($expectedManifest | Where-Object { $_.Name -eq $relative })
        if ($manifestEntry.Count -ne 1 -or $manifestEntry[0].SHA256 -ne $fileHash -or $manifestEntry[0].Size -ne $entry.Length) {
            throw "Payload disagrees with packaging manifest: $relative"
        }
        $results.Add([pscustomobject]@{ File=$relative; ISOName=$isoName; Lba=$entry.Lba; Length=$entry.Length; SHA256=$fileHash; ExactBytes=$true })
        Write-Check "EXACT $relative ($($entry.Length) bytes, SHA256=$fileHash)"
    }
    $isoHashAfter = (Get-FileHash -LiteralPath $isoPath -Algorithm SHA256).Hash
    if ($isoHashAfter -ne $isoHashBefore) { throw 'Inner ISO changed during verification' }
    Write-Check "PASS: all $($results.Count) system payload files exactly match staged bytes and manifest; FreeLoader filenames match; inner ISO unchanged."
    [ordered]@{ Passed=$true; ISO=$isoPath; Length=$isoBytes.Length; SHA256=$isoHashBefore; VolumeID=$volumeId;
                LogicalBlocks=$volumeBlocks; FileCount=$results.Count; Files=@($results.ToArray()); FreeLoaderFilenamesMatch=$true; ISOUnchanged=$true } |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
} catch {
    Write-Check "FAIL: $($_.Exception.Message)"
    [ordered]@{ Passed=$false; ISO=$isoPath; Error=$_.Exception.Message; Files=@($results.ToArray()) } |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    throw
} finally {
    $logLines | Set-Content -LiteralPath $logPath -Encoding UTF8
    $sha256.Dispose()
}
