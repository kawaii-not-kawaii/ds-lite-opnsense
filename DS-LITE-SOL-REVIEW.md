# DS-Lite Solution Review

**Review date:** 2026-07-25  
**Repository:** `ds-lite-opnsense`  
**Working branch:** `merge-fork-improvements`  
**Reviewed baseline:** `53b9b12` (`origin/main`)  
**Disposition:** Changes required before production packaging or merge

## 1. Review scope

This review covers the fork-improvement work present in the working tree at the time of review:

- 17 staged files, approximately `+2488/-1690` lines.
- One additional unstaged `README.md` change containing package, health, and performance claims.
- `FORK-REVIEW.md` and `REVIEW.md`, reconciled against the current implementation.
- OPNsense WAN hook behavior, FreeBSD command semantics, package lifecycle, tunnel and alias ownership, prefix-update security, health reporting, diagnostics, and dashboard rendering.

The working tree did not contain a committed merge: `HEAD` still matched `origin/main` at `53b9b12`. This report therefore reviews staged and unstaged changes rather than a merge commit.

### Files examined

Primary changed files:

- `.gitattributes`
- `.gitignore`
- `FORK-REVIEW.md`
- `REVIEW.md`
- `README.md` (unstaged)
- `dslite.md`
- `os-dslite/Makefile`
- `os-dslite/tools/build-pkg.sh`
- `os-dslite/src/etc/inc/plugins.inc.d/dslite.inc`
- `os-dslite/src/opnsense/scripts/OPNsense/dslite/configure.sh`
- `os-dslite/src/opnsense/scripts/OPNsense/dslite/diagnostics.sh`
- `os-dslite/src/opnsense/scripts/OPNsense/dslite/lib.sh`
- `os-dslite/src/opnsense/scripts/OPNsense/dslite/status.sh`
- `os-dslite/src/opnsense/scripts/OPNsense/dslite/teardown.sh`
- `os-dslite/src/opnsense/mvc/app/views/OPNsense/DSLite/diagnostics.volt`
- `os-dslite/src/opnsense/www/js/widgets/DSLite.js`
- `os-dslite/src/opnsense/www/js/widgets/Metadata/DSLite.xml`

Related integration files were also checked where the changed contracts are consumed, including `ServiceController.php`, `general.volt`, `general.xml`, `DSLite.xml`, and `actions_dslite.conf`.

## 2. Executive summary

The merge ports several useful ideas from `unchained-llc/os-ocnfixedip`:

- IPv6-renewal handling through OPNsense's `newwanip` family argument.
- Mode-`0600` netrc files for one-shot authenticated prefix updates.
- State-backed WAN `/128` alias cleanup.
- FreeBSD package construction.
- Structured health and diagnostics output.
- A richer dashboard widget and diagnostics table.

The current integration is not production-ready. The highest-risk defects are:

1. Package uninstall can delete an unrelated IPv4 default route and destroy an unrelated `gif0`.
2. Authenticated prefix updates still disable TLS verification and may use plain HTTP.
3. Package upgrades stop the tunnel without restoring it.
4. Health probes use a 2-millisecond timeout on FreeBSD and therefore generate false failures.
5. Fixed-IP periodic prefix updates remain unscheduled, while stale success state can remain healthy indefinitely.
6. The widget renders some explicitly degraded states as green and connected.
7. Alias-add failure is treated as success before the working tunnel is replaced.
8. Diagnostics interpolate unescaped provider data into JSON.
9. Opening the diagnostics page performs an authenticated, state-changing provider update.
10. The `vpn` hook truncates the family argument, defeating the intended IPv4 filter and duplicating IPv6 work.

The packaging and documentation should not be published as “clean install/upgrade/uninstall” until the package lifecycle is ownership-safe and upgrade-aware.

## 3. Severity model

| Severity | Meaning |
|---|---|
| P0 | Can expose credentials, remove unrelated network state, or cause immediate administrative lockout/outage. Must be fixed before merge. |
| P1 | Breaks a primary feature, produces materially false operational state, or creates a likely service outage. Must be fixed before release. |
| P2 | Reliability, maintenance, packaging hygiene, or documentation defect. Fix before calling the work production-ready. |

