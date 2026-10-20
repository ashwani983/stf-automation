# Stop the STF provider on this Windows PC (containers only; no state is kept).
Set-Location -Path $PSScriptRoot
docker compose -f provider-compose.yml --env-file .env.provider down
