#Requires -Version 5.1
<#
.SYNOPSIS
Package an experimental WRK native Hello World RAM-disk boot ISO.
.DESCRIPTION
Uses already-built components and a fresh output directory. Does not alter
the original loader ISO, kernel, source hives, or any virtual machine.
#>
[CmdletBinding()]
param(
    [string]$ReactOSRoot = (Join-Path $PSScriptRoot '..\..\reactos'),
    [string]$RuntimeBuildDirectory = '',
    [string]$LoaderBuildDirectory = '',
    [string]$HiveDirectory = '',
    [string]$OutputDirectory = '',
    [switch]$TextModeSetup
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$artifacts = [IO.Path]::GetFullPath((Join-Path $repo 'artifacts'))
if (-not $RuntimeBuildDirectory) { $RuntimeBuildDirectory = Join-Path $artifacts 'wrk-runtime-build-x86' }
if (-not $LoaderBuildDirectory) { $LoaderBuildDirectory = Join-Path $artifacts 'freeldr-build-x86' }
$loaderProvenance = Join-Path $LoaderBuildDirectory 'provenance.json'
if (-not $HiveDirectory) { $HiveDirectory = Join-Path $artifacts 'wrk-hello-hives' }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $artifacts ('wrk-hello-{0:yyyyMMdd-HHmmss}' -f (Get-Date)) }
if (-not [IO.Path]::IsPathRooted($OutputDirectory)) { $OutputDirectory = Join-Path $repo $OutputDirectory }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if (-not $OutputDirectory.StartsWith($artifacts + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Output must be a subdirectory of this repository artifacts directory.'
}
$inputs = [ordered]@{
    'loader/freeldr.sys' = Join-Path $LoaderBuildDirectory '_bootldr\wrk\freeldr.sys'
    'loader/rosload.exe' = Join-Path $LoaderBuildDirectory '_bootldr\wrk\rosload.exe'
    'loader/isoboot.bin' = Join-Path $LoaderBuildDirectory '_bootldr\freeldr\bootsect\isoboot.bin'
    'WRK/System32/wrkx86.exe' = Join-Path $repo 'WRK-V1.2\BASE\NTOS\BUILD\EXE\wrkx86.exe'
    'WRK/System32/halmacpi.dll' = Join-Path $repo 'WRK-V1.2\WS03SP1HALS\X86\HALMACPI\HALMACPI.DLL'
    'WRK/System32/bootvid.dll' = Join-Path $RuntimeBuildDirectory 'drivers\base\bootvid\bootvid.dll'
    'WRK/System32/kdcom.dll' = Join-Path $RuntimeBuildDirectory 'drivers\base\kdcom\kdcom.dll'
    'WRK/System32/Drivers/ramdisk.sys' = Join-Path $RuntimeBuildDirectory 'drivers\storage\class\ramdisk\ramdisk.sys'
    'WRK/System32/Drivers/cdfs.sys' = Join-Path $RuntimeBuildDirectory 'drivers\filesystems\cdfs\cdfs.sys'
    'WRK/System32/ntdll.dll' = Join-Path $repo 'hello_world\ntdll\ntdll.dll'
    'WRK/System32/smss.exe' = Join-Path $repo 'hello_world\smss\smss.exe'
}
foreach ($name in @('SYSTEM','SOFTWARE','DEFAULT','SAM','SECURITY')) {
    $inputs['WRK/System32/Config/' + $name] = Join-Path $HiveDirectory ('Config\' + $name)
}
foreach ($name in @('c_1252.nls','c_437.nls','l_intl.nls')) {
    $inputs['WRK/System32/' + $name] = Join-Path $HiveDirectory ('Nls\' + $name)
}
$mkisofs = Join-Path $LoaderBuildDirectory 'host-tools\bin\mkisofs.exe'
$gpl = Join-Path $ReactOSRoot 'COPYING'
$license = Join-Path $repo 'WRK-V1.2\LICENSE.TXT'
$provenance = Join-Path $RuntimeBuildDirectory 'overrides\provenance.json'
foreach ($file in @($inputs.Values) + @($mkisofs,$gpl,$license,$provenance)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or (Get-Item -LiteralPath $file).Length -eq 0) {
        throw "Missing or empty input: $file"
    }
}
if ($TextModeSetup) {
    $hiveManifestPath = Join-Path $HiveDirectory 'manifest.json'
    if (-not (Test-Path -LiteralPath $hiveManifestPath -PathType Leaf)) {
        throw 'TextModeSetup requires hives generated with New-WrkHelloHives.ps1 -TextModeSetup.'
    }
    $hiveManifest = Get-Content -LiteralPath $hiveManifestPath -Raw | ConvertFrom-Json
    if ($hiveManifest.PSObject.Properties.Name -notcontains 'TextModeSetup' -or
        -not $hiveManifest.TextModeSetup) {
        throw 'TextModeSetup requires hives generated with New-WrkHelloHives.ps1 -TextModeSetup.'
    }
    $systemRecord = @($hiveManifest.Hives | Where-Object { $_.Name -eq 'SYSTEM' })
    if ($systemRecord.Count -ne 1 -or $systemRecord[0].SHA256 -ne
        (Get-FileHash -LiteralPath $inputs['WRK/System32/Config/SYSTEM'] -Algorithm SHA256).Hash) {
        throw 'SYSTEM hive differs from the text-mode setup generation manifest.'
    }
    if (-not (Test-Path -LiteralPath $loaderProvenance -PathType Leaf)) {
        throw 'TextModeSetup requires Build-WrkSetupLoader.ps1 outputs and provenance.json.'
    }
    $loaderBuild = Get-Content -LiteralPath $loaderProvenance -Raw | ConvertFrom-Json
    if ($loaderBuild.SchemaVersion -ne 1 -or $loaderBuild.Purpose -ne 'NT52 text-mode setup lab loader') {
        throw 'Unrecognized text-mode setup loader provenance.'
    }
    foreach ($loaderFile in @('freeldr.sys', 'rosload.exe', 'isoboot.bin')) {
        $record = @($loaderBuild.Outputs | Where-Object { $_.Name -eq $loaderFile })
        if ($record.Count -ne 1 -or $record[0].SHA256 -ne
            (Get-FileHash -LiteralPath $inputs['loader/' + $loaderFile] -Algorithm SHA256).Hash) {
            throw "Loader input differs from the text-mode setup build: $loaderFile"
        }
    }
}
if ((Get-Item -LiteralPath $inputs['loader/isoboot.bin']).Length -ne 2048) { throw 'Unexpected El Torito boot-image size.' }
foreach ($file in $inputs.Values | Where-Object { $_ -match '\.(exe|dll|sys)$' -and $_ -notlike '*\freeldr.sys' }) {
    $bytes = [IO.File]::ReadAllBytes($file)
    if ($bytes.Length -lt 64 -or [Text.Encoding]::ASCII.GetString($bytes,0,2) -ne 'MZ') { throw "Invalid PE: $file" }
    $pe = [BitConverter]::ToInt32($bytes,0x3c)
    if ($pe -lt 64 -or $pe + 96 -gt $bytes.Length -or [BitConverter]::ToUInt32($bytes,$pe) -ne 0x4550 -or
        [BitConverter]::ToUInt16($bytes,$pe+4) -ne 0x14c -or [BitConverter]::ToUInt16($bytes,$pe+24) -ne 0x10b -or
        [BitConverter]::ToUInt16($bytes,$pe+24+68) -ne 1) { throw "Expected x86 native PE: $file" }
}
if (Test-Path -LiteralPath $OutputDirectory) {
    if (@(Get-ChildItem -LiteralPath $OutputDirectory -Force).Count) { throw "Output directory is not empty: $OutputDirectory" }
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$root = Join-Path $OutputDirectory 'iso-root'
$systemRoot = Join-Path $OutputDirectory 'system-root'
New-Item -ItemType Directory -Path $root,$systemRoot -Force | Out-Null
$manifest = @()
foreach ($entry in $inputs.GetEnumerator()) {
    $stageRoot = if ($entry.Key.StartsWith('loader/')) { $root } else { $systemRoot }
    $destination = Join-Path $stageRoot $entry.Key
    New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $entry.Value -Destination $destination
    $manifest += [pscustomobject]@{ Name=$entry.Key; Source=[IO.Path]::GetFullPath($entry.Value); Size=(Get-Item -LiteralPath $destination).Length; SHA256=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash }
}
Copy-Item -LiteralPath $gpl -Destination (Join-Path $root 'COPYING-GPL.TXT')
Copy-Item -LiteralPath $license -Destination (Join-Path $root 'LICENSE-WRK.TXT')
Copy-Item -LiteralPath $provenance -Destination (Join-Path $OutputDirectory 'runtime-provenance.json')
$log = Join-Path $OutputDirectory 'packaging.log'
function Invoke-Mkisofs([string[]]$Arguments) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $mkisofs
    $psi.Arguments = (($Arguments | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"','\"') + '"' } else { $_ } }) -join ' ')
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($psi)
    $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    Add-Content -LiteralPath $log -Value (($Arguments -join ' ') + "`r`n" + $stdout.Result + $stderr.Result)
    if ($process.ExitCode -ne 0) { throw "mkisofs failed ($($process.ExitCode)); see $log" }
}
$inner = Join-Path $root 'WRKSYS.ISO'
# FreeLoader's ISO reader strips ;1 but retains a trailing dot. Registry
# hive names must therefore be SYSTEM;1 rather than SYSTEM.;1.
Invoke-Mkisofs @('-iso-level','3','-omit-period','-J','-V','WRK_SYS','-o',$inner,$systemRoot)
$length = (Get-Item -LiteralPath $inner).Length
$options = "/SOS /MININT /INRAM /RDEXPORTASCD /RDPATH=\WRKSYS.ISO /RDIMAGELENGTH=$length /NOPAE /NOEXECUTE=ALWAYSOFF /FASTDETECT"
$ini = @"
[FREELOADER]
DefaultOS=WRKHello
TimeOut=30
[Display]
TitleText=WRK native Hello World experiment
MinimalUI=Yes
[Operating Systems]
WRKHello="WRK 1.2 x86 - native Hello World (RAM disk)"
[WRKHello]
BootType=Windows2003
SystemPath=ramdisk(0)\WRK
Kernel=wrkx86.exe
Hal=halmacpi.dll
Options=$options
"@
if ($TextModeSetup) {
    # Select the kernel's setup path for this generated-hive RAM-disk experiment.
    $ini += "`r`nSetupMode=Text`r`n"
    Copy-Item -LiteralPath $loaderProvenance -Destination (Join-Path $OutputDirectory 'loader-provenance.json')
}
$encoding = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $root 'freeldr.ini'),$ini,$encoding)
[IO.File]::WriteAllText((Join-Path $root 'loader\freeldr.ini'),$ini,$encoding)
$iso = Join-Path $OutputDirectory 'WRK-HelloWorld.iso'
Invoke-Mkisofs @('-iso-level','3','-J','-V','WRK_HELLO','-b','loader/isoboot.bin','-no-emul-boot','-boot-load-size','4','-c','loader/boot.catalog','-o',$iso,$root)
$metadata = [ordered]@{
    Purpose='Experimental WRK native Hello World RAM-disk boot'
    WRKKernelExecutionVerified=$false; NativeGreetingVerified=$false
    ISO=$iso; ISOSHA256=(Get-FileHash -LiteralPath $iso -Algorithm SHA256).Hash
    InnerImageLength=$length; InnerImageSHA256=(Get-FileHash -LiteralPath $inner -Algorithm SHA256).Hash
    Options=$options; Inputs=$manifest
    TextModeSetup=[bool]$TextModeSetup
}
$metadata | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'manifest.json') -Encoding UTF8
Write-Host "Packaged $iso ($((Get-Item -LiteralPath $iso).Length) bytes). Guest execution still requires verification."
