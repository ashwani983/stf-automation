# STF provider on the phone host

Run this on **any machine that has phones USB-plugged into it**, to publish
those phones into an existing STF core. This is STF's native "multi-provider"
layout: the core runs on the Proxmox box (see [`../core/`](../core/)); every
machine with devices runs a provider of its own.

```
phone ---USB---> this host
                  |
                  +-- adb server on 127.0.0.1:5037   (stf-adb.service)
                  +-- stf provider  (host networking)
                        |            |             \
                        |            |              +-- --public-ip=<this host>
                        |            |                     => browser fetches video HERE
                        |            +-- connect-sub   -> core:7114   (inbound cmds)
                        +--------------- connect-push  -> core:7116   (metadata)
                                         storage-url   -> core:7100
```

## Why a provider here, and not `--adb-host` at a remote peer

STF can also point one provider at another machine's adb server
(`--adb-host 10.8.0.x --allow-remote`). Upstream describes that as
*"highly unrecommended due to almost unbelievable slowness on the ADB side"*,
and it is right: screen capture (minicap) is **piped through adb**, so if the
provider sits across the network from the phone, every single video frame
crosses that link on one TCP socket.

Running the provider next to the phones keeps adb on loopback. Only device
metadata and control messages traverse the mesh, and the browser pulls the
video directly from this host.

## Install

```bash
# on the phone host, as root; core reached at proxmox's mesh address
sudo STF_CORE_IP=10.8.0.5 bash install-provider.sh

# a host on the direct cable (10.10.10.0/24) can use the fast path instead:
sudo STF_CORE_IP=10.10.10.3 bash install-provider.sh
```

`install-provider.sh` detects this host's `10.8.0.x` address (or takes
`STF_SELF_IP`), then:

1. installs `stf-adb.service` so adb listens on all interfaces across reboots
   (`pkill -9 adb` first — a client-started server collides with the bind);
2. runs `restrict-adb.sh` to make `5037` and the device-worker range
   **mesh-only**;
3. writes `/opt/stf-provider/{compose.yml,.env}`;
4. pulls the ~3 GB image in the background if it is missing, then starts the
   provider.

Every step is logged to `/opt/stf-provider/install.log`. If your SSH session
drops during the image pull, reconnect and poll:

```bash
tail -f /opt/stf-provider/install.log
docker compose -f /opt/stf-provider/compose.yml up -d   # after the pull finishes
```

Tunables: `STF_CORE_IP`, `STF_SELF_IP`, `STF_MIN_PORT`, `STF_MAX_PORT`,
`STF_ADB_PORT`.

## Files

| File | Purpose |
|---|---|
| `install-provider.sh` | idempotent installer for a phone host |
| `provider-compose.yml` | the provider unit (host networking) |
| `stf-adb.service` | adb on `0.0.0.0:5037`, restarted on failure |
| `restrict-adb.sh` | iptables: loopback + mesh allowed on `5037` and the worker range, everything else dropped |

## Port range

The provider claims `min-port..max-port` (default `7600-7700`) **on its own
host**, and those ports are what the browser connects to for video. They must
be free *on that host*.

`7600-7700` deliberately avoids `7400-7500`, which the Windows provider uses,
and avoids `7680`, which Windows Delivery Optimization (`svchost`) reserves. On
Linux this only matters for collisions with the other provider — pick any free
block if you have more than one phone host.

Do **not** reuse a range across hosts on the same machine, and if a provider
sits in a range something else already holds, it fails with:

```
FTL/device Setup had an error Error: listen EADDRINUSE: address already in use :::76xx
```

in a setup -> fail -> next-port loop. Check the range with
`sudo ss -tlnp | grep -E ':(76|77)[0-9][0-9]'` before blaming STF.

## Security

`restrict-adb.sh` is the whole boundary, since the provider uses
`network_mode: host` and therefore has no Docker-published ports:

* `5037` — loopback + `10.8.0.0/24`, dropped elsewhere. (adb is unauthenticated
  and grants full device control, so this matters.)
* the worker range — same rules.
* `network_mode: host` is chosen precisely so these `INPUT` rules apply; a
  bridge-mode container's published ports are NAT'd and slip past `INPUT` via
  `DOCKER-USER`.

Nothing is exposed to the LAN or the internet.

## Verifying

```bash
# on this host
sudo docker inspect stf-provider-peer --format '{{.State.Status}} {{.State.Health.Status}}'
sudo docker logs stf-provider-peer | grep -E 'Fully operational|Providing all'

# from the core host (on Proxmox: `pct exec 110 -- docker logs stf-core`)
docker logs stf-core | grep "is present"          # no 'Reaping' lines
```

`Providing all N device(s)` plus `Fully operational` per device means the core
accepted it. A `Device ... is present` followed by `Reaping device ... due to
heartbeat timeout` means the provider's `--connect-push` path to the core is
broken (usually the provider is crash-looping — check the log above it).
