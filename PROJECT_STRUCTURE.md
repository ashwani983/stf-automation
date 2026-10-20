# Project Structure

## Directory layout

```
stf-automation/
├── README.md                  # overview: the mesh topology and why
├── PROJECT_STRUCTURE.md       # this file
├── .gitignore                 # ignores .env
│
├── windows/                   # THE CORE: Windows PC (10.8.0.4), Docker Desktop
│   ├── README.md
│   ├── docker-compose.yml     # rethinkdb + stf-core + local provider
│   ├── .env                   # STF_IP, ports, admin, STF_AUTH_SECRET (gitignored)
│   ├── start.ps1 / stop.ps1   # bring the stack up / down
│   ├── firewall.ps1           # open panel/stream ports on the WireGuard iface
│   └── adb-service.ps1        # persist adb on 0.0.0.0 across reboots
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
| browser (any mesh member) | core `:7100` | HTTP | the panel |
| browser | provider host `:74xx`/`:76xx` | websocket | device video + touch |
| phone host provider | core `:7114` | ZMQ SUB | commands in |
| phone host provider | core `:7116` | ZMQ PUSH | device metadata / heartbeats |
| phone host provider | core `:7100` | HTTP | uploads, logs |
| core provider | Windows adb `host.docker.internal:5037` | adb | USB phone on the core host |
| phone host provider | local adb `127.0.0.1:5037` | adb | USB phones on that host |

The only client of a phone host's `5037` is its own provider — everything else
is blocked by `restrict-adb.sh`. Nothing on the mesh connects to `5037`.

## Ports

| Port | Host | Notes |
|---|---|---|
| `7100` | core | panel |
| `7110` | core | app websocket |
| `7114`, `7116` | core | provider ZMQ; must be reachable by every phone host |
| `7400-7500` | core | core host's own device video |
| `7600-7700` | phone host | that host's device video |
| `18080` | core | RethinkDB admin, bound to `127.0.0.1` |

`7600-7700` avoids `7680` (Windows Delivery Optimization) and does not overlap
the core's `7400-7500`.

## Health checks

```bash
# core host
docker ps --format '{{.Names}}  {{.Status}}'
docker logs --tail 50 stf-core | grep -E 'is present|Reaping'

# phone host
sudo docker inspect stf-provider-peer --format '{{.State.Status}} {{.State.Health.Status}}'
sudo docker logs --tail 50 stf-provider-peer | grep -E 'Fully operational|Providing all'
sudo systemctl status stf-adb
```

Success looks like `Providing all N device(s)` on the provider and a stream of
`Device "..." is present` lines with no `Reaping` on the core.

## Adding a phone host

1. Get it onto the mesh (WireGuard: it can reach the core's `10.8.0.4`).
2. Copy `peers/` to it and run `sudo STF_CORE_IP=10.8.0.4 bash install-provider.sh`.
3. Pick a free `7600-7700`-style range if another provider already uses it
   **on that same host**. Different hosts may share a range.
4. Device appears in the panel within seconds.
