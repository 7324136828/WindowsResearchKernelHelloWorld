#Requires -Version 5.1
<#
.SYNOPSIS
Remove repository build output, packaged media, VM files, and verification caches.
.DESCRIPTION
Run with -WhatIf to preview. Source BUILD directories, PREBUILT/LIB inputs,
bundled WRK tools and HALs, source manifests, and downloaded .tools are retained.
All targets are checked before deletion; tracked files and reparse points are refused.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path.TrimEnd('\', '/')
$repoPrefix = $repoRoot + [IO.Path]::DirectorySeparatorChar
$targets = [Collections.Generic.List[string]]::new()

foreach ($relative in @(
    'artifacts', '.vs', '__pycache__', 'WRK-V1.2/BASE/NTOS/BUILD/EXE',
    'ProjectOZ/runx86', 'ProjectOZ/files',
    'hello_world/ntdll/build', 'hello_world/smss/build',
    'hello_world/ntdll/ntdll.dll', 'hello_world/smss/smss.exe',
    'hello_world/build.log', 'hello_world/verification.json'
)) {
    $targets.Add((Join-Path $repoRoot $relative))
}

# Walk source directories without following junctions or descending into output.
$pending = [Collections.Generic.Stack[string]]::new()
foreach ($relative in @('WRK-V1.2', 'ProjectOZ', 'hello_world', 'bootloader', 'tools', '_bootldr', '_bootldr_ex')) {
    $path = Join-Path $repoRoot $relative
    if (Test-Path -LiteralPath $path -PathType Container) { $pending.Push($path) }
}
while ($pending.Count) {
    $directory = Get-Item -LiteralPath $pending.Pop() -Force
    if ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Refusing to traverse reparse point: $($directory.FullName)"
    }
    foreach ($child in Get-ChildItem -LiteralPath $directory.FullName -Directory -Force) {
        $isObjectDirectory = $child.Name -in @('OBJI386', 'OBJAMD64') -and
            ($child.FullName.StartsWith((Join-Path $repoRoot 'WRK-V1.2') + '\', [StringComparison]::OrdinalIgnoreCase) -or
             $child.FullName.StartsWith((Join-Path $repoRoot 'ProjectOZ') + '\', [StringComparison]::OrdinalIgnoreCase))
        $isCmakeOutput = $child.Parent.FullName -eq (Join-Path $repoRoot '_bootldr_ex') -and
            $child.Name -match '^(build|output)'
        if ($child.Name -eq '__pycache__' -or $isObjectDirectory -or $isCmakeOutput) {
            $targets.Add($child.FullName)
        } elseif ($child.FullName -notin $targets) {
            $pending.Push($child.FullName)
        }
    }
}

# Read NUL-delimited UTF-8 paths without Git's filename quoting or shell decoding.
$gitInfo = [Diagnostics.ProcessStartInfo]::new()
$gitInfo.FileName = (Get-Command git -CommandType Application).Source
$gitInfo.Arguments = '-C "' + $repoRoot + '" ls-files -z'
$gitInfo.UseShellExecute = $false
$gitInfo.CreateNoWindow = $true
$gitInfo.RedirectStandardOutput = $true
$gitInfo.RedirectStandardError = $true
$gitInfo.StandardOutputEncoding = [Text.Encoding]::UTF8
$gitProcess = [Diagnostics.Process]::Start($gitInfo)
$trackedText = $gitProcess.StandardOutput.ReadToEnd()
$gitError = $gitProcess.StandardError.ReadToEnd()
$gitProcess.WaitForExit()
if ($gitProcess.ExitCode -ne 0) { throw "Cannot read tracked files; cleanup aborted. $gitError" }
$gitProcess.Dispose()
$tracked = @($trackedText.Split([char]0, [StringSplitOptions]::RemoveEmptyEntries) |
    ForEach-Object { [IO.Path]::GetFullPath((Join-Path $repoRoot $_)) })
$existing = @($targets | Sort-Object -Unique | Where-Object { Test-Path -LiteralPath $_ })
foreach ($target in $existing) {
    $fullPath = [IO.Path]::GetFullPath($target)
    if (-not $fullPath.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Cleanup target is outside the repository: $fullPath"
    }
    for ($cursor = $fullPath; $cursor; $cursor = Split-Path -Parent $cursor) {
        $ancestor = Get-Item -LiteralPath $cursor -Force
        if ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Refusing to remove through reparse point: $($ancestor.FullName)"
        }
        if ($ancestor.FullName -eq $repoRoot) { break }
    }
    if (@($tracked | Where-Object { $_ -eq $fullPath -or $_.StartsWith($fullPath + '\', [StringComparison]::OrdinalIgnoreCase) }).Count) {
        throw "Cleanup target contains tracked files: $fullPath"
    }
    $item = Get-Item -LiteralPath $fullPath -Force
    if ($item.PSIsContainer -and @(Get-ChildItem -LiteralPath $fullPath -Recurse -Force |
            Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) {
        throw "Cleanup target contains a reparse point: $fullPath"
    }
}

foreach ($target in $existing) {
    if ($PSCmdlet.ShouldProcess($target, 'Remove generated files')) {
        Remove-Item -LiteralPath $target -Recurse -Force
    }
}
Write-Host "Cleanup checked $($existing.Count) generated paths."
