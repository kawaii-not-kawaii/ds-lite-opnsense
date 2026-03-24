# OPNsense DS-Lite / Fixed IP Plugin

OPNsense plugin for Japanese ISP IPv4-over-IPv6 tunneling. Supports both **DS-Lite** (shared IPv4 / CG-NAT) and **Fixed IP** (dedicated public IPv4 via IPIP) with **HB46PP auto-provisioning**.

## Features

- **HB46PP Auto-Provisioning** — just enter your ISP credentials, everything else is automatic
- **Fixed IP (IPIP)** — dedicated public IPv4 with inbound port forwarding
- **DS-Lite** — shared IPv4 via CG-NAT, auto-detected from prefix
- **Dashboard widget** — real-time tunnel status on the OPNsense lobby
- **Auto-start on boot** — tunnel comes up automatically after reboot
- **IPv6-only install** — works before the tunnel is up

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

**Important:** After installing the plugin, you need to **reboot OPNsense** for the DS-Lite menu to appear under Interfaces.

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
- **Boot**: Auto-starts via `newwanip` and `vpn` configure hooks

## Performance

Tested on Proxmox VM (4 cores, 4GB RAM) with Intel I226-V 2.5GbE NIC:

| Test | Result |
|------|--------|
| iperf3 8-stream download | 1.89 Gbps |
| iperf3 8-stream upload | 536 Mbps |
| speedtest-cli (Tokyo) | 1065 Mbps down / 475 Mbps up |
| Latency to Google DNS | 23 ms |

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

## License

BSD 2-Clause
