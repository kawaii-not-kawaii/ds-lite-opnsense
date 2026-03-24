#!/bin/sh

# Deploy DS-Lite plugin to OPNsense
# Usage: ./deploy.sh [opnsense_host]

OPNSENSE_HOST="${1:-192.168.0.2}"
OPNSENSE_USER="root"
PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="${PLUGIN_DIR}/src"

echo "Deploying DS-Lite plugin to ${OPNSENSE_HOST}..."

# Copy MVC files (model, controller, views)
echo "  -> MVC components..."
ssh "${OPNSENSE_USER}@${OPNSENSE_HOST}" "mkdir -p \
    /usr/local/opnsense/mvc/app/models/OPNsense/DSLite/ACL \
    /usr/local/opnsense/mvc/app/models/OPNsense/DSLite/Menu \
    /usr/local/opnsense/mvc/app/controllers/OPNsense/DSLite/Api \
    /usr/local/opnsense/mvc/app/controllers/OPNsense/DSLite/forms \
    /usr/local/opnsense/mvc/app/views/OPNsense/DSLite \
    /usr/local/opnsense/scripts/OPNsense/dslite"

# Models
scp -q "${SRC_DIR}/opnsense/mvc/app/models/OPNsense/DSLite/DSLite.xml" \
    "${OPNSENSE_USER}@${OPNSENSE_HOST}:/usr/local/opnsense/mvc/app/models/OPNsense/DSLite/"
scp -q "${SRC_DIR}/opnsense/mvc/app/models/OPNsense/DSLite/DSLite.php" \
    "${OPNSENSE_USER}@${OPNSENSE_HOST}:/usr/local/opnsense/mvc/app/models/OPNsense/DSLite/"
scp -q "${SRC_DIR}/opnsense/mvc/app/models/OPNsense/DSLite/ACL/ACL.xml" \
    "${OPNSENSE_USER}@${OPNSENSE_HOST}:/usr/local/opnsense/mvc/app/models/OPNsense/DSLite/ACL/"
scp -q "${SRC_DIR}/opnsense/mvc/app/models/OPNsense/DSLite/Menu/Menu.xml" \
    "${OPNSENSE_USER}@${OPNSENSE_HOST}:/usr/local/opnsense/mvc/app/models/OPNsense/DSLite/Menu/"

# Controllers
scp -q "${SRC_DIR}/opnsense/mvc/app/controllers/OPNsense/DSLite/GeneralController.php" \
    "${OPNSENSE_USER}@${OPNSENSE_HOST}:/usr/local/opnsense/mvc/app/controllers/OPNsense/DSLite/"
scp -q "${SRC_DIR}/opnsense/mvc/app/controllers/OPNsense/DSLite/DiagnosticsController.php" \
    "${OPNSENSE_USER}@${OPNSENSE_HOST}:/usr/local/opnsense/mvc/app/controllers/OPNsense/DSLite/"
scp -q "${SRC_DIR}/opnsense/mvc/app/controllers/OPNsense/DSLite/Api/SettingsController.php" \
    "${OPNSENSE_USER}@${OPNSENSE_HOST}:/usr/local/opnsense/mvc/app/controllers/OPNsense/DSLite/Api/"
scp -q "${SRC_DIR}/opnsense/mvc/app/controllers/OPNsense/DSLite/Api/ServiceController.php" \
    "${OPNSENSE_USER}@${OPNSENSE_HOST}:/usr/local/opnsense/mvc/app/controllers/OPNsense/DSLite/Api/"
scp -q "${SRC_DIR}/opnsense/mvc/app/controllers/OPNsense/DSLite/forms/general.xml" \
    "${OPNSENSE_USER}@${OPNSENSE_HOST}:/usr/local/opnsense/mvc/app/controllers/OPNsense/DSLite/forms/"

# Views
scp -q "${SRC_DIR}/opnsense/mvc/app/views/OPNsense/DSLite/general.volt" \
    "${OPNSENSE_USER}@${OPNSENSE_HOST}:/usr/local/opnsense/mvc/app/views/OPNsense/DSLite/"
scp -q "${SRC_DIR}/opnsense/mvc/app/views/OPNsense/DSLite/diagnostics.volt" \
    "${OPNSENSE_USER}@${OPNSENSE_HOST}:/usr/local/opnsense/mvc/app/views/OPNsense/DSLite/"

# Dashboard widget
echo "  -> Dashboard widget..."
scp -q "${SRC_DIR}/opnsense/www/js/widgets/DSLite.js" \
    "${OPNSENSE_USER}@${OPNSENSE_HOST}:/usr/local/opnsense/www/js/widgets/"
ssh "${OPNSENSE_USER}@${OPNSENSE_HOST}" "mkdir -p /usr/local/opnsense/www/js/widgets/Metadata"
scp -q "${SRC_DIR}/opnsense/www/js/widgets/Metadata/DSLite.xml" \
    "${OPNSENSE_USER}@${OPNSENSE_HOST}:/usr/local/opnsense/www/js/widgets/Metadata/"

# Backend scripts
echo "  -> Backend scripts..."
scp -q "${SRC_DIR}/opnsense/scripts/OPNsense/dslite/"*.sh \
    "${OPNSENSE_USER}@${OPNSENSE_HOST}:/usr/local/opnsense/scripts/OPNsense/dslite/"
ssh "${OPNSENSE_USER}@${OPNSENSE_HOST}" "chmod +x /usr/local/opnsense/scripts/OPNsense/dslite/*.sh"

# Configd actions
echo "  -> Configd actions..."
scp -q "${SRC_DIR}/opnsense/service/conf/actions.d/actions_dslite.conf" \
    "${OPNSENSE_USER}@${OPNSENSE_HOST}:/usr/local/opnsense/service/conf/actions.d/"

# Plugin registration
echo "  -> Plugin registration..."
scp -q "${SRC_DIR}/etc/inc/plugins.inc.d/dslite.inc" \
    "${OPNSENSE_USER}@${OPNSENSE_HOST}:/usr/local/etc/inc/plugins.inc.d/"

# Restart configd to pick up new actions
echo "  -> Restarting configd..."
ssh "${OPNSENSE_USER}@${OPNSENSE_HOST}" "service configd restart"

# Flush UI cache
echo "  -> Flushing UI caches..."
ssh "${OPNSENSE_USER}@${OPNSENSE_HOST}" "rm -rf /tmp/opnsense_*cache* 2>/dev/null; \
    configctl template reload OPNsense/DSLite 2>/dev/null; true"

echo ""
echo "Deploy complete! Access the plugin at:"
echo "  https://${OPNSENSE_HOST}/ui/dslite/general"
echo ""
echo "You may need to log out and back in for the menu to appear."