## 4. Detailed findings

### F-01 — P0: Package teardown can remove unowned system networking

**Locations:**

- `os-dslite/tools/build-pkg.sh:76-84`
- `os-dslite/src/opnsense/scripts/OPNsense/dslite/teardown.sh:13-24`

**Behavior:**

The package `pre-deinstall` script unconditionally runs:

```sh
configctl dslite stop
```

`teardown.sh` then unconditionally runs `route delete default`. If any `gif0` exists, it is brought down and destroyed. Neither operation proves that the route or interface belongs to this plugin.

The package post-install script also pre-creates `gif0` even when the plugin is disabled. If `gif0` belonged to another GIF user before installation, the package does not distinguish it from its own tunnel.

**Impact:**

- `pkg delete os-dslite` can remove the active WAN default route.
- A remote administrator can lose access during uninstall.
- An unrelated GIF tunnel using `gif0` can be destroyed.
- The defect applies even when DS-Lite is disabled or was never configured.

**Observed evidence:**

A mocked teardown with no tunnel present still emitted:

```text
delete default
```

**Required correction:**

- Do not pre-create `gif0` in package hooks.
- Persist the plugin-owned tunnel interface, route gateway/interface, and managed aliases.
- Delete the default route only when `route -n get default` matches the recorded plugin route.
- Destroy a GIF interface only when ownership and expected endpoints are confirmed.
- Make teardown idempotent and safe when disabled or partially configured.

**Acceptance criteria:**

- Uninstalling an enabled, disabled, and never-configured plugin preserves unrelated default routes and GIF interfaces.
- Repeated stop/uninstall operations are harmless.
- An unrelated `gif0` remains untouched.

### F-02 — P0: Authenticated prefix updates remain interceptable

**Locations:**

- `configure.sh:102`
- Generated helper in `configure.sh:274`
- `diagnostics.sh:196`
- `DSLite.xml:85-87`

**Behavior:**

All authenticated prefix-update paths use `curl -k`, disabling server certificate verification. The configured update URL is a generic `UrlField`, so plain HTTP is also accepted.

Moving credentials from `curl -u` to a netrc file correctly removes them from the process argument list, but it does not protect them in transit.

**Impact:**

- A network attacker can intercept the username and password.
- An attacker can impersonate the update endpoint and return forged status.
- This remains inconsistent with the v6mig/HB46PP requirement not to transmit credentials without verified HTTPS.
- Plain HTTP is worse than an unverified HTTPS session; `-k` being irrelevant to HTTP does not make the exposure moot.

**Required correction:**

- Require `https://` for authenticated update URLs.
- Remove `-k` from authenticated curl calls.
- Honor the provisioning protocol's transport policy where applicable.
- Refuse to send credentials when certificate or hostname verification fails.
- Add a finite `--max-time`; `--connect-timeout` alone does not bound a server that accepts a connection and then stalls.

**Acceptance criteria:**

- Authenticated HTTP URLs are rejected.
- A bad, expired, or hostname-mismatched certificate prevents credential transmission.
- All update paths use the same verified transport policy.

### F-03 — P1: Package upgrade stops the tunnel without restoring it

**Location:** `os-dslite/tools/build-pkg.sh:66-84`

**Behavior:**

FreeBSD package upgrade removes the installed package and runs its deinstallation scripts before installing the replacement. The old `pre-deinstall` stops DS-Lite. The new `post-install` restarts `configd` and clears caches but never reconfigures or starts an enabled tunnel.

**Impact:**

- `pkg upgrade` or forced package replacement can leave IPv4 connectivity down.
- Recovery requires a reboot or manual Apply/reconfigure action.
- The README's “clean upgrade” claim is not satisfied.

**Required correction:**

- Use upgrade-aware package scripts.
- Do not perform destructive final-uninstall cleanup during upgrade.
- After installation/upgrade, reconfigure only when the plugin is enabled.
- Preserve and restore prior enabled/running state.

**Acceptance criteria:**

- Upgrading an enabled installation restores the tunnel and route without manual action.
- Upgrading a disabled installation does not create or start a tunnel.
- Upgrade does not remove unrelated networking.

