<#
.SYNOPSIS
Copies the boot component source snapshot without moving the original files.
#>
[CmdletBinding()]
param(
    [string]$SourceRoot = (Join-Path $PSScriptRoot '../..'),
    [string]$DestinationRoot = (Join-Path $PSScriptRoot '..')
)

$ErrorActionPreference = 'Stop'
$sourceDirectory = (Resolve-Path -LiteralPath $SourceRoot).Path
$destinationDirectory = [IO.Path]::GetFullPath($DestinationRoot)
if ($sourceDirectory.TrimEnd('\', '/') -eq $destinationDirectory.TrimEnd('\', '/')) {
    throw 'SourceRoot and DestinationRoot must be different directories.'
}
if (-not (Test-Path -LiteralPath (Join-Path $sourceDirectory 'hal/hal.spec'))) {
    throw 'SourceRoot must be the ReactOS repository root.'
}
$selection = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '../source-paths.json') | ConvertFrom-Json
$rootCmake = Get-Content -Raw -LiteralPath (Join-Path $sourceDirectory 'CMakeLists.txt')
$targetStart = $rootCmake.IndexOf('    # We don''t need CMake importlib handling.')
$targetFinish = $rootCmake.IndexOf('    #begin with boot')
if ($targetStart -lt 0 -or $targetFinish -le $targetStart) {
    throw 'The upstream CMake target initialization changed; review the focused build before refreshing.'
}
$inputs = [Collections.Generic.List[string]]::new()
foreach ($directory in $selection.directories) {
    Get-ChildItem -LiteralPath (Join-Path $sourceDirectory $directory) -File -Recurse |
        ForEach-Object { $inputs.Add($_.FullName) }
}
foreach ($file in $selection.files) {
    $inputs.Add((Get-Item -LiteralPath (Join-Path $sourceDirectory $file)).FullName)
}

$records = foreach ($inputFile in ($inputs | Sort-Object -Unique)) {
    $relative = $inputFile.Substring($sourceDirectory.Length + 1).Replace('\', '/')
    $outputFile = Join-Path $destinationDirectory $relative
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputFile)) | Out-Null
    Copy-Item -LiteralPath $inputFile -Destination $outputFile -Force
    [ordered]@{
        path = $relative
        sha256 = (Get-FileHash -LiteralPath $outputFile -Algorithm SHA256).Hash.ToLowerInvariant()
        bytes = (Get-Item -LiteralPath $outputFile).Length
    }
}
$revision = & git -C $sourceDirectory rev-parse HEAD
if ($LASTEXITCODE -ne 0) { $revision = 'unknown' }
$utf8 = [Text.UTF8Encoding]::new($false)
[IO.Directory]::CreateDirectory((Join-Path $destinationDirectory 'cmake')) | Out-Null
$targetInit = '# Target initialization extracted from the ReactOS root CMakeLists.txt.' + "`n" +
    $rootCmake.Substring($targetStart, $targetFinish - $targetStart)
[IO.File]::WriteAllText((Join-Path $destinationDirectory 'cmake/reactos-target.cmake'), $targetInit, $utf8)
$hostInit = Get-Content -Raw -LiteralPath (Join-Path $sourceDirectory 'sdk/cmake/host-tools.cmake')
$hostInit = $hostInit.Replace(
    'list(APPEND HOST_TOOLS asmpp bin2c widl gendib cabman fatten hpp isohybrid mkhive mkisofs obj2bin spec2def geninc mkshelllink txt2nls utf16le xml2sdb)',
    'list(APPEND HOST_TOOLS asmpp bin2c widl hpp mkhive obj2bin spec2def geninc txt2nls utf16le)')
$hostInit = $hostInit -replace '(?m)^\s*if \(ARCH STREQUAL "i386"\)\r?\n\s*list\(APPEND HOST_TOOLS rsym\)\r?\n\s*endif\(\)\r?\n', ''
$hostInit = $hostInit.Replace('            -UCMAKE_TOOLCHAIN_FILE',
    '            -UCMAKE_TOOLCHAIN_FILE' + "`n" + '            -DBOOTLDR_EX_BUILD_CODEGEN=ON')
[IO.File]::WriteAllText((Join-Path $destinationDirectory 'cmake/host-tools.cmake'),
    '# Focused host-tools orchestration adapted from sdk/cmake/host-tools.cmake.' + "`n" + $hostInit, $utf8)
$derived = foreach ($pair in @(
    @('cmake/reactos-target.cmake', 'CMakeLists.txt'),
    @('cmake/host-tools.cmake', 'sdk/cmake/host-tools.cmake'))) {
    [ordered]@{
        path = $pair[0]
        sha256 = (Get-FileHash -LiteralPath (Join-Path $destinationDirectory $pair[0]) -Algorithm SHA256).Hash.ToLowerInvariant()
        source_path = $pair[1]
        source_sha256 = (Get-FileHash -LiteralPath (Join-Path $sourceDirectory $pair[1]) -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}
$manifest = [ordered]@{
    format = 1
    source = 'ReactOS working tree (including local changes)'
    base_commit = "$revision"
    files = @($records)
    derived_build_helpers = @($derived)
}
[IO.File]::WriteAllText((Join-Path $destinationDirectory 'source-manifest.json'),
    ($manifest | ConvertTo-Json -Depth 5) + "`n", $utf8)
Write-Output "Copied $($records.Count) source files to $destinationDirectory"
Write-Output 'Only the paths in source-paths.json were refreshed; originals were retained.'
