#!/bin/bash
# Install the STF *provider* on the machine the phones are plugged into.
#
#   sudo bash install-provider.sh                 # core at 10.8.0.4, detected self IP
#   sudo STF_CORE_IP=10.8.0.4 STF_SELF_IP=10.8.0.3 bash install-provider.sh
#
# Everything is time-bounded and logs to /opt/stf-provider/install.log, so an
# SSH drop can never leave the machine in a half-configured mystery state:
# reconnect and `tail -f /opt/stf-provider/install.log`.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST=/opt/stf-provider
CORE_IP="${STF_CORE_IP:-10.8.0.4}"
MIN_PORT="${STF_MIN_PORT:-7600}"
MAX_PORT="${STF_MAX_PORT:-7700}"
ADB_PORT="${STF_ADB_PORT:-5037}"

log() { echo "[$(date +%H:%M:%S)] $*"; }

# --- preflight -------------------------------------------------------------
command -v docker >/dev/null 2>&1 || { log "FATAL: docker is not installed"; exit 1; }
docker info >/dev/null 2>&1 || { log "FATAL: docker daemon not reachable"; exit 1; }
command -v adb >/dev/null 2>&1 || { log "FATAL: adb is not installed (apt-get install -y adb)"; exit 1; }

# Work out this host's mesh address if not given: the 10.8.0.0/24 one.
SELF_IP="${STF_SELF_IP:-}"
if [ -z "$SELF_IP" ]; then
  SELF_IP="$(ip -4 -o addr show 2>/dev/null | awk '{print $4}' | cut -d/ -f1 |
             grep -E '^10\.8\.0\.' | grep -v '^10\.8\.0\.4$' | head -1)"
fi
[ -n "$SELF_IP" ] || { log "FATAL: could not detect this host's mesh IP; pass STF_SELF_IP=..."; exit 1; }
log "core=$CORE_IP self=$SELF_IP adb=$ADB_PORT ports=$MIN_PORT-$MAX_PORT"

# --- 1. adb server + mesh-only firewall ------------------------------------
install -m 0755 "$HERE/restrict-adb.sh" /usr/local/bin/stf-restrict-adb.sh
install -m 0644 "$HERE/stf-adb.service"  /etc/systemd/system/stf-adb.service
systemctl daemon-reload
pkill -9 adb >/dev/null 2>&1 || true      # a stray client-started server collides with our bind
sleep 1
systemctl enable --now stf-adb.service
sleep 3
STF_ADB_PORT="$ADB_PORT" STF_PROVIDER_RANGE="${MIN_PORT}:${MAX_PORT}" \
  /usr/local/bin/stf-restrict-adb.sh
log "adb service: $(systemctl is-active stf-adb)"
if ! systemctl is-active --quiet stf-adb; then
  log "FATAL: stf-adb failed"; timeout 8 journalctl -u stf-adb -n 12 --no-pager; exit 1
fi

# --- 2. compose project ----------------------------------------------------
mkdir -p "$DEST"
install -m 0644 "$HERE/provider-compose.yml" "$DEST/compose.yml"
cat > "$DEST/.env" <<EOF
CORE_IP=$CORE_IP
SELF_IP=$SELF_IP
MIN_PORT=$MIN_PORT
MAX_PORT=$MAX_PORT
ADB_PORT=$ADB_PORT
GROUP_TIMEOUT=900
TZ=Asia/Kolkata
EOF

# --- 3. image (3 GB - run it in the background and poll) ------------------
cd "$DEST" || exit 1
if ! docker image inspect devicefarmer/stf:latest >/dev/null 2>&1; then
  log "pulling devicefarmer/stf (~3 GB) - this is the slow part"
  nohup docker compose -f compose.yml pull > "$DEST/pull.log" 2>&1 &
  log "pull running in background, log: $DEST/pull.log"
  log "follow with: tail -f $DEST/pull.log"
  exit 0
fi

# --- 4. start --------------------------------------------------------------
log "image already present, starting provider"
docker compose -f compose.yml up -d
sleep 12
docker ps --filter name=stf-provider-peer --format '  {{.Names}}  {{.Status}}'
log "done - devices should appear in the panel in a few seconds"
docker compose -f compose.yml logs --tail 15 2>&1 | sed 's/^/  /'

