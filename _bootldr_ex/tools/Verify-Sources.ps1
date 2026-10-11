<#
.SYNOPSIS
Verifies that every exported source matches the recorded SHA-256 and size.
#>
[CmdletBinding()]
param([string]$BundleRoot = (Join-Path $PSScriptRoot '..'))
$ErrorActionPreference = 'Stop'
$bundleDirectory = (Resolve-Path -LiteralPath $BundleRoot).Path
$manifest = Get-Content -Raw -LiteralPath (Join-Path $bundleDirectory 'source-manifest.json') | ConvertFrom-Json
$failures = [Collections.Generic.List[string]]::new()
foreach ($entry in $manifest.files) {
    $file = Join-Path $bundleDirectory $entry.path
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        $failures.Add("Missing: $($entry.path)")
        continue
    }
    $size = (Get-Item -LiteralPath $file).Length
    $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($size -ne $entry.bytes -or $hash -ne $entry.sha256) {
        $failures.Add("Changed: $($entry.path)")
    }
}
foreach ($entry in $manifest.derived_build_helpers) {
    $file = Join-Path $bundleDirectory $entry.path
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        $failures.Add("Missing build helper: $($entry.path)")
    } elseif ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.sha256) {
        $failures.Add("Changed build helper: $($entry.path)")
    }
}
if ($failures.Count) { throw ($failures -join "`n") }
Write-Output "Verified $($manifest.files.Count) exported source files."
