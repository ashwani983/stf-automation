# Start the STF stack on this Windows PC.
#
#   1. makes sure the Windows adb server is listening on all interfaces
#   2. brings up RethinkDB + STF core + the provider via Docker Compose
#
# Run from this directory:  powershell -ExecutionPolicy Bypass -File .\start.ps1

$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot

$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'

if (Test-Path $adb) {
    # A default adb server binds 127.0.0.1 only; the provider container reaches
    # the host over the Docker gateway, so adb must listen on all interfaces.
    $listeningOnAll = (netstat -ano -p TCP | Select-String ':5037\s+0\.0\.0\.0:0\s+LISTENING')
    if (-not $listeningOnAll) {
        Write-Host '==> starting adb server on 0.0.0.0:5037'
        & $adb kill-server | Out-Null
        Start-Process -WindowStyle Hidden -FilePath $adb -ArgumentList '-a','-P','5037','nodaemon','server','start'
        Start-Sleep -Seconds 2
    } else {
        Write-Host '==> adb server already listening on 0.0.0.0:5037'
    }
    & $adb devices -l
} else {
    Write-Warning "adb not found at $adb -- set ADB_HOST in .env to reach adb somewhere else"
}

Write-Host '==> docker compose up -d'
docker compose up -d

Write-Host '==> status'
docker compose ps

$ip = (Select-String -Path .env -Pattern '^STF_IP=(.+)$').Matches.Groups[1].Value
$web = (Select-String -Path .env -Pattern '^STF_WEB_PORT=(.+)$').Matches.Groups[1].Value
if (-not $web) { $web = '7100' }
Write-Host ""
Write-Host "STF web UI:  http://${ip}:${web}   (also http://localhost:${web} on this PC)"
