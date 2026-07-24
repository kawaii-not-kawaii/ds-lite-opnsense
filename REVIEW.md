# Code Review — os-dslite (main branch)

Reviewed: `lib.sh`, `configure.sh`, `teardown.sh`, `status.sh`, `dslite.inc`,
`actions_dslite.conf`, `ServiceController.php`, `DSLite.xml` model.
Cross-checked against the JAIPA **v6mig / HB46PP** spec (spec.md, v1.2).

## Overall

Solid, well-structured plugin. Proper OPNsense MVC + configd + firewall-anchor
integration, syslog facility, dashboard widget, IPv6-only-safe installer, and a
sensible AFTR-discovery priority chain (config → prefix map → DNS → ISP fallback)
with a boot-time PD retry loop. The issues below are mostly hardening and one or
two real functional gaps — nothing structurally wrong.

---

## High impact (functional)

### H1 — Auto-reconfigure won't fire on a v6-only WAN
`dslite.inc` hooks only `newwanip` and `vpn`:

```php
return [
    'newwanip' => ['dslite_configure_do:3'],
    'vpn'      => ['dslite_configure_do:2'],
];
```

Your prerequisite is **WAN IPv4 = None, IPv6 = DHCPv6**. `newwanip` is the IPv4
event — on a v6-only WAN it may never fire, so when the delegated prefix changes
the tunnel won't rebuild automatically. The v6mig spec (§3.6-j) explicitly says a
CPE SHOULD re-provision on detecting its own IPv6 address change.

**Fix:** also hook `newwanipv6`:

```php
return [
    'newwanip'    => ['dslite_configure_do:3'],
    'newwanipv6'  => ['dslite_configure_do:3'],
    'vpn'         => ['dslite_configure_do:2'],
];
```

### H2 — Fixed-IP periodic re-provision is created but never scheduled
`configure.sh` writes `prefix_update.sh`, but nothing registers it to actually run
periodically (no crontab entry, no OPNsense Cron job model). So the ISP-side
registration can lapse over time. Either register an OPNsense cron job
(`configd` job + Cron model) or drop a real crontab entry, and confirm it fires.

---

## Medium (security / spec alignment)

### M1 — `curl -k` disables TLS verification while sending credentials
Both the one-shot and the periodic update use `curl -6 -sk ... -u user:pass`.
`-k` skips certificate validation. The v6mig spec (§3.3) says credentials MUST NOT
be sent unless the connection is HTTPS **with certificate verification** and the
server name matches. Sending `user`/`pass` over an unverified TLS session is both
a spec violation and a real MITM risk.

**Fix:** honor the `t=` flag from the TXT record (verify unless `t=a`), and don't
send credentials on an unverified connection. At minimum, drop `-k` for the
authenticated update URL.

### M2 — Credential handling / masking
- `fixedip_auth_pass` is a plain `TextField`; make the form field a password
  (masked) input in `forms/general.xml`, and consider not echoing it back via API.
- The immediate update in `configure.sh` uses `-u "${USER}:${PASS}"`, which exposes
  the password in the process list (`ps`). You already switched the *periodic*
  script to `--netrc-file` — do the same for the one-shot call.

### M3 — `mss_clamp` config value is dead
The model exposes `mss_clamp` (default 1420), but `configure.sh` only sets
`sysctl net.inet.tcp.mss_ifmtu=1`, which derives MSS from the interface MTU and
ignores the configured value. Users who change the field see no effect.
Either implement it (pf `scrub ... max-mss` rule) or remove the field to avoid
misleading the UI.

---

## Low (polish / robustness)

- **L1 — hardcoded `gif0`.** `ifconfig gif0 create` assumes gif0 is free; it can
  collide with another gif tunnel. Prefer `IF=$(ifconfig gif create)` and use the
  returned unit throughout.
- **L2 — nibble-rounded prefix match.** `ipv6_prefix_match` compares
  `prefixlen/4` hex chars, so a `/30` in `AFTR_MAP` is effectively matched as `/28`.
  Fine for the current table, but imprecise if two ISPs share the first 28 bits.
- **L3 — fragile awk fallbacks.** The non-python paths in `ipv6_to_hex` and
  `get_pd_prefix` (`sprintf("%04s")` doesn't zero-pad in awk; `::` group math) are
  shaky. Low risk since OPNsense ships python3, but worth a comment or removal.
- **L4 — status inconsistency / dead code.** `status.sh` detects up via `RUNNING`
  while `lib.sh get_tunnel_status()` uses `UP`; `get_tunnel_status()` appears unused
  (status.sh reimplements it). Pick one and delete the other.
- **L5 — teardown leaves the /128.** Fixed-IP mode adds a `/128` to the WAN with
  `ifconfig ... inet6 ... prefixlen 128`; `teardown.sh` never removes it.

---

## Spec cross-check notes (v6mig / HB46PP)

- Main branch uses a static prefix→AFTR map + hardcoded fallbacks rather than the
  HB46PP DNS-TXT flow — reasonable, since transix/xpass/v6connect use fixed AFTRs.
  The HB46PP auto-provisioning lives on the `hb46pp` branch (not reviewed here).
- If/when reviewing `hb46pp`: verify the request sends `vendorid` (OUI + optional
  suffix), `product`, `version` (`[0-9_]{1,32}`), and `capability=dslite,ipip`
  over IPv6 (MUST); honor the response `ttl` (cap 604800) instead of a fixed 17h;
  and apply the §3.3 `user`/`pass` MUST-NOT-without-cert-verification rule.
- Response parsing should read `dslite.aftr` and, for fixed IP, the `ipip[]` array
  (`ipv6_local` / `ipv6_remote` / `ipv4`) per §3.4.

---

## What's already good

Clean configd action map; firewall anchors registered via the Firewall plugin API;
`--netrc-file` for the periodic update; sensible MTU 1460; AFTR discovery fallback
chain; PD retry loop at boot; dashboard widget + diagnostics; IPv6-only installer.
This is publishable — fixing H1/H2 and M1 would make it solidly production-grade.
