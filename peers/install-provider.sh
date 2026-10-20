#!/bin/bash
# Install the STF *provider* on the machine the phones are plugged into.
#
#   sudo bash install-provider.sh                 # core at 10.8.0.5, detected self IP
#   sudo STF_CORE_IP=10.8.0.5 STF_SELF_IP=10.8.0.3 bash install-provider.sh
#
# The core runs on the Proxmox box (see ../core/). Over the mesh it is reached
# at Proxmox's mesh address, 10.8.0.5, which DNATs the core's ports to the
# container on its direct cable. A host ON that cable (10.10.10.0/24) can use
# STF_CORE_IP=10.10.10.3 instead for a sub-millisecond path.
#
# Everything is time-bounded and logs to /opt/stf-provider/install.log, so an
# SSH drop can never leave the machine in a half-configured mystery state:
# reconnect and `tail -f /opt/stf-provider/install.log`.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST=/opt/stf-provider
CORE_IP="${STF_CORE_IP:-10.8.0.5}"
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
             grep -E '^10\.8\.0\.' | grep -v '^10\.8\.0\.5$' | head -1)"
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

# --- 3. image --------------------------------------------------------------
cd "$DEST" || exit 1
if ! docker image inspect devicefarmer/stf:latest >/dev/null 2>&1; then
  log "pulling devicefarmer/stf (~3 GB) - this is the slow part, waiting for it"
  docker compose -f compose.yml pull 2>&1 | tail -3 | sed 's/^/  /' || {
    log "FATAL: image pull failed - re-run this script once the network is back"
    exit 1
  }
fi

# --- 4. start --------------------------------------------------------------
# --force-recreate matters: on a re-run the container must pick up the .env
# written above. Without it, `up -d` sees no change and keeps running against
# whatever core it was started with - which is how a provider silently stays
# bound to a decommissioned core.
log "starting provider (core=$CORE_IP)"
docker compose -f compose.yml up -d --force-recreate

# --- 5. route to the core's direct-cable subnet ---------------------------
# The core's cable address (10.10.10.3) is only natively reachable from the
# two hosts on that cable. Every other mesh peer sends 10.10.10.0/24 to the
# hub, which has no route for it, so the packet dies. This host route sends it
# to Proxmox instead, which forwards and NATs it. Harmless when the core is
# reached over the mesh (10.8.0.5): it only affects the cable subnet.
WG_IFACE="$(ip -o link show 2>/dev/null | awk -F': ' '$2 ~ /^(wg|home_|kuuashwa)/ {print $2; exit}')"
if [ -n "$WG_IFACE" ]; then
  cat > /etc/systemd/system/stf-core-route.service <<EOF
[Unit]
Description=Route to the STF core's direct-cable subnet via the Proxmox mesh peer
Documentation=https://github.com/ashwani983/stf-automation
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/ip route replace 10.10.10.0/24 via $CORE_IP dev $WG_IFACE
ExecStop=/sbin/ip route del 10.10.10.0/24 dev $WG_IFACE

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now stf-core-route.service >/dev/null 2>&1 || true
  log "cable route via $CORE_IP on $WG_IFACE: $(systemctl is-active stf-core-route)/$(systemctl is-enabled stf-core-route)"
else
  log "no wireguard interface found - skipping the cable route"
fi

# --- 6. verify ------------------------------------------------------------
sleep 12
docker ps --filter name=stf-provider-peer --format '  {{.Names}}  {{.Status}}'
log "done - devices should appear in the panel in a few seconds"
docker compose -f compose.yml logs --tail 15 2>&1 | sed 's/^/  /'

