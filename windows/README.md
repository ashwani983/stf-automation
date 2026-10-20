# STF provider on Windows (Docker Desktop)

This PC contributes the **phone(s) plugged into it**. The core no longer runs
here — it lives on Proxmox, see [`../core/`](../core/). Phones on other
machines are served the same way, by [`../peers/`](../peers/).

```
                     +-- core on Proxmox (10.8.0.5 mesh / 10.10.10.3 cable) --+
                     |  stf-core + rethinkdb                                    |
                     +-------------------------+--------------------------------+
                                               ^  ZMQ 7114 (cmd) / 7116 (events)
                                               |  HTTP 7100 (storage)
+-- this Windows PC (10.8.0.4) ----------------+------------------------------+
|                                                                             |
|   phone USB -> adb on 0.0.0.0:5037                                          |
|          |                                                                  |
|          v                                                                  |
|   stf-provider-win  -----------------------------------> :7400+ video       |
+-------------------------------------------------------------------------+---+
                                                                          ^
                        browser anywhere on the mesh  -------------------+
                        (fetches video straight from this host)
```

## What this host does now

Only two things: run its own adb server, and run `stf provider` against the
Proxmox core.

| Flag | Points at | Direction |
|---|---|---|
| `--connect-sub` | `tcp://10.8.0.5:7114` | core -> provider (input from users) |
| `--connect-push` | `tcp://10.8.0.5:7116` | provider -> core (device metadata/heartbeats) |
| `--storage-url` | `http://10.8.0.5:7100/` | provider -> core (uploads, logs) |
| `--public-ip` | `10.8.0.4` (this host) | browser -> provider (video) |

`CORE_IP` is Proxmox's **mesh** address (`10.8.0.5`). Proxmox forwards
`7100/7110/7114/7116` into the `stf-core` container, which actually sits on the
direct cable; see `../core/README.md`. This means no changes are needed on this
host when the core's internal address changes.

Two consequences worth being explicit about:

* **Both ZMQ connections are outbound from the provider**, so this host needs no
  inbound firewall hole *toward the core* — but its own streaming ports must be
  reachable from whichever browser watches the device.
* **Video does not pass through the core.** The browser gets the device's stream
  URL pointing at this host's `--public-ip`, so it connects here directly.
  Keeping the core and the phones on opposite ends of a slow link therefore does
  *not* avoid the slow hop for the video — only browsing from near the provider
  does.

This is why we do **not** use STF's remote-adb mode (`--adb-host` at a peer's
address, with `--allow-remote`). Upstream calls that "highly unrecommended":
minicap video is *piped through adb*, so every frame would cross the WAN on a
single TCP socket, compounding the latency.

## Files

| File | Purpose |
|---|---|
| `provider-compose.yml` | the provider, pointed at `CORE_IP` |
| `.env.provider` | committed config: `SELF_IP`, `CORE_IP`, ports |
| `start.ps1` | ensure adb is on `0.0.0.0`, then bring the provider up |
| `stop.ps1` | stop the provider |
| `firewall.ps1` | open the stream ports on the WireGuard interface (self-elevates) |
| `adb-service.ps1` | scheduled task so adb listens on all interfaces after reboot |
| `docker-compose.yml` | **legacy**: the old core-on-Windows stack, kept for rollback |

## Run it

```powershell
cd windows
powershell -ExecutionPolicy Bypass -File .\adb-service.ps1                  # once: persist adb
powershell -ExecutionPolicy Bypass -File .\start.ps1                        # bring the provider up
powershell -ExecutionPolicy Bypass -File .\firewall.ps1                     # once: allow WireGuard peers (UAC)
```

Then open the panel at the core: <http://10.8.0.5:7100>. Log in with the admin
email/name from `../core/.env`.

## Ports

| Port | What | Bound to |
|---|---|---|
| `7400-7500` | this provider's per-device streaming | `10.8.0.4` |

Phone hosts use a **different** streaming range so two providers never collide;
`peers/` uses `7600-7700`. A provider claims `min-port..max-port` on its own
host, and the ports must be free on *that* host.

## Security model

The boundary is the network, not the app:

* `firewall.ps1` opens the ports **only on the WireGuard interface** (`gamepc`,
  which owns `10.8.0.4`), never on Wi-Fi/Ethernet.
* WireGuard authenticates and encrypts the path, so only mesh members reach it.

Note that Docker Desktop also programs its own accept rules for published
ports, which bypass the interface restriction. If you need hard guarantees that
a port is mesh-only, run that container with `network_mode: host` (as the peer
provider does) and let `peers/restrict-adb.sh` do the filtering.

## Notes / gotchas

* `adb` must be the **same** server the provider talks to. If Android Studio
  restarts adb bound to `127.0.0.1`, re-run `start.ps1`.
* A provider that can reach the core but whose *stream ports are already taken*
  on its host fails with `EADDRINUSE` and loops: setup -> bind fails -> retry on
  the next port. Check `netstat -ano -p TCP` for the range before blaming STF.
* Docker Desktop must be running (enable "Start Docker Desktop when you sign in"
  for hands-off use).

## Rolling back to a local core

`docker-compose.yml` and the old `.env` still describe the
core-runs-here topology. To go back:

```powershell
docker compose up -d            # the legacy stack
docker compose -f provider-compose.yml down
```

Note that the legacy stack needs its own `STF_AUTH_SECRET` in `.env`; the
current `.env.provider` deliberately has none, because this host stores no
secret any more.
