# Fork Review — unchained-llc/os-ocnfixedip

A fork of this project, retargeted and productionized for **OCN Fixed IP (IPoE)**
(NTT Communications). It narrows scope to one ISP/service and hardens the Fixed-IP
IPIP path. Reviewed: `README.md`, `ocnfixedip.inc`, `configure.sh`, plus file tree
and behavior notes.

## What they changed (vs your `main`)

**Scope & identity**
- Dropped DS-Lite and multi-ISP profiles; OCN Fixed IP (IPIP) only. Namespace
  renamed `DSLite` → `OCNFixedIP`.
- Fixed peer IPv4 `192.0.0.1`, single `gif0` — deliberately simplified.

**Packaging (big upgrade)**
- Real FreeBSD `.pkg` via `Makefile` + `tools/build-pkg.sh`, distributed through
  GitHub Releases (`pkg add -f …`). Replaces the `curl | sh` installer. Clean
  upgrade/uninstall through `pkg`. This is the single most reusable improvement.

**They fixed my review findings**
- **H1 (react to v6 renewal) — FIXED, and it teaches the correct pattern.** Rather
  than adding a `newwanipv6` hook key, they keep `newwanip` but read the `$family`
  arg: `rc.newwanipv6` calls `plugins_configure("newwanip", …, "inet6")`, and they
  early-return unless `family === 'inet6'`. So it reconfigures precisely on IPv6
  renewal and ignores IPv4 triggers. Confirms H1 was a real gap; this is the cleaner
  implementation to port back.
- **M2 (creds in `ps`) — FIXED.** The immediate prefix update now writes a
  `mktemp` `0600` netrc and uses `curl --netrc-file`, so credentials never appear in
  process args. (Your periodic script already did this; they extended it to the
  one-shot call.)
- **L5 (teardown leaves the /128) — FIXED.** They track the managed alias in
  `/var/run/ocnfixedip_local_tunnel_v6` and remove the stale `/128` when the prefix
  changes, before adding the new one.

**They resolved M3 by removing it**
- The dead `mss_clamp` field and the auto-NAT are gone. MSS is now a documented
  manual pf **Normalization** rule (Max MSS 1420), and outbound NAT is admin-managed.
  Trade-off: more idiomatic OPNsense integration, less turnkey.

**New robustness**
- 3-second debounce stamp to drop duplicate configure triggers during save/renewal
  races.
- `get_wan_global_v6_with_retry` to ride out DHCPv6 renewal timing.
- Best-effort auto-assignment of `gif0` as a real OPNsense interface (`TUNNEL`) via a
  guarded `write_config`, so the admin can build a proper gateway + outbound NAT from
  the GUI. Route set with `route change` (delete/add fallback) instead of raw
  delete/add.
- Local IPv6 calc normalized to a `/56` base with iface-ID = `ipv4 << 24`, explicitly
  handling the HGW-in-front `/60` case.

**Major observability upgrade (worth porting back)**
- `diagnostics.sh` 1.3 KB → **17 KB**, `status.sh` 2.1 KB → **7.2 KB**. A composite
  `HEALTHY` state checks: gif RUNNING, default route via peer, DNS A/AAAA, MTU match,
  `/128` alias presence, last prefix-update result (`good`/`nochg`), BR ping, v4/v6
  internet ping from tunnel source, DF MTU probes, and fragmentation tests. Prefix-
  update result persisted to `/var/run` for the widget.

## What they did NOT fix

- **M1 (`curl -k`)** still disables TLS verification — but now documented in Security
  Notes, and largely moot because OCN's update endpoint is plain `http://
  ipoe-static.ocn.ad.jp/nic/update` (a DynDNS-style `nic/update`, returning
  `good`/`nochg`/`nohost`).
- **L1 (hardcoded `gif0`)** — still hardcoded, listed as a known limitation.

## Design-philosophy difference

| | Your `main` | Fork |
|---|---|---|
| Scope | DS-Lite + Fixed IP, multi-ISP | OCN Fixed IP only |
| NAT / MSS | Plugin does it (pf anchors, sysctl) | Admin does it (outbound NAT + Normalization) |
| Install | `curl \| sh` | `.pkg` via Releases |
| Diagnostics | Basic | Extensive health suite |
| Gateway | Raw default route | Auto-assign `gif0` → real OPNsense gateway |

Neither is strictly "better": yours is broader and more turnkey; theirs is narrower,
more idiomatic to OPNsense subsystems, and far better instrumented.

## Performance data point

Their user report: **8.80 Gbps down / 8.13 Gbps up** (iperf3 8-stream) on a 16-vCPU
Ryzen 3700X + ConnectX-4 VM — vs your 1.89 Gbps on a 4-core VM. Confirms the IPIP
tunnel scales with CPU and that near-10G Fixed-IP is achievable with enough cores /
single-thread headroom. Encouraging for the i5-8500 build (Fixed-IP IPIP is lighter
than DS-Lite CGN).

## Recommended to port upstream

1. The `$family === 'inet6'` hook filter (implements H1 cleanly).
2. The netrc one-shot update (M2) and the `/128` alias state-file lifecycle (L5).
3. The `.pkg` packaging (Makefile + build-pkg.sh).
4. The diagnostics/status health suite — the highest-value borrow.
