# STF core (Proxmox)

The brain of the farm: `stf-core` + `rethinkdb`. It runs **no provider** — no
phone is plugged into the Proxmox box. Every phone host runs its own
`stf provider` that connects back here. See [`../peers/`](../peers/) and
[`../windows/`](../windows/).

```
providers (0.3 / 0.6 / Windows PC) --ZMQ 7114+7116--> stf-core --> rethinkdb
browser --HTTP 7100--> poorxy (stf-core)
browser --ws://<provider-ip>:74xx--> the provider actually holding the device
```

## Where it runs

An **LXC container on the Proxmox host**, not a VM: `stf-core`, CTID **110**.

| | |
|---|---|
| Host | Proxmox (`10.8.0.5` on the mesh, `10.10.10.1` on the direct cable) |
| Container | privileged, `features: nesting=1,keyctl=1` (same shape as the `photoprism` CT) |
| Size | 4 cores, 4 GB RAM, 24 GB on `local-lvm`, `onboot=1` |
| Address | `10.10.10.3/24` on `vmbr0` — the **direct cable** to host `0.6` |
| Panel | <http://10.10.10.3:7100> |

Why an LXC on the PVE host rather than Docker on the PVE host itself: the box is
a hypervisor and stays that way (no Docker installed on it, deliberately), while
the container gives STF a narrowly-scoped root filesystem and its own restart
policy. Nesting/keyctl are needed because the STF image runs its own postgres
of systemd-ish bits; the existing `photoprism` container proves the pattern.

## Networking

`stf-core` lives on the **direct cable** between Proxmox and `0.6`
(`10.10.10.0/24`: Proxmox `.1`, `0.6` `.2`, core `.3`). That link measures
**~0.5 ms** versus **~241 ms** across the WireGuard mesh, so `0.6` — the host
with the most capable hardware and the Fire tablet — gets the fast path to the
core.

The other providers reach the same core over the **WireGuard mesh** (they land
on Proxmox's `10.8.0.5` and are routed/NATed from there). This is the honest
trade-off: `0.6` is fast, `0.3`/Windows are mesh-bound. The device *video* path
is unaffected either way, because streams are served by the provider holding the
device (see `../peers/README.md`), not by the core.

Two things this depends on, both set up on the Proxmox host:

- `vmbr0` is **static** `10.10.10.1/24`. It was `inet dhcp`, but there is no
  DHCP server on that cable, so the old `/30` was hand-set and would not have
  survived a reboot.
- A `pve-stf-nat` systemd unit adds `MASQUERADE` on the WireGuard uplink
  (`Office_pc`). The host's internet route goes out `Office_pc`, but the only
  pre-existing masquerade rule was for `wlp3s0`, so traffic from `10.10.10.0/24`
  (and `0.6`) had no working return path.

## Running it

```sh
cp .env.example .env      # then edit: STF_IP, STF_ADMIN_*, STF_AUTH_SECRET
docker compose up -d
docker compose logs -f stf-core
```

`install-core.sh` does this for you inside the CT, including installing Docker
on a fresh Debian 12 container.

## Logging in

The root admin is created by STF's `migrate` step from `STF_ADMIN_EMAIL` /
`STF_ADMIN_NAME` in `.env`, and STF's mock auth accepts any password.

> `STF_ADMIN_EMAIL` **must** be a real-looking email (it needs a TLD). The mock
> login validator rejects addresses like `admin@localhost`.

## Publishing the ZMQ buses

`--bind-dev-pub` / `--bind-dev-pull` are set to `0.0.0.0`, and ports `7114` and
`7116` are published. That is what lets a provider on *another* host join this
core. `7115` (dev dealer) is core-internal and not needed by providers.
