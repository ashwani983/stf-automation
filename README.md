# STF Automation

Run [DeviceFarmer STF](https://github.com/DeviceFarmer/stf) so Android devices
can be driven from a browser, spread across a WireGuard mesh: the **core** on
the Proxmox box, the **phones** wherever they happen to be plugged in.

## Layout

```
                    +---------------------------------------------+
                    |  core: Proxmox (core/)                      |
                    |  LXC stf-core + rethinkdb                   |
                    |  :7100 panel   :7110 ws                     |
                    |  :7114/:7116 provider ZMQ                   |
                    |  See core/README.md              |
                    |  panel: http://10.8.0.5:7100  <- use this    |
                    |  10.10.10.3  <- direct cable, ~0.5 ms       |
                    |  10.8.0.5    <- WireGuard mesh, ~241 ms     |
                    +------+-----------------+--------------------+
                           |                 |
              fast cable   |                 |  WireGuard mesh
                           |                 |
              +------------v------+   +------v-----------------------------+
              | 0.6 (peers/)      |   | Windows PC (windows/)  + 0.3 (peers/)|
              | stf provider      |   | stf provider          | stf provider |
              | video :7600-7700  |   | video :7400-7500      | :7600-7700   |
              +-------------------+   +--------------------------------------+
```

This is STF's own **multi-provider** topology. Each machine with phones runs
`stf provider` locally, talks to its own adb over loopback, and connects out to
the core's ZMQ buses. Only metadata and control cross the network; the browser
fetches video directly from the provider host.

## The directories that matter

| Directory | Runs on | What it does |
|---|---|---|
| [`core/`](core/README.md) | the Proxmox box | the core: RethinkDB + `stf-core`, an LXC container |
| [`windows/`](windows/README.md) | the Windows box (`10.8.0.4`) | provider for its own USB phone(s) |
| [`peers/`](peers/README.md) | `0.3` and `0.6` | `install-provider.sh` -> adb + `stf provider`, mesh-only firewall |

Read [`core/README.md`](core/README.md) first, then
[`peers/README.md`](peers/README.md) for each phone host.

## The core sits on the fast link

The Proxmox box and host `0.6` are joined by a **direct cable**, and the core
container lives on it (`10.10.10.0/24`). Measured on that link: **~0.5 ms**,
against **~241 ms** across the WireGuard mesh. The host with the Fire tablet
therefore gets a fast path to the core.

Providers on `0.3` and the Windows PC reach the same core over the **mesh**, at
Proxmox's mesh address (`10.8.0.5`); Proxmox forwards the core's ports on to the
container. That is the honest trade-off of this layout — `0.6` is fast,
`0.3`/Windows are mesh-bound — and it costs nothing for video, which never
passes through the core anyway.

## Why not a single `stf local` on one host

Because the phones are not all in one place. And why not the obvious shortcut —
one provider with `--adb-host` pointing at a remote peer — because STF pipes
screen capture through adb, so every video frame would cross the link on one
TCP socket. Upstream itself calls that *"almost unbelievable slowness"*. Putting
a provider next to the phones avoids it.

## Ports at a glance

| Port | Where | Purpose |
|---|---|---|
| `7100` | core | panel |
| `7110` | core | app websocket |
| `7114` / `7116` | core | provider ZMQ in / out |
| `7400-7500` | Windows PC | that provider's video |
| `7600-7700` | each peer | that provider's video |

Ranges must not overlap per host, and must be free on that host.

## Security model

The boundary is the network, not the app: `stf local` uses STF's **mock** auth
unit, so anyone who can reach the panel has full control of the devices.

* The core is itself on a private `/24` cable, reachable from the mesh only
  through Proxmox, which DNATs just the four core ports.
* Each phone host's `peers/restrict-adb.sh` allows `5037` and the worker range
  from loopback and `10.8.0.0/24` only; the Windows `firewall.ps1` opens its
  stream range only on the WireGuard interface.
* Nothing is bound to the LAN or the internet.
* `STF_AUTH_SECRET` lives in a gitignored `.env` on the core; never commit it.

## Legacy single-host scripts

`docker-compose.yml`, `install.sh`, `start.sh` and `stop.sh` at the top level,
and `windows/docker-compose.yml`, are earlier layouts: the first is the original
all-in-one installer (`stf local --adb-host adb` with a `/dev/bus/usb`-mounting
adb container) and the second is the core-on-Windows stack. They are kept for
rollback and for the single-host case. They are **not** used by the layout
above.
