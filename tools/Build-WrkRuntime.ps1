[CmdletBinding()]
param(
    [string]$ReactOSRoot = (Join-Path $PSScriptRoot '..\..\reactos'),
    [string[]]$Targets = @('bootvid', 'kdcom', 'cdfs', 'ramdisk')
)
$ErrorActionPreference = 'Stop'
$wrkRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$sourceRoot = (Resolve-Path -LiteralPath $ReactOSRoot).Path
$buildRoot = Join-Path $wrkRoot 'artifacts\wrk-runtime-build-x86'
$overrideRoot = Join-Path $buildRoot 'overrides'
$cmakeExe = 'C:\Strawberry\c\bin\cmake.exe'
$vcvars = 'C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvarsall.bat'
$wfbRoot = Join-Path $wrkRoot '.tools\winflexbison-2.5.25'
foreach ($required in @($cmakeExe, $vcvars, (Join-Path $sourceRoot 'toolchain-msvc.cmake'),
                        (Join-Path $wfbRoot 'win_bison.exe'), (Join-Path $wfbRoot 'win_flex.exe'))) {
    if (!(Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required build tool missing: $required" }
}
foreach ($target in $Targets) {
    if ($target -notmatch '^[A-Za-z0-9_]+$') { throw "Invalid CMake target: $target" }
}
$cachePath = Join-Path $buildRoot 'CMakeCache.txt'
$sourceForward = $sourceRoot.Replace('\', '/')
if (Test-Path -LiteralPath $cachePath) {
    $cacheLines = Get-Content -LiteralPath $cachePath
    foreach ($identity in @("CMAKE_HOME_DIRECTORY:INTERNAL=$sourceForward",
                             'CMAKE_GENERATOR:INTERNAL=Ninja', 'ARCH:STRING=i386', 'SARCH:STRING=pc')) {
        if ($cacheLines -notcontains $identity) { throw "Isolated build cache identity mismatch: $identity" }
    }
    $toolchainLine = $cacheLines | Where-Object { $_ -match '^CMAKE_TOOLCHAIN_FILE:(FILEPATH|UNINITIALIZED)=' }
    if (!$toolchainLine -or $toolchainLine.Split('=', 2)[1].Replace('\', '/') -ne "$sourceForward/toolchain-msvc.cmake") {
        throw 'Isolated build cache toolchain identity mismatch'
    }
}

# Import the x86 compiler environment without changing the source checkout.
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
New-Item -ItemType Directory -Path $overrideRoot -Force | Out-Null
$ramdiskOriginal = Join-Path $sourceRoot 'drivers\storage\class\ramdisk\ramdisk.c'
$ramdiskCopy = Join-Path $overrideRoot 'ramdisk.c'
$originalText = [IO.File]::ReadAllText($ramdiskOriginal).Replace("`r`n", "`n")
$flagBefore = 'DeviceObject->Flags &= DO_DEVICE_INITIALIZING;'
$flagAfter = 'DeviceObject->Flags &= ~DO_DEVICE_INITIALIZING;'
if (($originalText.Split(@($flagBefore), [StringSplitOptions]::None).Length - 1) -ne 1) {
    throw 'Expected exactly one original RAM disk initialization flag expression'
}
$headerBefore = '#include "../../../filesystems/fs_rec/fs_rec.h"'
$headerAfter = '#include "' + (Join-Path $sourceRoot 'drivers\filesystems\fs_rec\fs_rec.h').Replace('\', '/') + '"'
if (!$originalText.Contains($headerBefore)) { throw 'Expected RAM disk FS recognizer include not found' }
$patchedText = $originalText.Replace($flagBefore, $flagAfter).Replace($headerBefore, $headerAfter)
# A PDO must complete unhandled PnP requests and return the incoming IRP
# status. The remove-lock status is unrelated to the PnP request's result.
$queryBefore = @'
            /* Complete immediately without touching it */
            IoCompleteRequest(Irp, IO_NO_INCREMENT);
            goto ReleaseAndReturn;
'@
$queryAfter = @'
            /* Preserve the incoming PnP result before completion frees the IRP. */
            Status = Irp->IoStatus.Status;
            IoCompleteRequest(Irp, IO_NO_INCREMENT);
            goto ReleaseAndReturn;
'@
$defaultBefore = @'
        default:
            DPRINT1("Illegal IRP: %lx\n", Minor);
            break;
'@
$defaultAfter = @'
        default:
            DPRINT1("Illegal IRP: %lx\n", Minor);
            if (DeviceExtension->Type == RamdiskDrive)
            {
                /* This PDO has no lower driver for unsupported PnP requests. */
                Status = Irp->IoStatus.Status;
                IoCompleteRequest(Irp, IO_NO_INCREMENT);
                goto ReleaseAndReturn;
            }
            break;
'@
foreach ($replacement in @(@($queryBefore, $queryAfter), @($defaultBefore, $defaultAfter))) {
    $beforeText = $replacement[0].Replace("`r`n", "`n")
    $afterText = $replacement[1].Replace("`r`n", "`n")
    if (($patchedText.Split(@($beforeText), [StringSplitOptions]::None).Length - 1) -ne 1) {
        throw 'Expected exactly one original RAM disk PnP completion block'
    }
    $patchedText = $patchedText.Replace($beforeText, $afterText)
}
# The two drive-only StartDevice branches also have no lower driver. Other
# handled PDO requests already complete inside their dedicated helpers.
foreach ($indent in @('                    ', '                ')) {
    $startBefore = $indent + "DriveExtension->State = RamdiskStateStarted;`n" +
        $indent + "Irp->IoStatus.Status = Status;`n" + $indent + 'break;'
    $startAfter = $indent + "DriveExtension->State = RamdiskStateStarted;`n" +
        $indent + "Irp->IoStatus.Status = Status;`n" +
        $indent + "IoCompleteRequest(Irp, IO_NO_INCREMENT);`n" + $indent + 'goto ReleaseAndReturn;'
    if (($patchedText.Split(@($startBefore), [StringSplitOptions]::None).Length - 1) -ne 1) {
        throw 'Expected exactly one original RAM disk PDO StartDevice completion branch'
    }
    $patchedText = $patchedText.Replace($startBefore, $startAfter)
}
[IO.File]::WriteAllText($ramdiskCopy, $patchedText, (New-Object Text.UTF8Encoding($false)))
$provenance = [ordered]@{
    source = $ramdiskOriginal
    original_sha256 = (Get-FileHash -LiteralPath $ramdiskOriginal -Algorithm SHA256).Hash
    isolated_copy = $ramdiskCopy
    isolated_sha256 = (Get-FileHash -LiteralPath $ramdiskCopy -Algorithm SHA256).Hash
    changes = @('Clear DO_DEVICE_INITIALIZING instead of retaining it after RamdiskAddDevice',
                'Resolve fs_rec.h include to the unchanged original absolute header path',
                'Return the incoming PnP status when completing resource queries',
                'Complete unsupported RamdiskDrive PDO PnP requests with their incoming status',
                'Complete both RamdiskDrive PDO StartDevice paths before returning')
}
$provenance | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $overrideRoot 'provenance.json') -Encoding UTF8
$overrideCmake = Join-Path $overrideRoot 'wrk-runtime.cmake'
$cmakeOverrideText = @'
function(wrk_runtime_override_ramdisk)
    if(NOT TARGET ramdisk)
        message(FATAL_ERROR "Expected ramdisk target is absent")
    endif()
    get_target_property(_original_sources ramdisk SOURCES)
    set(_replacement_sources)
    set(_replaced FALSE)
    foreach(_source IN LISTS _original_sources)
        get_filename_component(_source_name "${_source}" NAME)
        if(_source_name STREQUAL "ramdisk.c")
            list(APPEND _replacement_sources "@RAMDISK_SOURCE@")
            set(_replaced TRUE)
        else()
            list(APPEND _replacement_sources "${_source}")
        endif()
    endforeach()
    if(NOT _replaced)
        message(FATAL_ERROR "Could not locate original ramdisk.c target source: ${_original_sources}")
    endif()
    set_property(TARGET ramdisk PROPERTY SOURCES "${_replacement_sources}")
endfunction()
cmake_language(DEFER DIRECTORY "${CMAKE_SOURCE_DIR}" CALL wrk_runtime_override_ramdisk)
'@
$cmakeOverrideText = $cmakeOverrideText.Replace('@RAMDISK_SOURCE@', $ramdiskCopy.Replace('\', '/'))
[IO.File]::WriteAllText($overrideCmake, $cmakeOverrideText, (New-Object Text.UTF8Encoding($false)))
$configureArgs = @('-S', $sourceRoot, '-B', $buildRoot, '-G', 'Ninja',
    "-DCMAKE_TOOLCHAIN_FILE:FILEPATH=$sourceForward/toolchain-msvc.cmake", '-DARCH:STRING=i386', '-DSARCH:STRING=pc',
    '-DCMAKE_GENERATOR_PLATFORM=', '-DCMAKE_BUILD_TYPE=Debug', '-DRUNTIME_CHECKS=OFF', '-DENABLE_UNIATA=OFF',
    "-DBISON_EXECUTABLE=$wfbRoot/win_bison.exe", "-DFLEX_EXECUTABLE=$wfbRoot/win_flex.exe",
    "-DCMAKE_HOST_TOOLS_EXTRA_ARGS:STRING=-DBISON_EXECUTABLE=$wfbRoot/win_bison.exe;-DFLEX_EXECUTABLE=$wfbRoot/win_flex.exe",
    ('-DCMAKE_PROJECT_INCLUDE:FILEPATH=' + $overrideCmake.Replace('\', '/')))
$configureLog = Join-Path $buildRoot 'configure.log'
$ErrorActionPreference = 'Continue' # Windows PowerShell maps native stderr warnings to errors.
& $cmakeExe @configureArgs *> $configureLog
$configureExit = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
Write-Output "Configure exit $configureExit - $configureLog"
if ($configureExit -ne 0) { throw 'Runtime CMake configure failed; see configure.log' }
$buildLog = Join-Path $buildRoot 'build.log'
$buildArgs = @('--build', $buildRoot, '--target') + $Targets + @('--parallel', '2')
$ErrorActionPreference = 'Continue'
& $cmakeExe @buildArgs *> $buildLog
$buildExit = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
Write-Output "Build exit $buildExit - $buildLog"
if ($buildExit -ne 0) { throw 'Runtime compilation failed; see build.log' }
