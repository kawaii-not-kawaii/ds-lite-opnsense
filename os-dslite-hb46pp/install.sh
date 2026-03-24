#!/bin/sh

# OPNsense DS-Lite Plugin Installer (HB46PP branch)
# Works over IPv6-only connections using raw.githubusercontent.com
#
# Install:
#   curl -6 -skL -o /tmp/install-dslite.sh "https://raw.githubusercontent.com/kawaii-not-kawaii/ds-lite-opnsense/hb46pp/os-dslite-hb46pp/install.sh" && sh /tmp/install-dslite.sh

set -e

BRANCH="hb46pp"
BASE="https://raw.githubusercontent.com/kawaii-not-kawaii/ds-lite-opnsense/${BRANCH}/os-dslite-hb46pp/src"

echo "=== OPNsense DS-Lite Plugin Installer (HB46PP) ==="
echo ""

if [ ! -f /usr/local/etc/inc/plugins.inc.d/pf.inc ]; then
    echo "ERROR: This script must be run on an OPNsense system."
    exit 1
fi

# Download helper - tries curl -6 first, then fetch
dl() {
    local url="$1"
    local dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -6 -skL -o "${dest}" "${url}" 2>/dev/null
    elif command -v fetch >/dev/null 2>&1; then
        fetch --no-verify-hostname --no-verify-peer -o "${dest}" "${url}" 2>/dev/null
    else
        echo "ERROR: No download tool available"
        exit 1
    fi
    if [ ! -s "${dest}" ]; then
        echo "ERROR: Failed to download ${url}"
        exit 1
    fi
}

echo "Downloading plugin files..."

# Models
echo "  -> Models..."
mkdir -p /usr/local/opnsense/mvc/app/models/OPNsense/DSLite/ACL
mkdir -p /usr/local/opnsense/mvc/app/models/OPNsense/DSLite/Menu
dl "${BASE}/opnsense/mvc/app/models/OPNsense/DSLite/DSLite.xml" \
   /usr/local/opnsense/mvc/app/models/OPNsense/DSLite/DSLite.xml
dl "${BASE}/opnsense/mvc/app/models/OPNsense/DSLite/DSLite.php" \
   /usr/local/opnsense/mvc/app/models/OPNsense/DSLite/DSLite.php
dl "${BASE}/opnsense/mvc/app/models/OPNsense/DSLite/ACL/ACL.xml" \
   /usr/local/opnsense/mvc/app/models/OPNsense/DSLite/ACL/ACL.xml
dl "${BASE}/opnsense/mvc/app/models/OPNsense/DSLite/Menu/Menu.xml" \
   /usr/local/opnsense/mvc/app/models/OPNsense/DSLite/Menu/Menu.xml

# Controllers
echo "  -> Controllers..."
mkdir -p /usr/local/opnsense/mvc/app/controllers/OPNsense/DSLite/Api
mkdir -p /usr/local/opnsense/mvc/app/controllers/OPNsense/DSLite/forms
dl "${BASE}/opnsense/mvc/app/controllers/OPNsense/DSLite/GeneralController.php" \
   /usr/local/opnsense/mvc/app/controllers/OPNsense/DSLite/GeneralController.php
dl "${BASE}/opnsense/mvc/app/controllers/OPNsense/DSLite/DiagnosticsController.php" \
   /usr/local/opnsense/mvc/app/controllers/OPNsense/DSLite/DiagnosticsController.php
dl "${BASE}/opnsense/mvc/app/controllers/OPNsense/DSLite/Api/SettingsController.php" \
   /usr/local/opnsense/mvc/app/controllers/OPNsense/DSLite/Api/SettingsController.php
dl "${BASE}/opnsense/mvc/app/controllers/OPNsense/DSLite/Api/ServiceController.php" \
   /usr/local/opnsense/mvc/app/controllers/OPNsense/DSLite/Api/ServiceController.php
dl "${BASE}/opnsense/mvc/app/controllers/OPNsense/DSLite/forms/general.xml" \
   /usr/local/opnsense/mvc/app/controllers/OPNsense/DSLite/forms/general.xml

# Views
echo "  -> Views..."
mkdir -p /usr/local/opnsense/mvc/app/views/OPNsense/DSLite
dl "${BASE}/opnsense/mvc/app/views/OPNsense/DSLite/general.volt" \
   /usr/local/opnsense/mvc/app/views/OPNsense/DSLite/general.volt
dl "${BASE}/opnsense/mvc/app/views/OPNsense/DSLite/diagnostics.volt" \
   /usr/local/opnsense/mvc/app/views/OPNsense/DSLite/diagnostics.volt

# Dashboard widget
echo "  -> Widget..."
mkdir -p /usr/local/opnsense/www/js/widgets/Metadata
dl "${BASE}/opnsense/www/js/widgets/DSLite.js" \
   /usr/local/opnsense/www/js/widgets/DSLite.js
dl "${BASE}/opnsense/www/js/widgets/Metadata/DSLite.xml" \
   /usr/local/opnsense/www/js/widgets/Metadata/DSLite.xml

# Backend scripts
echo "  -> Backend scripts..."
mkdir -p /usr/local/opnsense/scripts/OPNsense/dslite
for script in lib.sh hb46pp.sh configure.sh teardown.sh status.sh diagnostics.sh; do
    dl "${BASE}/opnsense/scripts/OPNsense/dslite/${script}" \
       /usr/local/opnsense/scripts/OPNsense/dslite/${script}
done
chmod +x /usr/local/opnsense/scripts/OPNsense/dslite/*.sh

# Configd actions
echo "  -> Configd actions..."
dl "${BASE}/opnsense/service/conf/actions.d/actions_dslite.conf" \
   /usr/local/opnsense/service/conf/actions.d/actions_dslite.conf

# Plugin registration
echo "  -> Plugin registration..."
dl "${BASE}/etc/inc/plugins.inc.d/dslite.inc" \
   /usr/local/etc/inc/plugins.inc.d/dslite.inc

# Restart configd
echo "  -> Restarting configd..."
service configd restart

# Flush caches
rm -rf /tmp/opnsense_*cache* 2>/dev/null

echo ""
echo "=== Installation complete! ==="
echo ""
echo "Next steps:"
echo "  1. Log out and back into the OPNsense web UI"
echo "  2. Go to Interfaces > DS-Lite"
echo "  3. Select Fixed IP or DS-Lite mode"
echo "  4. Enter provisioning credentials (for Fixed IP)"
echo "  5. Click Apply"
echo ""
echo "Prerequisites:"
echo "  - WAN interface set to DHCPv6 (IPv4: None)"
echo "  - LAN IPv6 set to Track Interface (WAN)"
echo ""
