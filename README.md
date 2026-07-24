# OPNsense DS-Lite / Fixed IP Plugin

OPNsense plugin for Japanese ISP IPv4-over-IPv6 tunneling. Supports both **DS-Lite** (shared IPv4 / CG-NAT) and **Fixed IP** (dedicated public IPv4 via IPIP) with **HB46PP auto-provisioning**.

## Features

- **HB46PP Auto-Provisioning** — just enter your ISP credentials, everything else is automatic
- **Fixed IP (IPIP)** — dedicated public IPv4 with inbound port forwarding
- **DS-Lite** — shared IPv4 via CG-NAT, auto-detected from prefix
- **Dashboard widget** — real-time tunnel status and health on the OPNsense lobby
- **Health status & diagnostics** — composite HEALTHY/degraded state plus a structured endpoint-check panel (route, DNS, CE→AFTR, v4/v6 Internet, MTU/fragmentation, prefix update)
- **Auto-reconfigure on prefix change** — rebuilds the tunnel on IPv6 (PD) renewal, not just at boot
- **Auto-start on boot** — tunnel comes up automatically after reboot
- **IPv6-only install** — works before the tunnel is up
- **Package build** — produce a FreeBSD `.pkg` with `make pkg` for clean install/upgrade/uninstall

## Branches

| Branch | Description |
|--------|-------------|
| `main` | Stable DS-Lite + manual Fixed IP |
| `hb46pp` | **Experimental** — HB46PP auto-provisioning for both modes |

## Supported ISPs / VNEs

| VNE Service | DS-Lite | Fixed IP (IPIP) | HB46PP Auto |
|-------------|---------|-----------------|-------------|
| v6 Connect (Asahi Net) | Yes | Yes | Yes |
| Transix (Internet Multifeed) | Yes | - | Untested |
| Xpass (ARTERIA Networks) | Yes | - | Untested |
| BIGLOBE IPv6 (IPIP) | - | Yes | Untested |
| OCX Hikari Internet | - | Yes | Untested |

