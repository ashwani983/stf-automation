# Stop the STF stack (containers only; the RethinkDB volume is kept).
Set-Location -Path $PSScriptRoot
docker compose down
