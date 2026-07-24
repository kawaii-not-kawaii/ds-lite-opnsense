#!/bin/sh

# DS-Lite / Fixed IP tunnel configuration script
# Creates gif tunnel interface for IPv4-in-IPv6 encapsulation
#
# Invocation: no argument for the hook-driven path (boot, WAN renewal, Apply),
# "restart" to tear down first, "start" from the service control.

SCRIPT_DIR=$(dirname "$0")

# Serialize concurrent invocations. rc.newwanip, a config save and the service
# control can all fire at once; a wall-clock comparison is not serialization.
LOCK_FILE="/var/run/dslite_configure.lock"
if [ -z "${DSLITE_CONFIGURE_LOCKED}" ] && [ -x /usr/bin/lockf ]; then
    DSLITE_CONFIGURE_LOCKED=1
    export DSLITE_CONFIGURE_LOCKED
    exec /usr/bin/lockf -k -t 120 "${LOCK_FILE}" "$0" "$@"
fi

. "${SCRIPT_DIR}/lib.sh"

# Load configuration
get_config

ACTION="$1"
STAMP_FILE="/var/run/dslite_configure.stamp"

# Coalesce redundant hook-driven runs. Only the asynchronous path is debounced:
# an explicit start/restart, and any run following a failure, must always do the
# work. The stamp is written after a successful run, never before, so a failed
# attempt can never suppress the retry that fixes it.
case "${ACTION}" in
    restart|start)
        ;;
    *)
        if [ -f "${STAMP_FILE}" ]; then
            LAST=$(cat "${STAMP_FILE}" 2>/dev/null)
            case "${LAST}" in
                ''|*[!0-9]*) LAST=0 ;;
            esac
            NOW=$(date +%s)
            # A backwards clock step would otherwise suppress work indefinitely.
            if [ "${LAST}" -le "${NOW}" ] && [ $(( NOW - LAST )) -lt 3 ]; then
                logger -t dslite "Skipping duplicate configure trigger"
                exit 0
            fi
        fi
        ;;
esac

# Check if we should tear down first (restart)
if [ "${ACTION}" = "restart" ]; then
    "${SCRIPT_DIR}/teardown.sh"
fi

# Bail out if not enabled
if [ "${DSLITE_ENABLED}" != "1" ]; then
    logger -t dslite "DS-Lite is disabled, tearing down any existing tunnel"
    "${SCRIPT_DIR}/teardown.sh"
    exit 0
fi

# Determine tunnel parameters based on mode
TUNNEL_MODE=$(get_mode)

WAN_IF=$(get_wan_if_device)

