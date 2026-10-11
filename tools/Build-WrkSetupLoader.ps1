#Requires -Version 5.1
<#
.SYNOPSIS
Build an isolated i386 FreeLoader with the local NT 5.2 setup handoff changes.
.DESCRIPTION
Uses the sibling ReactOS checkout and existing MSVC/CMake/WinFlexBison tools.
Only rosload's generic ntldr/winldr.c is replaced by this repository's source.
The local setup-block header is copied into a target-specific include directory.
The original loader build and ISO are not changed. No tools are downloaded.
#>
[CmdletBinding()]
param(
    [string]$ReactOSRoot = (Join-Path $PSScriptRoot '..\..\reactos'),
    [string]$OutputDirectory = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$wrkRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$sourceRoot = (Resolve-Path -LiteralPath $ReactOSRoot).Path.TrimEnd('\')
$artifactRoot = [IO.Path]::GetFullPath((Join-Path $wrkRoot 'artifacts')).TrimEnd('\')
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $artifactRoot 'freeldr-setup-build-x86' }
if (-not [IO.Path]::IsPathRooted($OutputDirectory)) { $OutputDirectory = Join-Path $wrkRoot $OutputDirectory }
$buildRoot = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if (-not $buildRoot.StartsWith($artifactRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Loader build output must be a subdirectory of this repository artifacts directory.'
}
if ([string]::Equals($buildRoot, (Join-Path $artifactRoot 'freeldr-build-x86'), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The original FreeLoader build directory cannot be used for this isolated setup build.'
}
$overrideRoot = Join-Path $buildRoot 'overrides'
$includeRoot = Join-Path $overrideRoot 'include'
$overrideCmake = Join-Path $overrideRoot 'wrk-setup-loader.cmake'
$provenancePath = Join-Path $buildRoot 'provenance.json'
$localLoader = Join-Path $wrkRoot '_bootldr\freeldr\freeldr\ntldr\winldr.c'
$localLoaderHeader = Join-Path $wrkRoot '_bootldr\freeldr\freeldr\ntldr\winldr.h'
$localSetupHeader = Join-Path $wrkRoot '_bootldr_ex\sdk\include\reactos\arc\setupblk.h'
$isolatedSetupHeader = Join-Path $includeRoot 'arc\setupblk.h'
$cmakeExe = 'C:\Strawberry\c\bin\cmake.exe'
$vcvars = 'C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvarsall.bat'
$wfbRoot = Join-Path $wrkRoot '.tools\winflexbison-2.5.25'
$toolchain = Join-Path $sourceRoot 'toolchain-msvc.cmake'
foreach ($required in @($cmakeExe, $vcvars, $toolchain, $localLoader, $localLoaderHeader, $localSetupHeader,
    (Join-Path $sourceRoot '_bootldr\freeldr\freeldr\ntldr\winldr.c'),
    (Join-Path $wfbRoot 'win_bison.exe'), (Join-Path $wfbRoot 'win_flex.exe'))) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf) -or (Get-Item -LiteralPath $required).Length -eq 0) {
        throw "Missing or empty build input: $required"
    }
}
# Paths embedded in CMake must remain single literal arguments.
foreach ($path in @($sourceRoot, $buildRoot, $wrkRoot)) {
    if ($path -match '[;"$]') { throw "Unsupported CMake path character: $path" }
}
$sourceForward = $sourceRoot.Replace('\', '/')
$overrideForward = $overrideCmake.Replace('\', '/')
$cachePath = Join-Path $buildRoot 'CMakeCache.txt'
if (Test-Path -LiteralPath $cachePath -PathType Leaf) {
    $cacheLines = Get-Content -LiteralPath $cachePath
    foreach ($identity in @(
        @{ Key='CMAKE_HOME_DIRECTORY'; Value=$sourceForward },
        @{ Key='CMAKE_GENERATOR'; Value='Ninja' },
        @{ Key='CMAKE_TOOLCHAIN_FILE'; Value=$toolchain.Replace('\', '/') },
        @{ Key='ARCH'; Value='i386' },
        @{ Key='SARCH'; Value='pc' },
        @{ Key='CMAKE_PROJECT_INCLUDE'; Value=$overrideForward })) {
        $matchingLines = @($cacheLines | Where-Object { $_ -match ('^' + [regex]::Escape($identity.Key) + ':[^=]+=') })
        if ($matchingLines.Count -ne 1 -or -not [string]::Equals(
            $matchingLines[0].Split('=', 2)[1].Replace('\', '/'), $identity.Value, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Isolated loader cache identity mismatch: $($identity.Key)=$($identity.Value)"
        }
    }
}

# Import the x86 compiler environment into this process.
$environmentCommand = 'call "' + $vcvars + '" x86 >nul && set'
$environmentLines = & $env:ComSpec /d /s /c $environmentCommand
if ($LASTEXITCODE -ne 0) { throw 'vcvarsall failed' }
foreach ($line in $environmentLines) {
    if ($line -match '^([^=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process') }
}
$env:PATH = $wfbRoot + ';' + $env:PATH
foreach ($optionVariable in @('CL', '_CL_', 'LINK', '_LINK_')) {
    [Environment]::SetEnvironmentVariable($optionVariable, $null, 'Process')
}
New-Item -ItemType Directory -Path (Split-Path $isolatedSetupHeader -Parent) -Force | Out-Null
Copy-Item -LiteralPath $localSetupHeader -Destination $isolatedSetupHeader -Force
$inputs = @(foreach ($inputFile in @($localLoader, $localLoaderHeader, $localSetupHeader)) {
    [pscustomobject]@{ Name=[IO.Path]::GetFileName($inputFile); Source=$inputFile;
        SHA256=(Get-FileHash -LiteralPath $inputFile -Algorithm SHA256).Hash }
})
if ((Get-FileHash -LiteralPath $isolatedSetupHeader -Algorithm SHA256).Hash -ne $inputs[2].SHA256) {
    throw 'Isolated setup header differs from the local source.'
}
$cmakeOverrideText = @'
# ReactOS also calls project(HAL) in a subdirectory. Schedule this only once.
if(NOT CMAKE_CURRENT_SOURCE_DIR STREQUAL CMAKE_SOURCE_DIR)
    return()
endif()
function(wrk_setup_override_rosload)
    if(NOT TARGET rosload)
        message(FATAL_ERROR "Expected rosload target is absent")
    endif()
    get_target_property(_override_applied rosload WRK_SETUP_OVERRIDE_APPLIED)
    if(_override_applied)
        return()
    endif()
    get_target_property(_original_sources rosload SOURCES)
    get_target_property(_target_source_dir rosload SOURCE_DIR)
    set(_replacement_sources)
    set(_replacement_count 0)
    foreach(_source IN LISTS _original_sources)
        get_filename_component(_source_name "${_source}" NAME)
        get_filename_component(_source_absolute "${_source}" ABSOLUTE BASE_DIR "${_target_source_dir}")
        file(TO_CMAKE_PATH "${_source_absolute}" _source_absolute)
        # Preserve ntldr/arch/i386/winldr.c, which has the same basename.
        if(_source_name STREQUAL "winldr.c" AND
           _source_absolute STREQUAL "${CMAKE_SOURCE_DIR}/_bootldr/freeldr/freeldr/ntldr/winldr.c")
            list(APPEND _replacement_sources "@LOCAL_LOADER@")
            math(EXPR _replacement_count "${_replacement_count} + 1")
        else()
            list(APPEND _replacement_sources "${_source}")
        endif()
    endforeach()
    if(NOT _replacement_count EQUAL 1)
        message(FATAL_ERROR "Expected exactly one generic ntldr/winldr.c source; found ${_replacement_count}: ${_original_sources}")
    endif()
    set_property(TARGET rosload PROPERTY SOURCES "${_replacement_sources}")
    target_include_directories(rosload BEFORE PRIVATE "@SETUP_INCLUDE@")
    set_property(TARGET rosload PROPERTY WRK_SETUP_OVERRIDE_APPLIED TRUE)
    message(STATUS "WRK setup loader uses @LOCAL_LOADER@ and @SETUP_INCLUDE@/arc/setupblk.h")
endfunction()
cmake_language(DEFER DIRECTORY "${CMAKE_SOURCE_DIR}" CALL wrk_setup_override_rosload)
'@
$cmakeOverrideText = $cmakeOverrideText.Replace('@LOCAL_LOADER@', $localLoader.Replace('\', '/')).Replace('@SETUP_INCLUDE@', $includeRoot.Replace('\', '/'))
[IO.File]::WriteAllText($overrideCmake, $cmakeOverrideText, (New-Object Text.UTF8Encoding($false)))
# A failed rebuild must not retain a success manifest from an earlier build.
if (Test-Path -LiteralPath $provenancePath -PathType Leaf) { Remove-Item -LiteralPath $provenancePath }

function Invoke-Cmake([string[]]$Arguments, [string]$LogPath) {
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue' # PS 5.1 treats native stderr warnings as errors.
        & $cmakeExe @Arguments *> $LogPath
        $result = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    Write-Output "CMake exit $result - $LogPath"
    if ($result -ne 0) { throw "Loader build failed; see $LogPath" }
}
$configureArgs = @('-S', $sourceRoot, '-B', $buildRoot, '-G', 'Ninja',
    "-DCMAKE_TOOLCHAIN_FILE:FILEPATH=$sourceForward/toolchain-msvc.cmake", '-DARCH:STRING=i386', '-DSARCH:STRING=pc',
    '-DCMAKE_GENERATOR_PLATFORM=', '-DCMAKE_BUILD_TYPE=Debug', '-DRUNTIME_CHECKS=OFF', '-DENABLE_UNIATA=OFF',
    "-DBISON_EXECUTABLE=$wfbRoot/win_bison.exe", "-DFLEX_EXECUTABLE=$wfbRoot/win_flex.exe",
    "-DCMAKE_HOST_TOOLS_EXTRA_ARGS:STRING=-DBISON_EXECUTABLE=$wfbRoot/win_bison.exe;-DFLEX_EXECUTABLE=$wfbRoot/win_flex.exe",
    "-DCMAKE_PROJECT_INCLUDE:FILEPATH=$overrideForward")
Invoke-Cmake $configureArgs (Join-Path $buildRoot 'configure.log')
# native-mkisofs is imported, so the buildable host-tools target produces it.
Invoke-Cmake @('--build', $buildRoot, '--target', 'wrkboot', 'isoboot', 'host-tools', '--parallel', '2') (Join-Path $buildRoot 'build.log')

$outputFiles = [ordered]@{
    'freeldr.sys' = Join-Path $buildRoot '_bootldr\wrk\freeldr.sys'
    'rosload.exe' = Join-Path $buildRoot '_bootldr\wrk\rosload.exe'
    'isoboot.bin' = Join-Path $buildRoot '_bootldr\freeldr\bootsect\isoboot.bin'
}
foreach ($path in @($outputFiles.Values) + @((Join-Path $buildRoot 'host-tools\bin\mkisofs.exe'))) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -eq 0) {
        throw "Expected loader output missing or empty: $path"
    }
}
if ((Get-Item -LiteralPath $outputFiles['isoboot.bin']).Length -ne 2048) { throw 'Unexpected El Torito boot-image size.' }
foreach ($inputFile in $inputs) {
    if ((Get-FileHash -LiteralPath $inputFile.Source -Algorithm SHA256).Hash -ne $inputFile.SHA256) {
        throw "Local loader input changed during build: $($inputFile.Source)"
    }
}
$outputs = @(foreach ($entry in $outputFiles.GetEnumerator()) {
    [pscustomobject]@{ Name=$entry.Key; Path=$entry.Value; SHA256=(Get-FileHash -LiteralPath $entry.Value -Algorithm SHA256).Hash }
})
[ordered]@{
    SchemaVersion=1
    Purpose='NT52 text-mode setup lab loader'
    BaseSourceRoot=$sourceRoot
    BuildDirectory=$buildRoot
    Inputs=$inputs
    Outputs=$outputs
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $provenancePath -Encoding UTF8
Write-Output "Built isolated WRK setup loader: $buildRoot"
Write-Output "Provenance: $provenancePath"
