# STF on Windows (Docker Desktop)

The **core** of the farm runs here: RethinkDB, the STF core, and a provider for
whatever phone is USB-plugged into this PC. Phones on **other** machines are
served by a provider running on *that* machine, which reports back to this core
over WireGuard. See [`../peers/`](../peers/) for the phone-host side.

```
+-- this Windows PC (10.8.0.4) ---------------+     +-- phone host (10.8.0.x) --+
|                                             |     |                          |
|  phone USB -> adb on 0.0.0.0:5037           |     |  phone USB -> adb :5037  |
|        |                                    |     |        |                 |
|        v                                    |     |        v                 |
|  stf-provider-win        stf-core  <---ZMQ--+-----+-- stf-provider-peer      |
|  (host networking)       + rethinkdb :7114/7116    |  (host networking)       |
|        |                       |            |     |        |                 |
|        |                 http://10.8.0.4:7100      |   video on :7600+        |
+-------------------------------+-------------+     +--------+-----------------+
                                |                             |
                          browser on any mesh member <---------+
                          (fetches video straight from the provider host)
```

## Topology: one core, a provider per phone host

STF's own "multi-provider" layout. The core is the only stateful piece; each
machine with phones runs `stf provider` locally, talks to its own adb on
loopback, and connects *out* to the core's two ZMQ sockets:

| Flag | Points at | Direction |
|---|---|---|
| `--connect-sub` | `tcp://10.8.0.4:7114` | core -> provider (input from users) |
| `--connect-push` | `tcp://10.8.0.4:7116` | provider -> core (device metadata/heartbeats) |
| `--storage-url` | `http://10.8.0.4:7100/` | provider -> core (uploads, logs) |
| `--public-ip` | the provider host's own mesh IP | browser -> provider (video) |

Two consequences worth being explicit about:

* **Both ZMQ connections are outbound from the provider**, so a phone host needs
  no inbound firewall hole *toward the core* — but its own streaming ports must
  be reachable from whichever browser watches the device.
* **Video does not pass through the core.** The browser gets the device's
  stream URL pointing at the provider host's `--public-ip`, so it connects to
  that host directly. Keeping the core and the phones on opposite ends of a
  slow link therefore does *not* avoid the slow hop for the video — only
  browsing from near the provider does.

This is why we do **not** use STF's remote-adb mode (`--adb-host` at a peer's
address, with `--allow-remote`). Upstream calls that "highly unrecommended":
minicap video is *piped through adb*, so every frame would cross the WAN on a
single TCP socket, compounding the latency.

## Files

| File | Purpose |
|---|---|
| `docker-compose.yml` | RethinkDB + STF core + the local Windows provider |
| `.env` | config incl. generated `STF_AUTH_SECRET` (gitignored) |
| `start.ps1` | ensure adb is on `0.0.0.0`, then `docker compose up -d` |
| `stop.ps1` | `docker compose down` |
| `firewall.ps1` | open the panel/stream ports on the WireGuard interface (self-elevates) |
| `adb-service.ps1` | scheduled task so adb listens on all interfaces after reboot |

## Run it

```powershell
cd windows
powershell -ExecutionPolicy Bypass -File .\adb-service.ps1   # once: persist adb
powershell -ExecutionPolicy Bypass -File .\start.ps1         # bring the stack up
powershell -ExecutionPolicy Bypass -File .\firewall.ps1      # once: allow WireGuard peers (UAC)
```

Then open <http://10.8.0.4:7100> from any mesh member. Log in with the admin
email/name from `.env`.

## Ports

| Port | What | Bound to |
|---|---|---|
| `7100` | panel | `10.8.0.4` |
| `7110` | app websocket | `10.8.0.4` |
| `7114` / `7116` | provider ZMQ (in / out) | `10.8.0.4` |
| `7400-7500` | local provider's per-device streaming | `10.8.0.4` |
| `18080` | RethinkDB admin (orphaned by the core) | `127.0.0.1` only |

Phone hosts use a **different** streaming range so two providers never collide;
`peers/` uses `7600-7700`. A provider claims `min-port..max-port` on its own
host, and the ports must be free on *that* host.

## Security model

The boundary is the network, not the app:

* `firewall.ps1` opens the ports **only on the WireGuard interface** (`gamepc`,
  which owns `10.8.0.4`), never on Wi-Fi/Ethernet.
* WireGuard authenticates and encrypts the path, so only mesh members reach it.
* `STF_AUTH_SECRET` is generated into `.env` (gitignored) and signs session
  cookies. Never commit it.

Note that Docker Desktop also programs its own accept rules for published
ports, which bypass the interface restriction. If you need hard guarantees that
a port is mesh-only, run that container with `network_mode: host` (as the peer
provider does) and let `peers/restrict-adb.sh` do the filtering.

## Notes / gotchas

* `adb` must be the **same** server the provider talks to. If Android Studio
  restarts adb bound to `127.0.0.1`, re-run `start.ps1`.
* Recreating `stf-core` changes its container IP. Restart `stf-provider-win`
  (and the peer providers) afterwards.
* A provider that can reach the core but whose *stream ports are already taken*
  on its host fails with `EADDRINUSE` and loops: setup -> bind fails -> retry on
  the next port. Check `ss -tlnp` for the range before blaming STF.
* Docker Desktop must be running (enable "Start Docker Desktop when you sign in"
  for hands-off use).