Any ISP using the [HB46PP standard provisioning protocol](https://github.com/v6pc/v6mig-prov/blob/master/spec.md) should work automatically.

### Tested on

- **Asahi Net** (asahi-net.jp) + NTT West Flets Hikari Cross (10G plan)
- OPNsense 25.1 and 26.1.4 (FreeBSD 14.2)
- Fixed IP: inbound port forwarding verified
- Performance: 1.89 Gbps (iperf3 8-stream) through DS-Lite tunnel

## Installation

### On OPNsense (IPv6-only safe)

**HB46PP branch (recommended for Fixed IP users):**

```sh
curl -6 -skL -o /tmp/install-dslite.sh "https://raw.githubusercontent.com/kawaii-not-kawaii/ds-lite-opnsense/hb46pp/os-dslite-hb46pp/install.sh" && sh /tmp/install-dslite.sh
```

**Main branch (DS-Lite only):**

```sh
curl -6 -skL -o /tmp/install-dslite.sh "https://raw.githubusercontent.com/kawaii-not-kawaii/ds-lite-opnsense/main/os-dslite/install.sh" && sh /tmp/install-dslite.sh
```

### Remote install via SSH

```sh
git clone https://github.com/kawaii-not-kawaii/ds-lite-opnsense.git
cd ds-lite-opnsense/os-dslite-hb46pp  # or os-dslite for main branch
./deploy.sh <opnsense-ip>
```

### Build & install as a package (recommended)

Building a real FreeBSD `.pkg` gives you clean upgrades and a proper uninstall via
`pkg`. On the OPNsense box (or any FreeBSD host with the source tree):

```sh
cd ds-lite-opnsense/os-dslite
make pkg                                   # writes dist/os-dslite-<version>.pkg
pkg add -f dist/os-dslite-*.pkg
```

The package's post-install hook restarts `configd`, clears the UI cache, and — when
the plugin is enabled — reconfigures the tunnel, so an upgrade restores connectivity
without a reboot or a manual Apply. A disabled plugin is left alone. Uninstall only
removes a default route and a `gif` interface the plugin can prove it created, so an
unrelated tunnel or gateway on the box is never touched. See
[Building a Package](#building-a-package) for build options.

**Important:** After installing the plugin, you need to **reboot OPNsense** (or log
out/in) for the DS-Lite menu to appear under Interfaces.

## Prerequisites

1. **WAN interface** (connected to NTT ONT)
   - IPv4 Configuration Type: **None**
   - IPv6 Configuration Type: **DHCPv6**

2. **LAN interface**
   - IPv6 Configuration Type: **Track Interface** (tracking WAN)

### NTT Prefix Delegation by Plan

| Plan | Typical PD Size | Notes |
|------|----------------|-------|
| Hikari Cross (10G) | /56 | Guaranteed PD, IPoE only |
| Flets Hikari Next (1G) | /56 or /64 | PD available with current firmware |
| Legacy 1G (no Hikari Denwa) | /64 | May require manual prefix config |

## Usage

### Fixed IP (with HB46PP auto-provisioning)

1. Navigate to **Interfaces > DS-Lite**
2. Enable, select **Fixed IP** mode
3. Enter your ISP provisioning credentials (User ID + Password)
4. Select WAN interface
5. Click **Apply**

The plugin automatically discovers the provisioning server, authenticates, and configures the IPIP tunnel with your dedicated public IPv4.

### DS-Lite (shared IPv4)

1. Navigate to **Interfaces > DS-Lite**
2. Enable, select **DS-Lite** mode
3. Select WAN interface
4. Click **Apply**

The AFTR is auto-detected from your IPv6 prefix. No credentials needed for most ISPs.

### Port Forwarding (Fixed IP only)

With a Fixed IP, you get a dedicated public IPv4 address. Port forwarding works through OPNsense's standard Destination NAT:

**Firewall > NAT > Destination NAT** → Add rule mapping external port to internal server.

## How it works

### HB46PP Protocol

[HB46PP](https://github.com/v6pc/v6mig-prov/blob/master/spec.md) (HTTP-Based IPv4 over IPv6 Provisioning Protocol) is a Japanese standard for auto-configuring IPv4-over-IPv6 tunnels.

```
1. DNS TXT lookup: 4over6.info → provisioning server URL
2. HTTP GET with credentials → JSON response with tunnel parameters
3. Auto-configure gif tunnel with received AFTR, local IPv6, fixed IPv4
4. Re-provision every TTL (~17 hours) to maintain registration
```

The plugin implements this protocol to provide the same auto-provisioning experience as supported commercial routers (Yamaha, Buffalo, Allied Telesis, etc.).

### Tunnel Architecture

**Fixed IP (IPIP):**
```
[LAN] → [OPNsense NAT] → [gif0 IPIP tunnel] → [AFTR] → [Internet]
                                                     ↓
[Internet] → [AFTR] → [gif0] → [Destination NAT] → [LAN server]
```

**DS-Lite:**
```
[LAN] → [OPNsense NAT] → [gif0 DS-Lite tunnel] → [AFTR CG-NAT] → [Internet]
```

### Technical Details

- **Tunnel interface**: FreeBSD `gif` (IPv4-in-IPv6 encapsulation)
- **MTU**: 1460 (1500 - 40 byte IPv6 header)
- **MSS clamping**: Automatic via `net.inet.tcp.mss_ifmtu`
- **NAT**: pf masquerade via registered anchors
- **Firewall**: Integrated with OPNsense's pf anchor system
- **Boot & renewal**: Auto-starts via the `vpn` boot hook and reconfigures on IPv6
  (PD) renewal via the `newwanip` hook filtered to the `inet6` family — so the tunnel
  rebuilds when the delegated prefix changes on a v6-only WAN, not only at boot
- **Credential handling**: prefix-update auth is passed via a mode-`0600` `netrc`
  file, never on the `curl` command line, and only over HTTPS with certificate
  verification unless **Allow Insecure Update URL** is explicitly enabled
- **WAN alias lifecycle**: the tunnel-local `/128` is tracked in
  `/var/run/dslite_local_tunnel_v6` as `<device> <address>`; the alias is verified
  present before the tunnel is replaced, and stale aliases are removed when the
  prefix, the mode, or the WAN device changes, and on teardown
- **Ownership tracking**: the tunnel interface and the default route we installed are
  recorded in `/var/run/dslite_owned_tunnel` and `/var/run/dslite_owned_route`, and
  teardown removes only what matches
- **Fixed IP refresh**: registered as a cron job (`*/30`) via the plugin's `_cron()`
  hook, running the `dslite prefix_update` configd action

## Performance

Tested on Proxmox VM (4 cores, 4GB RAM) with an Intel **I226-V 2.5GbE** NIC:

| Test | Result |
|------|--------|
| iperf3 8-stream download | 1.89 Gbps |
| iperf3 8-stream upload | 536 Mbps |
| speedtest-cli (Tokyo) | 1065 Mbps down / 475 Mbps up |
| Latency to Google DNS | 23 ms |

> **Note:** the 1.89 Gbps download figure is close to the 2.5GbE link rate, so the
> NIC is the most likely limit here, but this was not isolated — CPU and AFTR-side
> capacity were not ruled out. Separately, an anecdotal user report on the OCN Fixed
> IP fork measured **~8.8 Gbps down / 8.1 Gbps up** (iperf3 8-stream) on a 16-vCPU
> host with a 10/25GbE NIC. That is a different service, a different codebase and
> different hardware, so treat it as an existence proof that the `gif` path can go
> past 2.5G, not as a prediction for this plugin on your box. DS-Lite throughput is
> additionally bounded by the VNE's shared AFTR.

## Health Status & Diagnostics

The plugin exposes two levels of visibility, both available in the UI
(**Interfaces > DS-Lite**), the dashboard widget, and from the shell.

### Health status (`configctl dslite status`)

Returns a JSON object with a composite `health` field (`healthy` / `degraded` /
`offline`) and a `health_failures` list naming any checks that failed. The tunnel is
`healthy` only when it is up, the default route points through it, and end-to-end
connectivity succeeds. Checks are **mode-aware** — the WAN `/128` alias and prefix-
update checks apply to Fixed IP mode only.

The settings page polls this endpoint every 5 seconds and the dashboard widget polls
it on every tick, so the two classes of check have different freshness:

- **Passive checks** (interface flags, default route, MTU, WAN alias, DNS, stored
  prefix-update result) are re-evaluated on every call.
- **Active probes** (CE→AFTR, IPv4/IPv6 Internet, DF-MTU, fragmentation) are cached
  in `/var/run/dslite_health_cache` for **30 seconds**, and invalidated whenever the
  tunnel's addresses or MTU change. Each probe waits up to **2000 ms**
  (`PING_WAIT_MS`); FreeBSD's `ping -W` is in milliseconds, so this is 2 seconds.
- CE→AFTR reachability and IPv4 Internet are evaluated **independently**: an AFTR
  that filters ICMPv6 echo shows up as `ce_to_br` without falsely reporting the
  IPv4 path as down.
- A stored prefix-update success older than 90 minutes (`PREFIX_UPDATE_MAX_AGE`)
  reports `prefix_update_stale`, so a scheduler that has stopped running cannot keep
  the tunnel looking healthy indefinitely.

```sh
configctl dslite status
```

Example (degraded, MTU mismatch + no IPv6 Internet):

```json
{"tunnel":{"status":"up","connectivity":"connected","health":"degraded",
 "health_failures":"mtu,ipv6_internet","mode":"fixedip","local_v6":"…",
 "aftr":"…","ipv4":"…","mtu":"1500","interface":"gif0","reason":""}}
```

### Diagnostics (`configctl dslite diagnostics`)

Runs an extended, structured set of endpoint checks and returns them as JSON for the
Diagnostics panel. Each check reports `ok` / `ng` / `skipped` / `not-configured`:

| Check | What it verifies |
|-------|------------------|
| `tunnel_state` | `gif0` exists and is UP/RUNNING |
| `default_route` | IPv4 default routes through the tunnel (DS-Lite: via the AFTR gateway) |
| `wan_alias` | The tunnel-local `/128` alias is present on WAN (Fixed IP) |
| `ce_to_aftr` | IPv6 ping from the CE source to the AFTR/BR endpoint |
| `prefix_update` | Stored result of the last prefix update is `good`/`nochg` and recent (Fixed IP) |
| `internet_v4` / `internet_v6` | Ping 1.1.1.1 / 2606:4700:4700::1111 from tunnel/CE source |
| `resolve_a` / `resolve_aaaa` | DNS A / AAAA resolution |
| `mtu` | Configured MTU matches the interface MTU |
| `mtu_probe` | DF ping at exact MTU (path-MTU sanity) |
| `mtu_fragmentation` | Oversized non-DF ping (fragmentation behavior) |

> Diagnostics is **read-only**. The `prefix_update` row reports the stored result of
> the last update (with its age, and `stale` when it is too old) rather than
> contacting the ISP, so opening or refreshing the page never spends credentials or
> changes provider-side state. To force a live update, use the **Run prefix update
> now** button, or `configctl dslite prefix_update` from the shell.

## Building a Package

You can build a FreeBSD package from the source tree on OPNsense/FreeBSD:

```sh
cd ds-lite-opnsense/os-dslite
make pkg
pkg add -f dist/os-dslite-*.pkg
```

Optional build variables:

```sh
make pkg PKG_VERSION=2026.07.25.1 \
         PKG_MAINTAINER=you@example.com \
         PKG_ORIGIN=net/os-dslite
```

- Output packages are written to `os-dslite/dist/`.
- Post-install restarts `configd`, clears UI caches, and pre-creates `gif0`.
- `pkg delete os-dslite` stops the service and removes plugin files; it leaves your
  `//OPNsense/dslite` configuration in `config.xml` intact.
- `make clean` removes build artifacts (`.pkgbuild/`, `dist/`).

## References & Sources

- [HB46PP Specification](https://github.com/v6pc/v6mig-prov/blob/master/spec.md) — the provisioning protocol spec
- [Yamaha Router HB46PP Documentation](https://www.rtpro.yamaha.co.jp/RT/docs/hb46pp/index.html) — where we discovered the protocol
- [Yamaha v6 Connect IPIP Guide](https://www.rtpro.yamaha.co.jp/UTM/docs/utx/v6_connect/ipip.html) — configuration examples
- [Asahi Net Fixed IP Setup](https://asahi-net.jp/support/guide/flets_cross/) — ISP documentation
- [OPNsense Plugin Development](https://docs.opnsense.org/development/api.html) — MVC framework reference
- [FreeBSD gif(4)](https://man.freebsd.org/cgi/man.cgi?gif(4)) — tunnel interface documentation
- [RFC 6333](https://datatracker.ietf.org/doc/html/rfc6333) — DS-Lite specification

## Uninstall

```sh
curl -6 -skL -o /tmp/uninstall-dslite.sh "https://raw.githubusercontent.com/kawaii-not-kawaii/ds-lite-opnsense/hb46pp/os-dslite-hb46pp/uninstall.sh" && sh /tmp/uninstall-dslite.sh
```

## Compatibility

- OPNsense 24.1+ (FreeBSD 14.x)
- Tested on OPNsense 25.1 and 26.1.4

## Credits

The health-check suite, `netrc`-based credential handling, WAN `/128` alias
lifecycle, IPv6-renewal reconfigure pattern, and `.pkg` packaging were adapted from
[unchained-llc/os-ocnfixedip](https://github.com/unchained-llc/os-ocnfixedip)
(a downstream, OCN-focused fork of this project), used under the BSD 2-Clause license.

## License

BSD 2-Clause