if [ "${TUNNEL_MODE}" = "fixedip" ]; then
    # Fixed IP mode: use member-specific parameters from Asahi Net / v6 Connect
    FIXEDIP_INTERFACE_ID=$(config_get "//OPNsense/dslite/fixedip_interface_id")
    FIXEDIP_AFTR=$(config_get "//OPNsense/dslite/fixedip_aftr")
    FIXEDIP_V4=$(config_get "//OPNsense/dslite/fixedip_v4")
    FIXEDIP_UPDATE_URL=$(config_get "//OPNsense/dslite/fixedip_update_url")
    FIXEDIP_AUTH_USER=$(config_get "//OPNsense/dslite/fixedip_auth_user")
    FIXEDIP_AUTH_PASS=$(config_get "//OPNsense/dslite/fixedip_auth_pass")

    if [ -z "${FIXEDIP_INTERFACE_ID}" ] || [ -z "${FIXEDIP_AFTR}" ] || [ -z "${FIXEDIP_V4}" ]; then
        logger -t dslite "ERROR: Fixed IP mode requires Interface ID, AFTR endpoint, and Fixed IPv4 address"
        exit 1
    fi

    AFTR_ADDRESS="${FIXEDIP_AFTR}"
    B4_ADDRESS="${FIXEDIP_V4}"
    AFTR_V4_ADDRESS=""

    # The Interface ID needs to be combined with the PD prefix to form
    # a full routable IPv6 address for the tunnel source.
    # Asahi Net provides the Interface ID as the host portion.
    PD_PREFIX=$(get_pd_prefix)
    if [ -n "${PD_PREFIX}" ] && command -v python3 >/dev/null 2>&1; then
        # Combine prefix + interface ID using python for reliable IPv6 math
        # The interface ID must be shifted to align with the prefix boundary
        # For /56 prefix: shift left 8 bits; for /64: no shift; etc.
        LOCAL_V6=$(python3 -c "
import sys, ipaddress
prefix = ipaddress.ip_network(sys.argv[1], strict=False)
iface_id = int(ipaddress.ip_address(sys.argv[2]))
shift = 64 - prefix.prefixlen
if shift > 0:
    iface_id = iface_id << shift
combined = int(prefix.network_address) | iface_id
print(str(ipaddress.ip_address(combined)))
" "${PD_PREFIX}" "${FIXEDIP_INTERFACE_ID}" 2>/dev/null)
    fi

    # Fallback: if no prefix available, use the Interface ID as-is
    # (user may have entered a full address)
    if [ -z "${LOCAL_V6}" ]; then
        LOCAL_V6="${FIXEDIP_INTERFACE_ID}"
    fi

    # Assign/refresh the tunnel-local /128 on WAN, cleaning up any stale alias.
    # A failure here means the tunnel source address does not exist, so the
    # replacement tunnel would be unusable: stop before destroying the working
    # one rather than after.
    if ! manage_wan_alias "${LOCAL_V6}" "${WAN_IF}"; then
        logger -t dslite "ERROR: could not establish WAN /128 alias ${LOCAL_V6} on ${WAN_IF}; leaving the existing tunnel untouched"
        exit 1
    fi
    sleep 1

    # Refresh the provider-side prefix registration. Credentials go via a
    # mode-0600 netrc and are never sent over an unverified connection.
    if [ -n "${FIXEDIP_UPDATE_URL}" ] && [ -n "${FIXEDIP_AUTH_USER}" ]; then
        logger -t dslite "Sending prefix update to ${FIXEDIP_UPDATE_URL}"
        UPDATE_RESULT=$(dslite_authed_get "${FIXEDIP_UPDATE_URL}" "${FIXEDIP_AUTH_USER}" \
            "${FIXEDIP_AUTH_PASS}" "${FIXEDIP_ALLOW_INSECURE}")
        UPDATE_RC=$?
        UPDATE_CODE=$(printf '%s' "${UPDATE_RESULT}" | awk '{print $1; exit}')
        write_prefix_update_state "${UPDATE_RC}" "${UPDATE_CODE}"
        logger -t dslite "Prefix update response: ${UPDATE_RESULT}"
    fi

    logger -t dslite "Fixed IP mode: local=${LOCAL_V6} aftr=${AFTR_ADDRESS} ipv4=${B4_ADDRESS}"
else
    # Standard DS-Lite mode
    if [ -z "${AFTR_ADDRESS}" ]; then
        logger -t dslite "ERROR: No AFTR address configured or resolved"
        exit 1
    fi

    # A native global address on the WAN is preferred. Any /128 we manage
    # ourselves is dropped first so that a Fixed IP -> DS-Lite mode change does
    # not leave a stale alias behind, and cannot be picked as the source.
    if read_alias_state; then
        if ! remove_wan_alias "${WAN_IF}"; then
            logger -t dslite "ERROR: could not remove the managed WAN /128 alias; aborting"
            exit 1
        fi
    fi

    # Get WAN IPv6 address (global scope)
    LOCAL_V6=$(get_wan_ipv6)

    # If no global address, try to derive one from DHCPv6-PD prefix
    if [ -z "${LOCAL_V6}" ]; then
        logger -t dslite "No global IPv6 on WAN, attempting to derive from PD prefix"
        # PD may not be ready at boot, so retry for a while.
        for attempt in 1 2 3 4 5 6; do
            PD_PREFIX=$(get_pd_prefix)
            if [ -n "${PD_PREFIX}" ]; then
                BASE_PREFIX=$(echo "${PD_PREFIX}" | sed 's|/.*||; s/::$//')
                LOCAL_V6="${BASE_PREFIX}::1"
                if ! manage_wan_alias "${LOCAL_V6}" "${WAN_IF}"; then
                    logger -t dslite "ERROR: could not establish WAN /128 alias ${LOCAL_V6} on ${WAN_IF}"
                    exit 1
                fi
                sleep 1
                break
            fi
            logger -t dslite "Waiting for IPv6 prefix delegation (attempt ${attempt}/6)..."
            sleep 5
        done
    fi

    if [ -z "${LOCAL_V6}" ]; then
        logger -t dslite "ERROR: No global IPv6 address found on WAN interface (${WAN_INTERFACE})"
        exit 1
    fi

    logger -t dslite "DS-Lite mode: local=${LOCAL_V6} aftr=${AFTR_ADDRESS}"
fi

# Tear down the existing tunnel, but only when it is ours. A gif unit belonging to
# another consumer must not be hijacked.
if tunnel_exists; then
    if tunnel_is_ours "${TUNNEL_IF}"; then
        logger -t dslite "Removing existing tunnel interface ${TUNNEL_IF}"
        ifconfig "${TUNNEL_IF}" destroy 2>/dev/null
    else
        logger -t dslite "ERROR: ${TUNNEL_IF} exists but was not created by this plugin; refusing to take it over. Pick a free gif unit under Interfaces > DS-Lite (Tunnel Interface), or remove the conflicting tunnel."
        exit 1
    fi
fi
rm -f "${STATE_OWNED_IF}"

# Create gif tunnel interface
if ! ifconfig "${TUNNEL_IF}" create; then
    logger -t dslite "ERROR: Failed to create ${TUNNEL_IF}"
    exit 1
fi

# Configure IPv6 tunnel endpoints (IPv4-in-IPv6)
if ! ifconfig "${TUNNEL_IF}" inet6 tunnel "${LOCAL_V6}" "${AFTR_ADDRESS}"; then
    logger -t dslite "ERROR: Failed to set tunnel endpoints"
    ifconfig "${TUNNEL_IF}" destroy 2>/dev/null
    exit 1
fi

# Claim ownership as soon as the endpoints are in place, so that a teardown
# after a partial failure still knows this interface is ours to remove.
record_owned_tunnel "${TUNNEL_IF}" "${LOCAL_V6}" "${AFTR_ADDRESS}"

# Configure IPv4 addresses on tunnel
if [ "${TUNNEL_MODE}" = "fixedip" ]; then
    # Fixed IP: assign the public IPv4 as point-to-point on tunnel interface
    ifconfig "${TUNNEL_IF}" inet "${B4_ADDRESS}" "${B4_ADDRESS}" netmask 255.255.255.255
    logger -t dslite "Fixed IP ${B4_ADDRESS} assigned to ${TUNNEL_IF}"
else
    # DS-Lite: standard B4/AFTR point-to-point (RFC 6333)
    ifconfig "${TUNNEL_IF}" inet "${B4_ADDRESS}" "${AFTR_V4_ADDRESS}" netmask 255.255.255.248
fi

# Set MTU
ifconfig "${TUNNEL_IF}" mtu "${MTU}"

# Apply TCP MSS clamping via sysctl (derives MSS from interface MTU)
sysctl net.inet.tcp.mss_ifmtu=1 >/dev/null 2>&1

# Bring interface up
ifconfig "${TUNNEL_IF}" up

logger -t dslite "Tunnel ${TUNNEL_IF} created via ${AFTR_ADDRESS}"

# Install the default IPv4 route through the tunnel. Our own previous route is
# withdrawn first; "route change" then adjusts an existing foreign route in
# place rather than blindly deleting whatever is in the table.
remove_owned_default_route
if [ "${TUNNEL_MODE}" = "fixedip" ]; then
    # For IPIP tunnel, route via the tunnel interface directly
    if route add default -interface "${TUNNEL_IF}" 2>/dev/null ||
       route change default -interface "${TUNNEL_IF}" 2>/dev/null; then
        record_owned_route "iface" "-" "${TUNNEL_IF}"
        logger -t dslite "Default IPv4 route set via ${TUNNEL_IF}"
    else
        logger -t dslite "WARNING: Failed to add default route via ${TUNNEL_IF}"
    fi
else
    if route add default "${AFTR_V4_ADDRESS}" 2>/dev/null ||
       route change default "${AFTR_V4_ADDRESS}" 2>/dev/null; then
        record_owned_route "gw" "${AFTR_V4_ADDRESS}" "${TUNNEL_IF}"
        logger -t dslite "Default IPv4 route set via ${AFTR_V4_ADDRESS}"
    else
        logger -t dslite "WARNING: Failed to add default route via ${AFTR_V4_ADDRESS}"
    fi
fi

# Configure NAT and firewall rules via OPNsense's registered anchors
if [ "${NAT_ENABLED}" = "1" ]; then
    NAT_FILE="/tmp/dslite_nat.conf"
    if [ "${TUNNEL_MODE}" = "fixedip" ]; then
        # Fixed IP: NAT to the public fixed IP
        cat > "${NAT_FILE}" << NATEOF
nat on ${TUNNEL_IF} from any to any -> ${B4_ADDRESS}
NATEOF
    else
        # DS-Lite: NAT to tunnel interface address
        cat > "${NAT_FILE}" << NATEOF
nat on ${TUNNEL_IF} from any to any -> (${TUNNEL_IF})
NATEOF
    fi

    FW_FILE="/tmp/dslite_fw.conf"
    cat > "${FW_FILE}" << FWEOF
pass out quick on ${TUNNEL_IF} all keep state
pass in quick on ${TUNNEL_IF} all keep state
FWEOF

    # Load into OPNsense's registered anchors
    if pfctl -a "dslite/nat" -f "${NAT_FILE}" 2>/dev/null; then
        logger -t dslite "NAT rules loaded for ${TUNNEL_IF}"
    else
        logger -t dslite "WARNING: Failed to load NAT anchor, trying filter reload"
        configctl filter reload 2>/dev/null
        sleep 1
        pfctl -a "dslite/nat" -f "${NAT_FILE}" 2>/dev/null
    fi

    if pfctl -a "dslite/fw" -f "${FW_FILE}" 2>/dev/null; then
        logger -t dslite "Firewall rules loaded for ${TUNNEL_IF}"
    else
        logger -t dslite "WARNING: Failed to load firewall anchor"
    fi
fi

# Drop any cached health result so the next status poll reflects the new tunnel.
rm -f /var/run/dslite_health_cache

# Mark this run successful. The debounce above only ever suppresses work that
# followed a run which actually completed.
date +%s > "${STAMP_FILE}"

logger -t dslite "Tunnel configuration complete (mode: ${TUNNEL_MODE})"
exit 0
