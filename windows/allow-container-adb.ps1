# Allow the STF provider container to reach the host's adb server.
#
#   powershell -ExecutionPolicy Bypass -File .\allow-container-adb.ps1
#
# The provider runs in a container and talks to adb on the Windows host. adb
# listens on 0.0.0.0:5037, but Docker/WSL traffic arrives on the 'vEthernet'
# interfaces, and the stock adb.exe firewall rules are Public-profile only, so
# the connection is accepted then immediately closed (adb replies with nothing,
# even to host:version).
#
# Scoped to the container networks only: two /24s by default. Adjust if your
# Docker Desktop uses a different subnet (Get-NetIPAddress -InterfaceAlias
# 'vEthernet*'). Self-elevates.

#Requires -Version 5.1
[CmdletBinding()]
param(
    [string[]]$RemoteAddress = @('172.22.240.0/24', '172.23.112.0/24'),
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $argv = @('-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($Uninstall) { $argv += '-Uninstall' }
    Start-Process powershell -Verb RunAs -ArgumentList $argv | Out-Null
    return
}

$ruleName = 'STF provider -> host adb (container networks)'

if ($Uninstall) {
    Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    Write-Host "removed '$ruleName'"
    return
}

Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule

New-NetFirewallRule `
    -DisplayName $ruleName `
    -Direction Inbound `
    -Action Allow `
    -Protocol TCP `
    -LocalPort 5037 `
    -RemoteAddress $RemoteAddress `
    -Profile Any `
    -Description 'Lets the stf-provider container reach the host adb server on 5037.' | Out-Null

Write-Host "==> added '$ruleName'"
Write-Host "    inbound TCP 5037 from: $($RemoteAddress -join ', ')"

Get-NetFirewallRule -DisplayName $ruleName |
    Select-Object DisplayName, Enabled, Direction, Action |
    Format-Table -AutoSize