### F-04 — P1: FreeBSD ping timeout is 2 milliseconds, not 2 seconds

**Locations:**

- `status.sh:115-144`
- `diagnostics.sh:95-149`

**Behavior:**

Ten health probes use `ping -W 2`. FreeBSD `ping(8)` defines `-W` in milliseconds, so these checks wait only 2 ms for a response.

**Impact:**

- Internet, IPv6, AFTR/BR, DF-MTU, and fragmentation checks will commonly fail on healthy connections.
- The composite health state will report false degradation.
- The dashboard and diagnostics page become operationally misleading.

**Required correction:**

Use a realistic FreeBSD timeout, for example `-W 2000`, or define a shared timeout value in milliseconds.

The status endpoint is polled every five seconds by `general.volt`; after fixing the timeout, active probes should be moved out of that hot path or cached to avoid overlapping multi-second status requests.

**Acceptance criteria:**

- A known healthy tunnel reports healthy at ordinary WAN latency.
- Probe timeouts are expressed and documented in milliseconds.
- A failed probe remains bounded without causing overlapping status jobs.

### F-05 — P1: Periodic Fixed-IP update is still not scheduled

**Locations:**

- `configure.sh:258-284`
- `status.sh:83-99`
- `REVIEW.md:44-48`

**Behavior:**

`configure.sh` writes `prefix_update.sh` but registers no cron entry, OPNsense cron plugin callback, or other periodic execution mechanism. Status reads the stored update result but ignores its timestamp.

**Impact:**

- Provider-side prefix registration can lapse after the initial update.
- A single old `good` or `nochg` result can remain healthy indefinitely.
- Opening diagnostics may mask the missing scheduler by performing a live update and overwriting state.

**Required correction:**

- Package the helper statically rather than generating it at runtime.
- Register it through OPNsense's cron/configd integration.
- Remove or disable the job when Fixed-IP mode or the plugin is disabled.
- Parse and validate the stored timestamp against the intended update interval.
- Treat missing, malformed, or stale state as degraded.

**Acceptance criteria:**

- The job appears in the generated OPNsense cron configuration.
- It runs at the intended interval after reboot and package upgrade.
- Health becomes stale after the defined maximum age.

### F-06 — P1: Explicitly degraded health can render green

**Locations:**

- `os-dslite/src/opnsense/www/js/widgets/DSLite.js:71`
- `os-dslite/src/opnsense/mvc/app/views/OPNsense/DSLite/general.volt:137-142`

**Behavior:**

The widget's green branch is:

```js
t.health === 'healthy' || (t.status === 'up' && t.connectivity === 'connected')
```

A response with `health="degraded"`, `status="up"`, and `connectivity="connected"` therefore renders green. The general settings page ignores `health` and similarly treats connected IPv4 as fully healthy.

**Impact:**

Route, DNS, MTU, WAN alias, prefix-update, or IPv6 failures can be hidden behind a green Connected state.

**Observed evidence:**

The exact degraded input above evaluated into the current green branch during review.

**Required correction:**

- Use the legacy status/connectivity fallback only when the `health` property is absent.
- Make both the widget and general page prioritize explicit `healthy`, `degraded`, and `offline` states.
- Display failed-check identifiers when degraded.

**Acceptance criteria:**

- `health="degraded"` never renders green.
- Legacy responses without `health` still render compatibly.

### F-07 — P1: WAN alias installation failure is recorded as success

**Locations:**

- `lib.sh:323-348`
- `configure.sh:92-94`

**Behavior:**

`manage_wan_alias()` logs failure when `ifconfig ... alias` fails, but then writes the requested address to `/var/run/dslite_local_tunnel_v6` and returns success. `configure.sh` ignores the helper's return value and proceeds to replace the tunnel.

**Impact:**

- The old working tunnel can be destroyed.
- The replacement tunnel uses a source IPv6 address that is not assigned.
- State falsely claims ownership of a nonexistent alias.
- Later teardown cannot reliably recover the original condition.

**Observed evidence:**

A mocked failed alias addition produced:

```text
rc=0
state=2001:db8::1
```

**Required correction:**

