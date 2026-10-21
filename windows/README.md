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

## Devices attached over the network (`adb connect`)

A phone does not have to be plugged into this PC by USB. If it is shared by
another host on the mesh, it appears here as a network device, e.g.
`10.8.0.2:34571`.

STF's provider **ignores those by default** and logs:

```
Filtered out remote device "10.8.0.2:34571", use --allow-remote to override
```

That is an intentional safeguard, not a bug. `provider-compose.yml` therefore
passes `--allow-remote`, so mesh-shared phones are accepted. Only do this where
the adb server is one you control and is firewalled to the mesh (see
`../peers/restrict-adb.sh` and `allow-container-adb.ps1`).

To attach one and have it show up immediately:

```powershell
powershell -ExecutionPolicy Bypass -File .\add-network-device.ps1 -Address 10.8.0.2:34571
```

`start.ps1` re-establishes devices listed in `NETWORK_DEVICES` (in
`.env.provider`) on each start, so a reboot does not lose them.

## The provider must use a reachable adb address

`provider-compose.yml` sets `--adb-host=${ADB_HOST}`. Two traps on Docker
Desktop for Windows:

* **`host.docker.internal` resolves to IPv6** inside the container
  (`fdc4:f303:9324::254`), which is the Docker VM — *not* this PC's adb. The
  container then talks to an empty adb server and silently sees zero devices.
  Use the host's concrete address (`ADB_HOST=10.8.0.4`) instead.
* **adb listens on `127.0.0.1` by default**, so nothing outside this PC can
  reach it. Run it as `adb -a nodaemon server start` to bind `0.0.0.0:5037`
  (`start.ps1` does this).
* Even then, the stock `adb.exe` firewall rules are **Public-profile only**,
  while Docker/WSL traffic arrives on the `vEthernet` interfaces. The
  connection is accepted and then closed immediately — adb answers nothing,
  even to `host:version`. Fix:

  ```powershell
  powershell -ExecutionPolicy Bypass -File .\allow-container-adb.ps1
  ```

  which allows inbound TCP 5037 from the container networks only.

Symptom of getting this wrong: the provider reports `Providing all 1 device(s)`
no matter how many phones are attached, and never logs `Found device` for the
missing ones.

## Files

| File | Purpose |
|---|---|
| `provider-compose.yml` | the provider, pointed at `CORE_IP` |
| `.env.provider` | committed config: `SELF_IP`, `CORE_IP`, ports |
| `start.ps1` | ensure adb is on `0.0.0.0`, then bring the provider up |
| `stop.ps1` | stop the provider |
| `firewall.ps1` | open the stream ports on the WireGuard interface (self-elevates) |
| `allow-container-adb.ps1` | let the provider container reach the host adb (self-elevates) |
| `route-to-core.ps1` | persistent route to the core's `10.10.10.0/24` cable subnet (self-elevates) |
| `add-network-device.ps1` | re-attach an `adb connect` phone and restart the provider |
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
