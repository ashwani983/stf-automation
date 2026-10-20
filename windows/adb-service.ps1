# Keep the Windows adb server listening on all interfaces across reboots.
#
#   powershell -ExecutionPolicy Bypass -File .\adb-service.ps1
#
# Registers a scheduled task that runs at logon. No admin rights needed (it
# runs as the current user). Without this, adb started by an IDE/Android Studio
# binds 127.0.0.1 only and the STF provider container cannot reach it.

$ErrorActionPreference = 'Stop'

$taskName = 'STF adb server'
$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'

if (-not (Test-Path $adb)) { throw "adb not found at $adb" }

$action = New-ScheduledTaskAction -Execute $adb `
    -Argument '-a -P 5037 nodaemon server start' `
    -WorkingDirectory (Split-Path $adb)

$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Settings $settings -Force | Out-Null

Start-ScheduledTask -TaskName $taskName

Write-Host "registered scheduled task '$taskName' (runs at logon) and started it"
netstat -ano -p TCP | Select-String ':5037\s+0\.0\.0\.0:0\s+LISTENING'
