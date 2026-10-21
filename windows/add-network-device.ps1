# Add a device that is attached over the network (`adb connect`) to the Windows
# provider.
#
#   powershell -ExecutionPolicy Bypass -File .\add-network-device.ps1 -Address 10.8.0.2:34571
#
# Background: STF's provider ignores devices that arrive via `adb connect` by
# default and logs:
#
#   Filtered out remote device "10.8.0.2:34571", use --allow-remote to override
#
# That is a deliberate safeguard, not a bug. provider-compose.yml now passes
# --allow-remote so mesh-shared phones are accepted; this script re-attaches one
# and restarts the provider so it is enumerated immediately.

#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Address,
    [string]$Container = 'stf-provider-win'
)

$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $PSCommandPath
Set-Location $here

Write-Host "==> adb connect $Address"
& adb connect $Address | ForEach-Object { Write-Host "    $_" }

Write-Host "==> adb now lists:"
& adb devices -l | ForEach-Object { Write-Host "    $_" }

$hasAllowRemote = Select-String -Path 'provider-compose.yml' -Pattern '--allow-remote' -Quiet
if (-not $hasAllowRemote) {
    Write-Warning "provider-compose.yml does not set --allow-remote; STF will filter '$Address' out."
}

Write-Host "==> recreating $Container so it re-enumerates"
& docker compose -f provider-compose.yml --env-file .env.provider up -d --force-recreate 2>&1 |
    Select-Object -Last 3 | ForEach-Object { Write-Host "    $_" }

Write-Host "==> waiting for discovery"
Start-Sleep -Seconds 40

Write-Host "==> provider device lines:"
& docker logs --tail 150 $Container 2>&1 |
    Select-String -Pattern 'Found device|Filtered out|Fully operational|Providing all|Registered device' |
    Select-Object -Last 12 | ForEach-Object { Write-Host "    $_" }
