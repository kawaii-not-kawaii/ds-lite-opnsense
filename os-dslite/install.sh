#!/bin/sh

# OPNsense DS-Lite Plugin Installer
# Works over IPv6-only connections (for pre-tunnel install)
# Run this directly on the OPNsense box:
#   curl -6 -skL -o /tmp/install-dslite.sh "https://raw.githubusercontent.com/kawaii-not-kawaii/ds-lite-opnsense/main/os-dslite/install.sh" && sh /tmp/install-dslite.sh

set -e

# Files are fetched individually from raw.githubusercontent.com rather than as a
# tarball from github.com, because github.com and codeload.github.com are
# IPv4-only -- they publish no AAAA record. raw.githubusercontent.com is behind
# Fastly and does have real IPv6. Since the whole point of this installer is to
# run on a box whose IPv4 does not exist until the tunnel it installs is up,
# pulling the tarball would fail exactly when it is needed most.
BRANCH="${DSLITE_BRANCH:-main}"
BASE_URL="https://raw.githubusercontent.com/kawaii-not-kawaii/ds-lite-opnsense/${BRANCH}/os-dslite/src"
TMP_DIR="/tmp/dslite-install"

# Source paths, relative to os-dslite/src. The install destination is always
# /usr/local/<same relative path>, so one list drives both.
FILES="
etc/inc/plugins.inc.d/dslite.inc
opnsense/mvc/app/controllers/OPNsense/DSLite/GeneralController.php
opnsense/mvc/app/controllers/OPNsense/DSLite/DiagnosticsController.php
opnsense/mvc/app/controllers/OPNsense/DSLite/Api/SettingsController.php
opnsense/mvc/app/controllers/OPNsense/DSLite/Api/ServiceController.php
opnsense/mvc/app/controllers/OPNsense/DSLite/forms/general.xml
opnsense/mvc/app/models/OPNsense/DSLite/DSLite.xml
opnsense/mvc/app/models/OPNsense/DSLite/DSLite.php
opnsense/mvc/app/models/OPNsense/DSLite/ACL/ACL.xml
opnsense/mvc/app/models/OPNsense/DSLite/Menu/Menu.xml
opnsense/mvc/app/views/OPNsense/DSLite/general.volt
opnsense/mvc/app/views/OPNsense/DSLite/diagnostics.volt
opnsense/scripts/OPNsense/dslite/lib.sh
opnsense/scripts/OPNsense/dslite/configure.sh
opnsense/scripts/OPNsense/dslite/teardown.sh
opnsense/scripts/OPNsense/dslite/status.sh
opnsense/scripts/OPNsense/dslite/diagnostics.sh
opnsense/scripts/OPNsense/dslite/prefix_update.sh
opnsense/scripts/OPNsense/dslite/mape_calc.sh
opnsense/service/conf/actions.d/actions_dslite.conf
opnsense/www/js/widgets/DSLite.js
opnsense/www/js/widgets/Metadata/DSLite.xml
"

echo "=== OPNsense DS-Lite Plugin Installer ==="
echo "branch: ${BRANCH}"
echo ""

# Check we're on OPNsense
if [ ! -f /usr/local/etc/inc/plugins.inc.d/pf.inc ]; then
    echo "ERROR: This script must be run on an OPNsense system."
    exit 1
fi

if command -v curl >/dev/null 2>&1; then
    DL="curl"
elif command -v fetch >/dev/null 2>&1; then
    DL="fetch"
else
    echo "ERROR: No download tool available (curl or fetch required)"
    exit 1
fi

# Fetch one file. Prefers IPv6 but does not force it: forcing -6 breaks the
# install on a dual-stack box whose resolver hands back an IPv4-only CDN node,
# and the earlier version failed silently when that happened.
fetch_one() {
    _src="$1"
    _dst="$2"

    if [ "${DL}" = "curl" ]; then
        curl -6 -sfL --connect-timeout 10 -o "${_dst}" "${_src}" 2>/dev/null && return 0
        curl -sfL --connect-timeout 10 -o "${_dst}" "${_src}" 2>/dev/null && return 0
    else
        fetch -q --no-verify-hostname --no-verify-peer -o "${_dst}" "${_src}" && return 0
    fi
    return 1
}

echo "Downloading plugin (${BRANCH})..."
rm -rf "${TMP_DIR}"
mkdir -p "${TMP_DIR}"

count=0
for rel in ${FILES}; do
    mkdir -p "${TMP_DIR}/$(dirname "${rel}")"
    if ! fetch_one "${BASE_URL}/${rel}" "${TMP_DIR}/${rel}"; then
        echo ""
        echo "ERROR: failed to download ${rel}"
        echo "       from ${BASE_URL}/${rel}"
        echo ""
        echo "Check connectivity to raw.githubusercontent.com. Note that"
        echo "github.com itself is IPv4-only, so on an IPv6-only box only the"
        echo "raw.githubusercontent.com host is reachable."
        exit 1
    fi
    # A 404 from raw returns the string "404: Not Found" with a success status
    # under some curl versions; catch that rather than installing a stub file.
    if [ ! -s "${TMP_DIR}/${rel}" ]; then
        echo "ERROR: ${rel} downloaded empty -- aborting"
        exit 1
    fi
    count=$((count + 1))
    printf '\r  %d/%d files' "${count}" "$(echo "${FILES}" | wc -w | tr -d ' ')"
done
echo ""

echo "Installing plugin files..."
for rel in ${FILES}; do
    dst="/usr/local/${rel}"
    mkdir -p "$(dirname "${dst}")"
    cp "${TMP_DIR}/${rel}" "${dst}"
done

chmod +x /usr/local/opnsense/scripts/OPNsense/dslite/*.sh

# Restart configd
echo "Restarting configd..."
service configd restart

# Flush caches
rm -rf /tmp/opnsense_*cache* 2>/dev/null

# Re-register cron. Copying files does not rebuild the crontab -- only a package
# install runs the post-install hook that reads dslite_cron(). Without this the
# */30 prefix-update job never runs, and on a Fixed IP service that means the CE
# registration goes stale the next time the delegated prefix changes, silently.
echo "Re-registering cron jobs..."
configctl cron restart >/dev/null 2>&1 || true

# Cleanup
rm -rf "${TMP_DIR}"

echo ""
echo "=== Installation complete! ==="
echo ""
echo "Next steps:"
echo "  1. Log out and back into the OPNsense web UI (the menu entry"
echo "     will not appear until you do)"
echo "  2. Go to Interfaces > DS-Lite > Settings"
echo "  3. Enable, pick your mode and WAN interface, click Save"
echo ""
echo "Prerequisites (Interfaces > [WAN]):"
echo "  - IPv4 Configuration Type: None"
echo "  - IPv6 Configuration Type: DHCPv6"
echo "  - Prefix delegation size: 56 (or whatever your ISP delegates)"
echo ""
echo "Fixed IP mode also needs, from your provisioning mail:"
echo "  - Interface ID, BR/AFTR address, and the fixed IPv4"
echo "  - the update URL plus its user/password, so the CE address"
echo "    re-registers automatically when your prefix changes"
echo ""
echo "After the tunnel is up, add a gateway on the DS-Lite interface"
echo "or nothing will monitor it and WAN failover will never trigger."
echo "See the README section 'Gateway and failover'."
echo ""
