#Requires -Version 5.1
<# .SYNOPSIS
Boot a fresh, CD-only VirtualBox VM and collect screenshots and diagnostics.
This tests the supplied ISO without modifying existing VMs. A screenshot of
the greeting is required to claim that native Hello World executed.#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$IsoPath,
    [string]$Name = 'WRK-HelloWorld-x86',
    [string]$EvidenceDirectory = '',
    [ValidateRange(10,300)][int]$ObservationSeconds = 120,
    [switch]$CaptureCore
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$artifacts = [IO.Path]::GetFullPath((Join-Path $repo 'artifacts'))
$vbox = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$IsoPath = (Resolve-Path -LiteralPath $IsoPath).Path
if (-not $EvidenceDirectory) { $EvidenceDirectory = Join-Path (Split-Path $IsoPath -Parent) 'verification' }
$EvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory).TrimEnd('\')
if (-not $EvidenceDirectory.StartsWith($artifacts + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Evidence must be under repository artifacts.' }
if ($Name -notmatch '^WRK-HelloWorld-[A-Za-z0-9_-]+$') { throw 'Use a distinct WRK-HelloWorld-* VM name.' }
if (Test-Path -LiteralPath $EvidenceDirectory) { throw "Evidence directory already exists: $EvidenceDirectory" }
New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null
$log = Join-Path $EvidenceDirectory 'vbox-commands.log'
function Invoke-VBox([string[]]$Arguments, [switch]$AllowFailure) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $vbox
    $psi.Arguments = (($Arguments | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"','\"') + '"' } else { $_ } }) -join ' ')
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
    $p.WaitForExit()
    $message = ($Arguments -join ' ') + "`r`n" + $out.Result + $err.Result
    Add-Content -LiteralPath $log -Value $message
    if ($p.ExitCode -ne 0 -and -not $AllowFailure) { throw "VBoxManage exit $($p.ExitCode); see $log" }
    return $out.Result
}
$vms = Invoke-VBox @('list','vms')
if ($vms -match ('(?m)^"' + [regex]::Escape($Name) + '" ')) { throw "VM already exists: $Name" }
$before = [ordered]@{}
foreach ($path in @($IsoPath, (Join-Path $repo 'WRK-V1.2\BASE\NTOS\BUILD\EXE\wrkx86.exe'), (Join-Path $repo 'WRK-V1.2\WS03SP1HALS\X86\HALMACPI\HALMACPI.DLL'))) {
    $before[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}
# Cleanup can remove the unrelated, original loader ISO. Protect it when present.
$originalIso = Join-Path $repo 'artifacts\wrk-freeldr\WRK-FreeLoader.iso'
if (Test-Path -LiteralPath $originalIso -PathType Leaf) {
    $before[$originalIso] = (Get-FileHash -LiteralPath $originalIso -Algorithm SHA256).Hash
}
$before | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'hashes-before.json') -Encoding UTF8
$vmBase = Join-Path $artifacts 'VirtualBox'
$null = Invoke-VBox @('createvm','--name',$Name,'--ostype','Windows2003','--basefolder',$vmBase,'--register')
$running = $false
try {
    $null = Invoke-VBox @('modifyvm',$Name,'--memory','512','--cpus','1','--firmware','bios','--chipset','piix3','--acpi','on','--ioapic','on','--pae','off','--nic1','none','--audio-enabled','off','--usb','off','--graphicscontroller','vboxvga','--vram','16','--boot1','dvd','--boot2','none','--boot3','none','--boot4','none','--uart1','0x3f8','4','--uartmode1','file',(Join-Path $EvidenceDirectory 'serial.txt'))
    $null = Invoke-VBox @('storagectl',$Name,'--name','IDE','--add','ide','--controller','PIIX4','--bootable','on')
    $null = Invoke-VBox @('storageattach',$Name,'--storagectl','IDE','--port','1','--device','0','--type','dvddrive','--medium',$IsoPath)
    Invoke-VBox @('showvminfo',$Name,'--machinereadable') | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'vm-before.txt') -Encoding UTF8
    $null = Invoke-VBox @('startvm',$Name,'--type','headless')
    $running = $true
    Start-Sleep -Seconds 8
    $null = Invoke-VBox @('controlvm',$Name,'screenshotpng',(Join-Path $EvidenceDirectory 'screen-menu.png'))
    $null = Invoke-VBox @('controlvm',$Name,'keyboardputscancode','1c','9c')
    Start-Sleep -Seconds 10
    $null = Invoke-VBox @('controlvm',$Name,'screenshotpng',(Join-Path $EvidenceDirectory 'screen-10s.png'))
    # VGA bitmap rendering can take tens of seconds on VirtualBox NEM.
    $remaining = $ObservationSeconds - 10
    while ($remaining -gt 0) {
        $interval = [Math]::Min(30,$remaining)
        Start-Sleep -Seconds $interval
        $remaining -= $interval
        $elapsed = $ObservationSeconds - $remaining
        $null = Invoke-VBox @('controlvm',$Name,'screenshotpng',(Join-Path $EvidenceDirectory ("screen-${elapsed}s.png")))
    }
    $null = Invoke-VBox @('controlvm',$Name,'screenshotpng',(Join-Path $EvidenceDirectory 'screen-final.png'))
    if ($CaptureCore) { $null = Invoke-VBox @('controlvm',$Name,'pause') }
    Invoke-VBox @('debugvm',$Name,'getregisters','--cpu=0','eip','esp','ebp','eax','ebx','ecx','edx','cr0','cr3') -AllowFailure | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'registers.txt') -Encoding UTF8
    if ($CaptureCore) {
        $null = Invoke-VBox @('debugvm',$Name,'dumpvmcore','--filename',(Join-Path $EvidenceDirectory 'guest.core'))
    }
} finally {
    if ($running) { $null = Invoke-VBox @('controlvm',$Name,'poweroff') -AllowFailure }
    Invoke-VBox @('showvminfo',$Name,'--machinereadable') -AllowFailure | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'vm-after.txt') -Encoding UTF8
    $vmLog = Join-Path $vmBase ($Name + '\Logs\VBox.log')
    if (Test-Path -LiteralPath $vmLog) { Copy-Item -LiteralPath $vmLog -Destination (Join-Path $EvidenceDirectory 'VBox.log') }
    $after = [ordered]@{}; $unchanged = $true
    foreach ($path in $before.Keys) { $after[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash; if ($after[$path] -ne $before[$path]) { $unchanged=$false } }
    $after | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'hashes-after.json') -Encoding UTF8
    [ordered]@{ VM=$Name; ISO=$IsoPath; OriginalPayloadAndISOUnchanged=$unchanged; GuestGreetingVerified=$false; Note='Inspect screenshots and diagnostics before reporting a guest execution result.' } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'result.json') -Encoding UTF8
}
Write-Host "VM observation finished; inspect $EvidenceDirectory"
