#!/bin/bash
# Restrict adb (and the STF provider's stream ports) to the WireGuard mesh.
#
# adb on 0.0.0.0 gives any caller full control of every plugged-in phone, and a
# provider bound to 0.0.0.0 would hand device screens to the home LAN, so both
# port sets are locked down: loopback + mesh allowed, everything else dropped.
# Idempotent: safe to run on every boot (it is the adb unit's ExecStartPre).
set -u

MESH="${STF_MESH_NET:-10.8.0.0/24}"
MESH6="${STF_MESH_NET6:-}"          # optional mesh ULA, e.g. fdcc:...::/64
ADB_PORT="${STF_ADB_PORT:-5037}"
PROVIDER_RANGE="${STF_PROVIDER_RANGE:-7600:7700}"

# Insert ACCEPT rules above the DROP rule. Order between the two ACCEPTs does
# not matter; what matters is that both sit before the DROP.
add_rules() {
  local ipt="$1" mesh="$2" spec="$3" lo="$4"
  # 1. DROP for anything else on this port (inserted at the head) ...
  $ipt -C INPUT -p tcp --dport "$spec" -j DROP 2>/dev/null ||
    $ipt -I INPUT 1 -p tcp --dport "$spec" -j DROP
  # 2. ... loopback (local `adb devices`, local browser) ...
  $ipt -C INPUT -p tcp --dport "$spec" -i lo -j ACCEPT 2>/dev/null ||
    $ipt -I INPUT 1 -p tcp --dport "$spec" -i lo -j ACCEPT
  $ipt -C INPUT -p tcp --dport "$spec" -s "$lo" -j ACCEPT 2>/dev/null ||
    $ipt -I INPUT 1 -p tcp --dport "$spec" -s "$lo" -j ACCEPT
  # 3. ... and the mesh.
  if [ -n "$mesh" ]; then
    $ipt -C INPUT -p tcp --dport "$spec" -s "$mesh" -j ACCEPT 2>/dev/null ||
      $ipt -I INPUT 1 -p tcp --dport "$spec" -s "$mesh" -j ACCEPT
  fi
}

if command -v iptables >/dev/null 2>&1; then
  add_rules iptables "$MESH"  "$ADB_PORT"        "127.0.0.0/8"
  add_rules iptables "$MESH"  "$PROVIDER_RANGE"  "127.0.0.0/8"
fi

if command -v ip6tables >/dev/null 2>&1; then
  add_rules ip6tables "$MESH6" "$ADB_PORT"       "::1"
  add_rules ip6tables "$MESH6" "$PROVIDER_RANGE" "::1"
fi

echo "ports $ADB_PORT,$PROVIDER_RANGE: loopback + ${MESH:-<no mesh>} allowed, everything else dropped"

