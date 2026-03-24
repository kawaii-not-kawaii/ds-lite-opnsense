#!/bin/sh

# OPNsense DS-Lite Plugin Installer
# Works over IPv6-only connections (for pre-tunnel install)
# Run this directly on the OPNsense box:
#   fetch --no-verify-hostname --no-verify-peer -o /tmp/install-dslite.sh "https://raw.githubusercontent.com/kawaii-not-kawaii/ds-lite-opnsense/main/os-dslite/install.sh" && sh /tmp/install-dslite.sh

set -e

PLUGIN_URL="https://github.com/kawaii-not-kawaii/ds-lite-opnsense/archive/refs/heads/main.tar.gz"
TMP_DIR="/tmp/dslite-install"

echo "=== OPNsense DS-Lite Plugin Installer ==="
echo ""

# Check we're on OPNsense
if [ ! -f /usr/local/etc/inc/plugins.inc.d/pf.inc ]; then
    echo "ERROR: This script must be run on an OPNsense system."
    exit 1
fi

echo "Downloading plugin..."
rm -rf "${TMP_DIR}"
mkdir -p "${TMP_DIR}"

# Prefer curl -6 (forces IPv6, works before DS-Lite tunnel is up)
# Fall back to fetch if curl unavailable
if command -v curl >/dev/null 2>&1; then
    curl -6 -skL -o "${TMP_DIR}/plugin.tar.gz" "${PLUGIN_URL}"
elif command -v fetch >/dev/null 2>&1; then
    fetch --no-verify-hostname --no-verify-peer -o "${TMP_DIR}/plugin.tar.gz" "${PLUGIN_URL}"
else
    echo "ERROR: No download tool available (curl or fetch required)"
    exit 1
fi

echo "Extracting..."
tar -xzf "${TMP_DIR}/plugin.tar.gz" -C "${TMP_DIR}" --strip-components=3

echo "Installing plugin files..."
SRC="${TMP_DIR}"

# Models
mkdir -p /usr/local/opnsense/mvc/app/models/OPNsense/DSLite/ACL
mkdir -p /usr/local/opnsense/mvc/app/models/OPNsense/DSLite/Menu
cp "${SRC}/opnsense/mvc/app/models/OPNsense/DSLite/DSLite.xml" \
   /usr/local/opnsense/mvc/app/models/OPNsense/DSLite/
cp "${SRC}/opnsense/mvc/app/models/OPNsense/DSLite/DSLite.php" \
   /usr/local/opnsense/mvc/app/models/OPNsense/DSLite/
cp "${SRC}/opnsense/mvc/app/models/OPNsense/DSLite/ACL/ACL.xml" \
   /usr/local/opnsense/mvc/app/models/OPNsense/DSLite/ACL/
cp "${SRC}/opnsense/mvc/app/models/OPNsense/DSLite/Menu/Menu.xml" \
   /usr/local/opnsense/mvc/app/models/OPNsense/DSLite/Menu/

# Controllers
mkdir -p /usr/local/opnsense/mvc/app/controllers/OPNsense/DSLite/Api
mkdir -p /usr/local/opnsense/mvc/app/controllers/OPNsense/DSLite/forms
cp "${SRC}/opnsense/mvc/app/controllers/OPNsense/DSLite/GeneralController.php" \
   /usr/local/opnsense/mvc/app/controllers/OPNsense/DSLite/
cp "${SRC}/opnsense/mvc/app/controllers/OPNsense/DSLite/DiagnosticsController.php" \
   /usr/local/opnsense/mvc/app/controllers/OPNsense/DSLite/
cp "${SRC}/opnsense/mvc/app/controllers/OPNsense/DSLite/Api/SettingsController.php" \
   /usr/local/opnsense/mvc/app/controllers/OPNsense/DSLite/Api/
cp "${SRC}/opnsense/mvc/app/controllers/OPNsense/DSLite/Api/ServiceController.php" \
   /usr/local/opnsense/mvc/app/controllers/OPNsense/DSLite/Api/
cp "${SRC}/opnsense/mvc/app/controllers/OPNsense/DSLite/forms/general.xml" \
   /usr/local/opnsense/mvc/app/controllers/OPNsense/DSLite/forms/

# Views
mkdir -p /usr/local/opnsense/mvc/app/views/OPNsense/DSLite
cp "${SRC}/opnsense/mvc/app/views/OPNsense/DSLite/general.volt" \
   /usr/local/opnsense/mvc/app/views/OPNsense/DSLite/
cp "${SRC}/opnsense/mvc/app/views/OPNsense/DSLite/diagnostics.volt" \
   /usr/local/opnsense/mvc/app/views/OPNsense/DSLite/

# Dashboard widget
mkdir -p /usr/local/opnsense/www/js/widgets/Metadata
cp "${SRC}/opnsense/www/js/widgets/DSLite.js" \
   /usr/local/opnsense/www/js/widgets/
cp "${SRC}/opnsense/www/js/widgets/Metadata/DSLite.xml" \
   /usr/local/opnsense/www/js/widgets/Metadata/

# Backend scripts
mkdir -p /usr/local/opnsense/scripts/OPNsense/dslite
cp "${SRC}/opnsense/scripts/OPNsense/dslite/"*.sh \
   /usr/local/opnsense/scripts/OPNsense/dslite/
chmod +x /usr/local/opnsense/scripts/OPNsense/dslite/*.sh

# Configd actions
cp "${SRC}/opnsense/service/conf/actions.d/actions_dslite.conf" \
   /usr/local/opnsense/service/conf/actions.d/

# Plugin registration
cp "${SRC}/etc/inc/plugins.inc.d/dslite.inc" \
   /usr/local/etc/inc/plugins.inc.d/

# Restart configd
echo "Restarting configd..."
service configd restart

# Flush caches
rm -rf /tmp/opnsense_*cache* 2>/dev/null

# Cleanup
rm -rf "${TMP_DIR}"

echo ""
echo "=== Installation complete! ==="
echo ""
echo "Next steps:"
echo "  1. Log out and back into the OPNsense web UI"
echo "  2. Go to Interfaces > DS-Lite"
echo "  3. Enable DS-Lite, select your ISP profile, pick WAN interface"
echo "  4. Click Apply"
echo ""
echo "Prerequisites:"
echo "  - WAN interface set to DHCPv6 (IPv4: None)"
echo "  - LAN IPv6 set to DHCPv6 with prefix size /56"
echo ""