- Return non-zero when the alias cannot be added and verified.
- Write state only after successful verification.
- Abort configuration before prefix update, tunnel replacement, or route changes.
- Preserve cleanup state if alias removal fails.

**Acceptance criteria:**

- Failed alias addition leaves the existing tunnel and state intact.
- Successful return guarantees the address is present on the expected device.

### F-08 — P1: Diagnostics JSON is not escaped

**Location:** `diagnostics.sh:190-230`

**Behavior:**

The old diagnostics implementation escaped command output before interpolation. The rewrite directly inserts dynamic shell values into a JSON `printf`. The prefix-update response token is controlled by an external server and can contain quotes, backslashes, or control characters.

**Impact:**

- Valid provider error responses can make the API return invalid JSON.
- `ServiceController::diagnosticsAction()` falls back to an error response after `json_decode()` fails.
- The diagnostics page reports no usable backend response.

**Observed evidence:**

Injecting a provider token containing `"` produced JSON rejected by a standard JSON parser.

**Required correction:**

Generate JSON with a real JSON encoder. If shell output remains, pass values to a supported encoder rather than maintaining a partial escaping function.

**Acceptance criteria:**

- Quotes, backslashes, newlines, tabs, and non-ASCII data remain valid JSON.
- Error responses from the provider remain displayable.

### F-09 — P1: Diagnostics page load performs a state-changing provider update

**Locations:**

- `diagnostics.volt:72-73`
- `diagnostics.sh:190-212`

**Behavior:**

The page invokes diagnostics immediately on document ready. In Fixed-IP mode, diagnostics performs an authenticated request to the configured prefix-update endpoint and rewrites the persisted update result.

**Impact:**

- Merely opening or refreshing a diagnostics page changes provider state.
- Repeated refreshes can trigger rate limits.
- A read operation conceals the missing periodic scheduler.
- The automatic call expands exposure to the insecure curl transport in F-02.

**Required correction:**

- Make diagnostics read-only by reporting persisted last-update state.
- Put a live provider update behind an explicit POST action with clear UI wording.
- Keep the action separate from page initialization and ordinary refresh.

**Acceptance criteria:**

- Opening or refreshing diagnostics sends no authenticated update.
- Only an explicit user action performs a live update.

### F-10 — P1: `vpn:2` truncates the family discriminator

**Location:** `os-dslite/src/etc/inc/plugins.inc.d/dslite.inc:28-56`

**Behavior:**

`newwanip` registers `dslite_configure_do:3`, but `vpn` retains `dslite_configure_do:2`. OPNsense's dispatcher slices the argument list according to that suffix. Current `rc.newwanip` and `rc.newwanipv6` call both `vpn` and `newwanip`, passing the family as the third callback argument.

For the `vpn` callback, `$family` is therefore always `null` and passes the filter:

- IPv4 renewal rebuilds through `vpn`, even though `newwanip` correctly rejects `inet`.
- IPv6 renewal invokes the callback through both hooks and relies on the timestamp debounce to suppress one run.

The callback also does not verify that the changed interface list contains the configured WAN, so unrelated IPv6 interface changes can trigger a destructive reconfigure.

**Required correction:**

- Use a distinct boot callback for `vpn` that runs only for a true boot invocation and rejects renewal calls with a family.
- Keep the renewal callback on `newwanip:3`.
- Check that the configured WAN is present in the supplied interface set.
- Account for older supported OPNsense versions that did not pass the family argument during renewal.

**Acceptance criteria:**

- IPv4 renewal causes no DS-Lite reconfigure.
- One IPv6 WAN renewal causes exactly one reconfigure.
- An unrelated interface renewal does not reconfigure the tunnel.
- Boot still starts an enabled tunnel.

### F-11 — P1: Alias cleanup is incomplete across mode and WAN changes

**Locations:**

- `configure.sh:111-159`
- `lib.sh:311-362`

**Behavior:**

The alias state records only an IPv6 address, not the device that owns it. Switching from Fixed-IP to DS-Lite with a native WAN IPv6 bypasses alias cleanup. Changing the configured WAN makes cleanup search the new device rather than the old one.

`remove_wan_alias()` deletes the state file even when removal fails, losing the only cleanup handle.

**Impact:**

