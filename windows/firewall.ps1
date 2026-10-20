# Allow WireGuard peers to reach the STF panel and device streams.
#
#   powershell -ExecutionPolicy Bypass -File .\firewall.ps1
#
# Windows classifies the WireGuard tunnel as a Public network, so inbound is
# blocked by default. This opens ONLY the WireGuard interface, not your LAN or
# the internet. It self-elevates (you will get a UAC prompt).

#Requires -Version 5.1
[CmdletBinding()]
param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot

# --- self-elevate ---------------------------------------------------------
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $args = @('-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    if ($Uninstall) { $args += '-Uninstall' }
    Start-Process powershell -Verb RunAs -ArgumentList $args | Out-Null
    return
}

$ruleName = 'STF over WireGuard'

# --- find the WireGuard interface that owns STF_IP ------------------------
$stfIp = (Select-String -Path .env -Pattern '^STF_IP=(.+)$').Matches.Groups[1].Value.Trim()
$web   = (Select-String -Path .env -Pattern '^STF_WEB_PORT=(.+)$').Matches.Groups[1].Value
$ws    = (Select-String -Path .env -Pattern '^STF_WS_PORT=(.+)$').Matches.Groups[1].Value
$minP  = (Select-String -Path .env -Pattern '^PROVIDER_MIN_PORT=(.+)$').Matches.Groups[1].Value
$maxP  = (Select-String -Path .env -Pattern '^PROVIDER_MAX_PORT=(.+)$').Matches.Groups[1].Value
$devPub  = (Select-String -Path .env -Pattern '^STF_DEV_PUB_PORT=(.+)$').Matches.Groups[1].Value
$devPull = (Select-String -Path .env -Pattern '^STF_DEV_PULL_PORT=(.+)$').Matches.Groups[1].Value
if (-not $web)  { $web='7100' }
if (-not $ws)   { $ws='7110' }
if (-not $minP) { $minP='7400' }
if (-not $maxP) { $maxP='7500' }
# Provider ZMQ buses, so a provider on another mesh host can join this core.
if (-not $devPub)  { $devPub='7114' }
if (-not $devPull) { $devPull='7116' }

$alias = (Get-NetIPAddress -IPAddress $stfIp -ErrorAction SilentlyContinue |
          Select-Object -First 1 -ExpandProperty InterfaceAlias)

# Remove any previous rules.
Get-NetFirewallRule -DisplayName "$ruleName*" -ErrorAction SilentlyContinue |
    Remove-NetFirewallRule -ErrorAction SilentlyContinue

if ($Uninstall) { Write-Host "removed firewall rules '$ruleName*'"; return }

if (-not $alias) {
    Write-Warning "no network interface currently owns $stfIp (is WireGuard up?)."
    Write-Warning "creating rules for all interfaces instead of a specific one."
}

$ports = @([int]$web, [int]$ws, [int]$devPub, [int]$devPull, "$minP-$maxP")
$params = @{
    DisplayName = $ruleName
    Direction   = 'Inbound'
    Action      = 'Allow'
    Protocol    = 'TCP'
    LocalPort   = $ports
    Profile     = 'Any'
}
if ($alias) { $params.InterfaceAlias = $alias }

New-NetFirewallRule @params | Out-Null

Write-Host "created inbound TCP rule for ports $($ports -join ', ')"
if ($alias) { Write-Host "restricted to interface : $alias" }
Write-Host "peers on the WireGuard mesh can now reach http://${stfIp}:${web}"
