#!/usr/bin/env bash
# Bring up the STF core on a Debian 12 host (the LXC `stf-core` on Proxmox).
#
#   ./install-core.sh
#
# Idempotent: safe to re-run. Installs Docker if missing, then starts the stack.
# Expects .env next to docker-compose.yml (copy .env.example first).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

log() { printf '\n== %s\n' "$*"; }

log "checking .env"
if [ ! -f .env ]; then
  echo "ERROR: .env not found. Run: cp .env.example .env  then edit it." >&2
  exit 1
fi
# shellcheck disable=SC1091
set -a; . ./.env; set +a

if [ -z "${STF_AUTH_SECRET:-}" ] || [ "$STF_AUTH_SECRET" = "change-me-generate-a-random-secret" ]; then
  echo "ERROR: set a real STF_AUTH_SECRET in .env (openssl rand -hex 24)." >&2
  exit 1
fi
if [ -z "${STF_IP:-}" ]; then
  echo "ERROR: set STF_IP in .env (the address clients use for the panel)." >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  log "installing docker"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  # shellcheck disable=SC1091
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
fi

log "starting the stack"
docker compose up -d

log "waiting for the core to answer"
for _ in $(seq 1 30); do
  if curl -fsS -m 3 -o /dev/null "http://127.0.0.1:${STF_WEB_PORT:-7100}/" 2>/dev/null; then
    break
  fi
  sleep 2
done

docker compose ps

cat <<EOF

Core is up.
  panel:  http://${STF_IP}:${STF_WEB_PORT:-7100}
  admin:  ${STF_ADMIN_EMAIL} (any password; STF mock auth)

Point a provider at it:
  CORE_IP=${STF_IP}  (see ../peers/install-provider.sh)
EOF
