# STF Automation

Run [DeviceFarmer STF](https://github.com/DeviceFarmer/stf) so Android devices
can be driven from a browser, with the machines spread across a WireGuard mesh:
the **core** on one box, the **phones** wherever they happen to be plugged in.

## Layout

```
                            +---------------------------+
                            |  core host (windows/)     |
                            |  stf-core + rethinkdb     |
                            |  :7100 panel  :7110 ws    |
                            |  :7114/:7116 provider ZMQ |
                            |  + its own phone (USB)    |
                            +------------+--------------+
                                         |  WireGuard
              +--------------------------+--------------------------+
              |                          |                          |
   +----------v----------+    +----------v----------+    +----------v----------+
   | phone host (peers/) |    | phone host (peers/) |    | phone host (peers/) |
   | stf provider        |    | stf provider        |    | stf provider        |
   | adb on 127.0.0.1    |    | ...                 |    | ...                 |
   | video :7600-7700    |    |                     |    |                     |
   +---------------------+    +---------------------+    +---------------------+
```

This is STF's own **multi-provider** topology. Each machine with phones runs
`stf provider` locally, talks to its own adb over loopback, and connects out to
the core's ZMQ buses. Only metadata and control cross the mesh; the browser
fetches video directly from the provider host.

## The two directories that matter

| Directory | Runs on | What it does |
|---|---|---|
| [`windows/`](windows/README.md) | the Windows box (`10.8.0.4`) | the core: RethinkDB, `stf-core`, plus a provider for its own USB phone |
| [`peers/`](peers/README.md) | every host with phones | `install-provider.sh` -> adb + `stf provider`, mesh-only firewall |

Read [`windows/README.md`](windows/README.md) first, then
[`peers/README.md`](peers/README.md) for each additional machine.

## Why not a single `stf local` on one host

Because the phones are not all in one place. And why not the obvious shortcut —
one provider with `--adb-host` pointing at a remote peer — because STF pipes
screen capture through adb, so every video frame would cross the link on one
TCP socket. Upstream itself calls that *"almost unbelievable slowness"*. Putting
a provider next to the phones avoids it.

## Ports at a glance

| Port | Where | Purpose |
|---|---|---|
| `7100` | core host | panel |
| `7110` | core host | app websocket |
| `7114` / `7116` | core host | provider ZMQ in / out |
| `7400-7500` | core host | core host's own provider video |
| `7600-7700` | each phone host | that host's provider video |

Ranges must not overlap per host, and must be free on that host.

## Security model

The boundary is the network, not the app: `stf local` uses STF's **mock** auth
unit, so anyone who can reach the panel has full control of the devices.

* The core's `windows/firewall.ps1` opens ports only on the WireGuard
  interface.
* Each phone host's `peers/restrict-adb.sh` allows `5037` and the worker range
  from loopback and `10.8.0.0/24` only.
* Nothing is bound to the LAN or the internet.
* `STF_AUTH_SECRET` lives in a gitignored `.env`; never commit it.

## Legacy single-host scripts

`docker-compose.yml`, `install.sh`, `start.sh` and `stop.sh` at the top level
are the original all-in-one installer (`stf local --adb-host adb` with a
`/dev/bus/usb`-mounting adb container). They are kept for a plain single Ubuntu
box where STF and the phones share a host. They are **not** used by the
mesh layout above, and they assume the `adb` container can see USB — which it
cannot under Docker Desktop / WSL2, and did not work on the PN64 either.
