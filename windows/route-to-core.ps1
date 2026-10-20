# Add the route that makes the core's DIRECT-CABLE address work from this PC.
#
#   powershell -ExecutionPolicy Bypass -File .\route-to-core.ps1
#
# The core container lives on the direct cable between Proxmox and host 0.6,
# at 10.10.10.3. This PC is not on that cable, and its WireGuard peer sends
# everything (AllowedIPs = 0.0.0.0/0) to the mesh hub -- so without a more
# specific route, a packet to 10.10.10.3 is handed to the hub, which has no
# route for it, and dies.
#
# Proxmox (10.8.0.5) forwards 10.10.10.0/24 to the cable and NATs it. These
# rules add that host route so the cable address is reachable from here too.
#
# Self-elevates (UAC prompt). Persistent: survives reboot.

#Requires -Version 5.1
[CmdletBinding()]
param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot

# --- self-elevate ---------------------------------------------------------
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $argv = @('-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    if ($Uninstall) { $argv += '-Uninstall' }
    Start-Process powershell -Verb RunAs -ArgumentList $argv | Out-Null
    return
}

# --- where is the core? ---------------------------------------------------
$envPath = if (Test-Path '.env.provider') { '.env.provider' } else { '.env' }
$coreIp  = (Select-String -Path $envPath -Pattern '^CORE_IP=(.+)$').Matches.Groups[1].Value
if (-not $coreIp) { $coreIp = (Select-String -Path $envPath -Pattern '^STF_IP=(.+)$').Matches.Groups[1].Value }
if (-not $coreIp) { throw "could not read CORE_IP from $envPath" }

$net   = '10.10.10.0'
$mask  = '255.255.255.0'
$dest  = $coreIp.Trim()

if ($Uninstall) {
    route delete $net 2>$null | Out-Null
    Write-Host "removed route $net -> $dest"
    return
}

Write-Host "==> route: $net/$mask via $dest  (persistent)"

# -p makes it survive reboot. Replace rather than duplicate.
route delete $net 2>$null | Out-Null
$out = route -p add $net mask $mask $dest 2>&1
if ($LASTEXITCODE -ne 0) { throw "route add failed: $out" }

Write-Host "==> current 10.10.10.x routes:"
route print -4 | Select-String -Pattern '10\.10\.10\.' | ForEach-Object { Write-Host "    $_" }

# --- verify ---------------------------------------------------------------
Write-Host "==> probing the core's cable address"
foreach ($p in 7100, 7114, 7116) {
    $client = New-Object Net.Sockets.TcpClient
    $ok = $client.ConnectAsync($dest, $p).Wait(4000)
    Write-Host ("    {0}:{1} = {2}" -f $dest, $p, $ok)
    $client.Close()
}