- Old `/128` aliases can remain permanently on a previous WAN device.
- A stale managed alias may be selected as the first global DS-Lite source.
- Teardown may report completion after losing track of the still-present alias.

**Required correction:**

- Store both device and address in managed state.
- Remove managed alias state before changing mode or WAN device.
- Clear state only after successful removal or confirmed absence.
- Exclude plugin-managed aliases when selecting a native WAN source.

**Acceptance criteria:**

- Fixed-IP → DS-Lite and WAN-device changes remove the old alias.
- Failed removal preserves enough state for retry.

### F-12 — P2: Debounce can suppress the real action

**Location:** `configure.sh:12-31`

**Behavior:**

The three-second timestamp check executes before restart handling, enabled-state handling, parameter validation, and tunnel work. Any invocation writes the stamp before success is known. A failed, irrelevant, or duplicate invocation can therefore make an explicit restart or real WAN-renewal action return success without doing work.

The wall-clock comparison is not serialization: concurrent processes can both pass before either writes. A backward clock adjustment can also leave a future timestamp that suppresses configuration longer than three seconds.

**Required correction:**

Use an ownership-safe lock for serialization and coalesce only equivalent asynchronous renewal work. Explicit start/restart/stop operations and retries after failure must not be silently dropped.

### F-13 — P2: Status endpoint performs active diagnostic workload on a five-second poll

**Locations:**

- `status.sh:102-148`
- `general.volt:174-175`
- `DSLite.js:45-49`

**Behavior:**

The normal status endpoint now performs AFTR, IPv4, IPv6, DF-MTU, and fragmentation probes. The general page polls it every five seconds; the dashboard widget also invokes it on widget ticks.

Correcting F-04 to a realistic timeout can make failed status requests take several seconds and overlap with subsequent polls. IPv4 Internet checking is also gated on the AFTR/BR answering ICMPv6, so an endpoint that filters echo can cause a false “no internet” state despite working tunneled IPv4.

**Required correction:**

- Keep the frequently-polled status path lightweight.
- Cache active health results or run them on a slower controlled schedule.
- Keep full active probing in the diagnostics action.
- Evaluate CE-to-BR and IPv4 Internet independently.

### F-14 — P2: Package leaves generated files behind

**Locations:**

- `configure.sh:258-284`
- `build-pkg.sh:45-49,76-84`

**Behavior:**

`prefix_update.sh` is generated at runtime after the package plist is created. Package deletion therefore does not own or remove it. `/var/run/dslite_prefix_update_status` is also not cleaned.

**Impact:**

- Package uninstall can leave plugin directories and files behind.
- README's “proper uninstall” claim is inaccurate.

**Required correction:**

Package the helper statically, and remove runtime state on final uninstall and when leaving Fixed-IP mode.

### F-15 — P2: Package includes an empty accidental artifact

**Location:** `os-dslite/src/opnsense/scripts/OPNsense/dslite/err.txt`

The staged zero-byte `err.txt` has no references. The generated plist includes it under `/usr/local/opnsense/scripts/OPNsense/dslite`. Remove it.

### F-16 — P2: Default package metadata is not production metadata

**Location:** `os-dslite/Makefile:4`

The default maintainer is `you@example.invalid`. Set the real maintainer or make `PKG_MAINTAINER` mandatory for release builds.

### F-17 — P2: Functional changes are mixed with whole-file line-ending churn

**Location:** `dslite.md`

All 1,577 lines are staged as line-ending-only changes. `git diff --ignore-space-at-eol -- dslite.md` produced no semantic diff. Revert it from the functional merge or normalize it in a separate commit.

## 5. Prior review reconciliation

