#!/bin/sh

# OPNsense DS-Lite Plugin Uninstaller

set -e

echo "=== OPNsense DS-Lite Plugin Uninstaller ==="
echo ""

# Stop tunnel if running
echo "Stopping DS-Lite tunnel..."
configctl dslite stop 2>/dev/null || true

# Remove files
echo "Removing plugin files..."
rm -rf /usr/local/opnsense/mvc/app/models/OPNsense/DSLite
rm -rf /usr/local/opnsense/mvc/app/controllers/OPNsense/DSLite
rm -rf /usr/local/opnsense/mvc/app/views/OPNsense/DSLite
rm -rf /usr/local/opnsense/scripts/OPNsense/dslite
rm -f /usr/local/opnsense/service/conf/actions.d/actions_dslite.conf
rm -f /usr/local/etc/inc/plugins.inc.d/dslite.inc
rm -f /usr/local/opnsense/www/js/widgets/DSLite.js
rm -f /usr/local/opnsense/www/js/widgets/Metadata/DSLite.xml

# Cleanup tunnel
ifconfig gif0 destroy 2>/dev/null || true
route delete default 2>/dev/null || true
pfctl -a "dslite/nat" -F all 2>/dev/null || true
pfctl -a "dslite/fw" -F all 2>/dev/null || true
pfctl -a "dslite" -F all 2>/dev/null || true

# Restart configd
echo "Restarting configd..."
service configd restart

# Flush caches
rm -rf /tmp/opnsense_*cache* 2>/dev/null
rm -f /tmp/dslite_*.conf 2>/dev/null

echo ""
echo "=== Uninstall complete ==="
echo "Log out and back into the web UI for menu changes to take effect."
echo "Note: DS-Lite config in /conf/config.xml was not removed."
echo ""
