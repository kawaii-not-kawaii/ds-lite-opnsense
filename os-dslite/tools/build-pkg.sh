#!/bin/sh

# Build a FreeBSD pkg for the DS-Lite / Fixed IP plugin from the local source tree.
# Intended to run on OPNsense / FreeBSD.
# (packaging ported from unchained-llc/os-ocnfixedip, BSD-2-Clause)

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)
SRC_DIR="${PROJECT_ROOT}/src"

PKG_NAME="${PKG_NAME:-os-dslite}"
PKG_VERSION="${PKG_VERSION:-$(date +%Y.%m.%d.%H%M)}"
PKG_MAINTAINER="${PKG_MAINTAINER:-kawaii-not-kawaii@users.noreply.github.com}"
PKG_WWW="${PKG_WWW:-https://github.com/kawaii-not-kawaii/ds-lite-opnsense}"
PKG_ORIGIN="${PKG_ORIGIN:-net/os-dslite}"

WORK_DIR="${WORK_DIR:-${PROJECT_ROOT}/.pkgbuild}"
STAGE_DIR="${WORK_DIR}/stage"
META_DIR="${WORK_DIR}/meta"
OUT_DIR="${OUT_DIR:-${PROJECT_ROOT}/dist}"

if ! command -v pkg >/dev/null 2>&1; then
    echo "ERROR: pkg command not found. Run this on OPNsense/FreeBSD." >&2
    exit 1
fi

if [ ! -d "${SRC_DIR}/opnsense" ] || [ ! -d "${SRC_DIR}/etc" ]; then
    echo "ERROR: src tree not found at ${SRC_DIR}" >&2
    exit 1
fi

rm -rf "${WORK_DIR}"
mkdir -p "${STAGE_DIR}/usr/local/opnsense" "${STAGE_DIR}/usr/local/etc" "${META_DIR}" "${OUT_DIR}"

# Stage files exactly like install.sh destinations.
tar -C "${SRC_DIR}/opnsense" -cf - . | tar -C "${STAGE_DIR}/usr/local/opnsense" -xf -
tar -C "${SRC_DIR}/etc" -cf - . | tar -C "${STAGE_DIR}/usr/local/etc" -xf -

if [ -d "${STAGE_DIR}/usr/local/opnsense/scripts/OPNsense/dslite" ]; then
    find "${STAGE_DIR}/usr/local/opnsense/scripts/OPNsense/dslite" -type f -name "*.sh" -exec chmod 0555 {} \;
fi

# Build plist from staged files/links. The parentheses are load-bearing: without
# them the implicit -print binds only to the last term on some find(1)s.
(
    cd "${STAGE_DIR}"
    find usr/local \( -type f -o -type l \) -print | sort
) > "${META_DIR}/plist"

cat > "${META_DIR}/manifest.ucl" <<UCL
name: "${PKG_NAME}"
version: "${PKG_VERSION}"
origin: "${PKG_ORIGIN}"
comment: "DS-Lite / Fixed IP (IPv4-over-IPv6) plugin for OPNsense"
maintainer: "${PKG_MAINTAINER}"
www: "${PKG_WWW}"
prefix: "/"
licenses: [ "BSD2CLAUSE" ]
desc: <<EOD
DS-Lite and Fixed IP (IPIP) IPv4-over-IPv6 plugin for OPNsense.
Provides tunnel configuration, health status, diagnostics, API, and dashboard widget
for Japanese IPoE ISPs (transix, xpass, v6 connect, and Fixed IP services).
EOD
categories: [ "net" ]
scripts: {
  post-install: <<EOD
#!/bin/sh
service configd restart >/dev/null 2>&1 || true
rm -rf /tmp/opnsense_*cache* >/dev/null 2>&1 || true

# No gif0 is pre-created here. Creating one on a box where the plugin is
# disabled would claim an interface name that may belong to another consumer,
# and would make it impossible to tell our tunnel apart from theirs later.

# Restore the tunnel when the plugin is enabled. pkg runs the new post-install
# last for both a fresh install and an upgrade (new pre-install, old
# pre-deinstall, replace files, new post-install), so this is also what brings
# the tunnel back after "pkg upgrade" stopped it. A disabled plugin is left
# alone: configure.sh tears down instead of starting.
if /usr/local/bin/xmllint --xpath "string(//OPNsense/dslite/enabled)" /conf/config.xml 2>/dev/null | grep -q '^1\$'; then
  attempt=0
  while [ \$attempt -lt 15 ]; do
    if /usr/local/sbin/configctl -d dslite configure >/dev/null 2>&1; then
      break
    fi
    attempt=\$((attempt + 1))
    sleep 2
  done
fi
EOD

  pre-deinstall: <<EOD
#!/bin/sh
# teardown.sh only removes a default route and a gif interface it can prove it
# created, so this is safe on a box where DS-Lite was never configured.
configctl dslite stop >/dev/null 2>&1 || true

# Drop runtime state. On an upgrade this runs before the new files are in
# place and post-install reconfigures afterwards, so nothing is lost.
rm -f /var/run/dslite_* >/dev/null 2>&1 || true
EOD
  post-deinstall: <<EOD
#!/bin/sh
service configd restart >/dev/null 2>&1 || true
rm -rf /tmp/opnsense_*cache* >/dev/null 2>&1 || true
EOD
}
UCL

pkg create \
    -M "${META_DIR}/manifest.ucl" \
    -r "${STAGE_DIR}" \
    -p "${META_DIR}/plist" \
    -o "${OUT_DIR}"

echo ""
echo "Package output directory: ${OUT_DIR}"
ls -1 "${OUT_DIR}" | sed 's/^/  - /'