| Review item | Current status | Evidence / remaining work |
|---|---|---|
| H1 — IPv6-only WAN renewal | Original functional gap resolved, integration still partial | `newwanip:3` receives `inet6`; `vpn:2` still bypasses filtering and duplicates work. |
| H2 — periodic Fixed-IP update | Unresolved | Helper exists, but no scheduler registration exists. |
| M1 — TLS verification | Unresolved and expanded | Immediate, generated, and diagnostics curl paths use `-k`; HTTP remains accepted. |
| M2 — masking / process arguments | Mostly resolved | Form uses `type=password`; netrc removes credentials from argv. Generic API serialization was not changed. |
| M3 — dead `mss_clamp` | Unresolved | `MSS_CLAMP` is read but never applied; `mss_ifmtu` derives from MTU instead. |
| L1 — hardcoded `gif0` | Unresolved | Collision and ownership risk now affects package install/uninstall. |
| L2 — `/30` rounded to `/28` | Unresolved | Prefix comparison still uses integer `prefixlen / 4`. |
| L3 — fragile no-Python IPv6 fallback | Unresolved | The manual parser remains and mishandles common compressed forms. |
| L4 — `UP`/`RUNNING` inconsistency | Unresolved | Status uses `RUNNING`; diagnostics requires both; dead helper checks only `UP`. |
| L5 — `/128` teardown | Partially resolved | Same-device happy-path cleanup exists; failures, mode changes, and WAN changes remain unsafe. |

## 6. Review-document corrections

### `REVIEW.md`

- Lines 19-42 should mark the original H1 gap resolved.
- The recommendation to register a separate `newwanipv6` hook is incorrect for current OPNsense. IPv6 renewal uses `newwanip` with an `inet6` family argument.
- Lines 65-70 should mark form masking and command-line credential exposure resolved.
- Lines 95-96 should mark L5 partially resolved rather than open or fully resolved.
- H2, M1, M3, and L1-L4 remain open.

### `FORK-REVIEW.md`

- Line 18's “clean upgrade/uninstall” conclusion is not supported by the fork-derived package hooks.
- Lines 60-63 should not describe insecure transport as largely moot because the endpoint is HTTP. HTTP makes credential interception unconditional.
- Lines 81-85 treat one cross-machine benchmark as proof of CPU scaling and as a prediction for different hardware. Label the result anecdotal, cite the raw methodology, and remove the causal conclusion.

### `README.md`

- Lines 15 and 67-80 should not claim clean package upgrade/uninstall until F-01, F-03, and F-14 are fixed.
- Lines 185-190 should not claim the 1.89 Gbps test was definitively NIC-limited or that another mode on different hardware proves DS-Lite scaling.
- The health section should explain probe cadence, timeout semantics, and whether state is live or cached once the implementation is corrected.

## 7. Verification performed

### Syntax and parsing

- `sh -n` passed for:
  - `tools/build-pkg.sh`
  - `configure.sh`
  - `diagnostics.sh`
  - `lib.sh`
  - `status.sh`
  - `teardown.sh`
- `node --check` passed for `DSLite.js`.
- Changed widget metadata, settings form, and model XML parsed successfully.

### Targeted behavioral checks

The review used isolated command mocks and data inputs rather than modifying appliance networking:

| Check | Observed result |
|---|---|
| Teardown with no GIF tunnel | Still called `route delete default`. |
| Failed `ifconfig ... alias` | `manage_wan_alias` returned `0` and wrote the requested state. |
| Widget input: degraded + up + connected | Entered the green Connected branch. |
| Provider token containing a quote | Produced invalid diagnostics JSON. |
| Package staging with a stub `pkg` binary | Completed staging, included empty `err.txt`, included pre-deinstall stop, and contained no post-install reconfigure. |
| Ping timeout scan | Found five `-W 2` probes in status and five in diagnostics. |

### Environment limitations

- Review host was Linux, not OPNsense/FreeBSD.
- A real FreeBSD package was not created or installed.
- Appliance routing, GIF behavior, configd scheduling, upgrade, and browser UI should be exercised on an isolated OPNsense test instance after corrections.
- PHP CLI was unavailable locally, so `dslite.inc` was checked structurally and against the upstream dispatcher contract rather than with `php -l`.

## 8. Upstream contracts checked

