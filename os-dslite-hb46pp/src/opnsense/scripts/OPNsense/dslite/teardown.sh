#!/bin/sh

# DS-Lite tunnel teardown script
# Removes gif tunnel interface and associated configuration

SCRIPT_DIR=$(dirname "$0")
. "${SCRIPT_DIR}/lib.sh"

logger -t dslite "Tearing down DS-Lite tunnel"

# Remove default route through tunnel
route delete default 2>/dev/null

# Flush pf anchor rules
pfctl -a "dslite/nat" -F all 2>/dev/null
pfctl -a "dslite/fw" -F all 2>/dev/null
pfctl -a "dslite" -F all 2>/dev/null

# Destroy tunnel interface
if tunnel_exists; then
    ifconfig "${TUNNEL_IF}" down 2>/dev/null
    ifconfig "${TUNNEL_IF}" destroy 2>/dev/null
    logger -t dslite "Tunnel interface ${TUNNEL_IF} destroyed"
else
    logger -t dslite "Tunnel interface ${TUNNEL_IF} not found"
fi

# Cleanup temp files
rm -f /tmp/dslite_nat.conf /tmp/dslite_fw.conf

logger -t dslite "DS-Lite teardown complete"
exit 0
