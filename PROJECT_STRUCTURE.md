# Project Structure

## Directory layout

```
stf-automation/
├── README.md                  # overview: the topology and why
├── PROJECT_STRUCTURE.md       # this file
├── .gitignore                 # ignores host-local .env files
│
├── core/                      # THE CORE: Proxmox box, LXC `stf-core`
│   ├── README.md
│   ├── docker-compose.yml     # rethinkdb + stf-core (no provider)
│   ├── .env.example           # committed template
│   ├── .env                   # STF_IP, admin, STF_AUTH_SECRET (gitignored)
│   └── install-core.sh        # install docker if needed, then bring it up
│
├── windows/                   # PHONE HOST: Windows PC (10.8.0.4)
│   ├── README.md
│   ├── provider-compose.yml   # `stf provider` -> Proxmox core (CORE_IP)
│   ├── .env.provider          # SELF_IP, CORE_IP, ports (no secrets)
│   ├── start.ps1 / stop.ps1   # bring the provider up / down
│   ├── firewall.ps1           # open stream ports on the WireGuard iface
│   ├── adb-service.ps1        # persist adb on 0.0.0.0 across reboots
│   └── docker-compose.yml     # legacy: the old core-on-Windows stack
│
├── peers/                     # PHONE HOSTS: one provider per machine with phones
│   ├── README.md
│   ├── install-provider.sh    # install adb service + start the provider
│   ├── provider-compose.yml   # `stf provider` with host networking
│   ├── stf-adb.service        # adb on 0.0.0.0:5037
│   └── restrict-adb.sh        # iptables: loopback + mesh only
│
└── (legacy, single host)
    ├── docker-compose.yml     # `stf local --adb-host adb` + adb container
    ├── install.sh             # Docker-or-manual installer
    ├── start.sh / stop.sh
    └── .env
```

## How the pieces talk

| From | To | Protocol | Purpose |
|---|---|---|---|
| browser (any member) | core `:7100` | HTTP | the panel |
| browser | provider host `:74xx`/`:76xx` | websocket | device video + touch |
| phone host provider | core `:7114` | ZMQ SUB | commands in |
| phone host provider | core `:7116` | ZMQ PUSH | device metadata / heartbeats |
| phone host provider | core `:7100` | HTTP | uploads, logs |
| Windows provider | Windows adb `host.docker.internal:5037` | adb | USB phones on that host |
| peer provider | local adb `127.0.0.1:5037` | adb | USB phones on that host |

The only client of a phone host's `5037` is its own provider — everything else
is blocked by `restrict-adb.sh`. Nothing on the mesh connects to `5037`.

## How the core is reached

The core container lives on the direct cable between Proxmox and `0.6`
(`10.10.10.3`), which is the fast path (~0.5 ms). Mesh members reach the same
container through Proxmox (`10.8.0.5`); it DNATs `7100/7110/7114/7116` into the
container, so no peer needs a route to the cable subnet.

| Client | Address used | Path | Measured |
|---|---|---|---|
| `0.6` | `10.10.10.3` | direct cable | ~0.5 ms |
| Windows PC, `0.3` | `10.8.0.5` | WireGuard -> Proxmox DNAT | ~241 ms |
| browser on the cable | `10.10.10.3` | direct cable | ~0.5 ms |
| browser on the mesh | `10.8.0.5` | WireGuard -> Proxmox DNAT | ~241 ms |

## Ports

| Port | Host | Notes |
|---|---|---|
| `7100` | core | panel |
| `7110` | core | app websocket |
| `7114`, `7116` | core | provider ZMQ; must be reachable by every phone host |
| `7400-7500` | Windows PC | that provider's device video |
| `7600-7700` | peer | that provider's device video |
| `18080` | core | RethinkDB admin, bound to `127.0.0.1` |

`7600-7700` avoids `7680` (Windows Delivery Optimization) and does not overlap
the Windows provider's `7400-7500`.

## Health checks

```bash
# core (on the Proxmox host: pct exec 110 -- <cmd>, or ssh in)
docker ps --format '{{.Names}}  {{.Status}}'
docker logs --tail 50 stf-core | grep -E 'is present|Reaping'
curl -s -o /dev/null -w '%{http_code}\n' http://10.10.10.3:7100/   # 302 = up

# phone host
docker inspect stf-provider-peer --format '{{.State.Status}} {{.State.Health.Status}}'
docker logs --tail 50 stf-provider-peer | grep -E 'Fully operational|Providing all'
systemctl status stf-adb

# Windows PC
docker inspect stf-provider-win --format '{{.State.Status}} {{.State.Health.Status}}'
docker logs --tail 50 stf-provider-win | grep -E 'Fully operational|Providing all'
```

Success looks like `Providing all N device(s)` on each provider, `Fully
operational` per device, and on the core a stream of `Device "..." is present`
lines with no `Reaping`.

## Adding a phone host

1. Get it onto the mesh (WireGuard), so it can reach Proxmox at `10.8.0.5`.
2. Copy `peers/` to it and run `sudo STF_CORE_IP=10.8.0.5 bash install-provider.sh`.
3. Pick a free `7600-7700`-style range if another provider already uses it
   **on that same host**. Different hosts may share a range.
4. Device appears in the panel within seconds.

A host on the `10.10.10.0/24` cable (like `0.6`) can instead use
`STF_CORE_IP=10.10.10.3` for a sub-millisecond path to the core.