- [OPNsense `rc.newwanip`](https://github.com/opnsense/core/blob/master/src/etc/rc.newwanip)
- [OPNsense `rc.newwanipv6`](https://github.com/opnsense/core/blob/master/src/etc/rc.newwanipv6)
- [OPNsense plugin dispatcher](https://github.com/opnsense/core/blob/master/src/etc/inc/plugins.inc)
- [OPNsense 24.1 `rc.newwanipv6`](https://github.com/opnsense/core/blob/24.1/src/etc/rc.newwanipv6)
- [FreeBSD `ping(8)`](https://man.freebsd.org/cgi/man.cgi?query=ping&sektion=8&manpath=FreeBSD+14.2-RELEASE)
- [FreeBSD `pkg-upgrade(8)`](https://man.freebsd.org/cgi/man.cgi?query=pkg-upgrade&sektion=8)
- [Downstream OCN Fixed-IP fork](https://github.com/unchained-llc/os-ocnfixedip)

## 9. Recommended remediation order

1. Make teardown and package lifecycle ownership-safe.
2. Require verified HTTPS for authenticated updates.
3. Separate package upgrade from final uninstall and restore enabled service state.
4. Correct FreeBSD probe timeouts and remove active probes from the five-second status path.
5. Register the periodic prefix-update job and enforce result freshness.
6. Make alias installation/removal transactional and persist device ownership.
7. Correct widget/general-page health precedence.
8. Make diagnostics read-only by default and encode JSON safely.
9. Split boot and renewal callbacks so the family/interface filters are effective.
10. Remove generated/untracked package files, accidental artifacts, and line-ending churn.
11. Update `REVIEW.md`, `FORK-REVIEW.md`, and `README.md` only after behavior matches their claims.

## 10. Merge recommendation

Do not publish or merge the current package and observability changes as production-ready. The imported concepts are useful, but the package lifecycle, credential transport, health timeout, scheduler, alias transaction, and UI-state defects are release blockers.

After the P0 and P1 items are corrected, validate the complete story on an isolated OPNsense appliance:

1. Fresh package install while disabled.
2. Enable and configure DS-Lite.
3. IPv6 prefix renewal.
4. Fixed-IP registration and scheduled refresh.
5. Fixed-IP to DS-Lite mode transition.
6. WAN-interface change.
7. Package upgrade while enabled and while disabled.
8. Package uninstall with an unrelated default route and unrelated GIF interface present.
9. Dashboard and diagnostics behavior under healthy, degraded, offline, high-latency, and provider-error conditions.
10. Tunnel-interface collision: create an unrelated GIF on the configured unit, apply, and confirm the plugin refuses rather than taking it over; then point it at a free unit and confirm it comes up.

### MAP-E validation

MAP-E was added after this review. Its arithmetic is verified against RFC 7597's
worked example and the published v6plus parameters, but three things cannot be
checked off-appliance.

11. **`map-e-portset` availability.** The one item that gates everything else, because pf is what actually confines the source ports.

    ```sh
    printf 'nat on lo0 from any to any -> 192.0.2.1 map-e-portset 6/8/0\n' | pfctl -n -f -
    echo "rc=$?"   # 0 = supported
    ```

    Non-zero means this base lacks the RFC 7597 NAT port selection from FreeBSD
    D29468. `configure.sh` runs exactly this probe and refuses to build a tunnel
    when it fails, so the expected behavior on an unsupported base is a clean
    refusal in the log, not a half-working tunnel. Confirm which it is, and
    record the OPNsense/FreeBSD version alongside the result.

12. **Derived values against the line.** Compare what the plugin computes with what the ISP actually assigned:

    ```sh
    configctl dslite status          # ipv4 and the MAP-E line in the log
    grep 'MAP-E mode' /var/log/dslite/latest.log
    ```

    The derived IPv4 must equal the address the ISP assigned. A mismatch means
    the configured mapping rule is wrong for this prefix — not a bug in the
    derivation, which refuses outright when the prefix falls outside the rule.

13. **Port set actually enforced.** The failure this guards against is silent: traffic leaves, the BR drops it, and it looks like a routing fault.

    ```sh
    pfctl -a dslite/nat -s nat       # rule should carry map-e-portset a/k/psid
    pfctl -s state | grep <derived-ipv4>
    ```

    Every translated source port must fall inside the derived set. With the
    v6plus example (offset 4, PSID length 8) that is 15 ranges of 16 ports, none
    below 1024. A port outside the set is the defect to look for.

14. **MAP-E to DS-Lite mode transition**, confirming the managed CE `/128` alias and the `map-e-portset` nat rule are both withdrawn.
