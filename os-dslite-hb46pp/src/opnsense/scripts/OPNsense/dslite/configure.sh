#!/bin/sh

# DS-Lite / Fixed IP tunnel configuration script
# Priority: HB46PP auto-provisioning > manual advanced settings > auto-detect

SCRIPT_DIR=$(dirname "$0")
. "${SCRIPT_DIR}/lib.sh"
. "${SCRIPT_DIR}/hb46pp.sh"

# Load configuration
get_config

if [ "$1" = "restart" ]; then
    "${SCRIPT_DIR}/teardown.sh"
fi

if [ "${DSLITE_ENABLED}" != "1" ]; then
    logger -t dslite "Disabled, tearing down"
    "${SCRIPT_DIR}/teardown.sh"
    exit 0
fi

TUNNEL_MODE=$(config_get "//OPNsense/dslite/mode")
TUNNEL_MODE="${TUNNEL_MODE:-fixedip}"

WAN_IF=$(config_get "//interfaces/${WAN_INTERFACE}/if")
WAN_IF="${WAN_IF:-${WAN_INTERFACE}}"

HB46PP_USER=$(config_get "//OPNsense/dslite/hb46pp_user")
HB46PP_PASS=$(config_get "//OPNsense/dslite/hb46pp_pass")

# ============================================================
# Step 1: Try HB46PP auto-provisioning (if credentials present)
# ============================================================
HB46PP_OK=0
if [ -n "${HB46PP_USER}" ]; then
    logger -t dslite "Trying HB46PP auto-provisioning..."
    HB46PP_TOKEN=$(get_token)

    for attempt in 1 2 3; do
        if provision "${HB46PP_USER}" "${HB46PP_PASS}" "${HB46PP_TOKEN}"; then
            HB46PP_OK=1
            break
        fi
        logger -t dslite "HB46PP: Attempt ${attempt}/3 failed"
        sleep 5
    done

    # Try cached data if live provisioning failed
    if [ "${HB46PP_OK}" -ne 1 ] && [ -f "${HB46PP_CACHE}" ]; then
        logger -t dslite "HB46PP: Using cached data"
        HB46PP_OK=1
    fi

    if [ "${HB46PP_OK}" -eq 1 ]; then
        parse_provisioning
        if [ $? -eq 0 ]; then
            # Apply based on selected mode
            if [ "${TUNNEL_MODE}" = "fixedip" ] && [ -n "${HB46PP_IPIP_LOCAL}" ]; then
                LOCAL_V6="${HB46PP_IPIP_LOCAL}"
                AFTR_ADDRESS="${HB46PP_IPIP_REMOTE}"
                B4_ADDRESS="${HB46PP_IPIP_V4}"
                AFTR_V4_ADDRESS=""
                logger -t dslite "HB46PP: Fixed IP - ${B4_ADDRESS} via ${AFTR_ADDRESS}"
            elif [ -n "${HB46PP_DSLITE_AFTR}" ]; then
                # Resolve AFTR FQDN
                resolved=`drill AAAA "${HB46PP_DSLITE_AFTR}" 2>/dev/null | grep -A1 "ANSWER SECTION" | grep AAAA | awk '{print $NF}' | head -1`
                if [ -n "${resolved}" ]; then
                    AFTR_ADDRESS="${resolved}"
                fi
                TUNNEL_MODE="dslite"
                logger -t dslite "HB46PP: DS-Lite - aftr=${AFTR_ADDRESS}"
            else
                HB46PP_OK=0
                logger -t dslite "HB46PP: No matching connection type for mode ${TUNNEL_MODE}"
            fi
        else
            HB46PP_OK=0
        fi
    fi
fi

# ============================================================
# Step 2: Fall back to manual/advanced settings
# ============================================================
if [ "${HB46PP_OK}" -ne 1 ]; then
    logger -t dslite "Using manual configuration (mode: ${TUNNEL_MODE})"

    if [ "${TUNNEL_MODE}" = "fixedip" ]; then
        # Check for manual Fixed IP settings
        FIXEDIP_INTERFACE_ID=$(config_get "//OPNsense/dslite/fixedip_interface_id")
        FIXEDIP_AFTR=$(config_get "//OPNsense/dslite/fixedip_aftr")
        FIXEDIP_V4=$(config_get "//OPNsense/dslite/fixedip_v4")

        if [ -n "${FIXEDIP_INTERFACE_ID}" ] && [ -n "${FIXEDIP_AFTR}" ] && [ -n "${FIXEDIP_V4}" ]; then
            AFTR_ADDRESS="${FIXEDIP_AFTR}"
            B4_ADDRESS="${FIXEDIP_V4}"
            AFTR_V4_ADDRESS=""

            PD_PREFIX=$(get_pd_prefix)
            if [ -n "${PD_PREFIX}" ] && command -v python3 >/dev/null 2>&1; then
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
            if [ -z "${LOCAL_V6}" ]; then
                LOCAL_V6="${FIXEDIP_INTERFACE_ID}"
            fi
            logger -t dslite "Manual Fixed IP: ${B4_ADDRESS} via ${AFTR_ADDRESS}"
        else
            logger -t dslite "ERROR: Fixed IP mode requires provisioning credentials or manual Interface ID/AFTR/IPv4"
            exit 1
        fi
    else
        # DS-Lite: use manual AFTR or auto-detect
        if [ -z "${AFTR_ADDRESS}" ]; then
            PD_PREFIX=$(get_pd_prefix)
            if [ -n "${PD_PREFIX}" ]; then
                AFTR_ADDRESS=$(detect_aftr_from_prefix "${PD_PREFIX}")
            fi
        fi
        if [ -z "${AFTR_ADDRESS}" ]; then
            logger -t dslite "ERROR: No AFTR address - provide provisioning credentials or set manually"
            exit 1
        fi
        logger -t dslite "Manual DS-Lite: aftr=${AFTR_ADDRESS}"
    fi
fi

# ============================================================
# Derive local IPv6 for DS-Lite if not set
# ============================================================
if [ -z "${LOCAL_V6}" ]; then
    LOCAL_V6=$(get_wan_ipv6)
    if [ -z "${LOCAL_V6}" ]; then
        for i in 1 2 3 4 5; do
            logger -t dslite "Waiting for IPv6 prefix (attempt $i/5)..."
            sleep 5
            PD_PREFIX=$(get_pd_prefix)
            if [ -n "${PD_PREFIX}" ]; then
                BASE_PREFIX=`echo "${PD_PREFIX}" | sed 's|/.*||; s/::$//'`
                LOCAL_V6="${BASE_PREFIX}::1"
                break
            fi
        done
    fi
fi

if [ -z "${LOCAL_V6}" ]; then
    logger -t dslite "ERROR: No IPv6 address available"
    exit 1
fi

# Assign to WAN if needed
if ! ifconfig "${WAN_IF}" 2>/dev/null | grep -q "${LOCAL_V6}"; then
    ifconfig "${WAN_IF}" inet6 "${LOCAL_V6}" prefixlen 128
    logger -t dslite "Assigned ${LOCAL_V6} to ${WAN_IF}"
    sleep 2
fi

# ============================================================
# Create tunnel
# ============================================================
if tunnel_exists; then
    ifconfig "${TUNNEL_IF}" destroy 2>/dev/null
fi

ifconfig "${TUNNEL_IF}" create || { logger -t dslite "ERROR: Failed to create ${TUNNEL_IF}"; exit 1; }

ifconfig "${TUNNEL_IF}" inet6 tunnel "${LOCAL_V6}" "${AFTR_ADDRESS}"
if [ $? -ne 0 ]; then
    logger -t dslite "ERROR: Failed to set tunnel endpoints"
    ifconfig "${TUNNEL_IF}" destroy 2>/dev/null
    exit 1
fi

if [ "${TUNNEL_MODE}" = "fixedip" ]; then
    ifconfig "${TUNNEL_IF}" inet "${B4_ADDRESS}" "${B4_ADDRESS}" netmask 255.255.255.255
else
    B4_ADDRESS="${B4_ADDRESS:-192.0.0.2}"
    AFTR_V4_ADDRESS="${AFTR_V4_ADDRESS:-192.0.0.1}"
    ifconfig "${TUNNEL_IF}" inet "${B4_ADDRESS}" "${AFTR_V4_ADDRESS}" netmask 255.255.255.248
fi

ifconfig "${TUNNEL_IF}" mtu "${MTU}"
ifconfig "${TUNNEL_IF}" up
sysctl net.inet.tcp.mss_ifmtu=1 >/dev/null 2>&1

logger -t dslite "Tunnel up: ${LOCAL_V6} -> ${AFTR_ADDRESS} [${TUNNEL_MODE}]"

# Route
route delete default 2>/dev/null
if [ "${TUNNEL_MODE}" = "fixedip" ]; then
    route add default -interface "${TUNNEL_IF}" 2>/dev/null
else
    route add default "${AFTR_V4_ADDRESS}" 2>/dev/null
fi

# NAT + firewall
if [ "${NAT_ENABLED}" = "1" ]; then
    NAT_FILE="/tmp/dslite_nat.conf"
    if [ "${TUNNEL_MODE}" = "fixedip" ]; then
        echo "nat on ${TUNNEL_IF} from any to any -> ${B4_ADDRESS}" > "${NAT_FILE}"
    else
        echo "nat on ${TUNNEL_IF} from any to any -> (${TUNNEL_IF})" > "${NAT_FILE}"
    fi

    FW_FILE="/tmp/dslite_fw.conf"
    cat > "${FW_FILE}" << EOF
pass out quick on ${TUNNEL_IF} all keep state
pass in quick on ${TUNNEL_IF} all keep state
EOF

    pfctl -a "dslite/nat" -f "${NAT_FILE}" 2>/dev/null || {
        configctl filter reload 2>/dev/null; sleep 1
        pfctl -a "dslite/nat" -f "${NAT_FILE}" 2>/dev/null
    }
    pfctl -a "dslite/fw" -f "${FW_FILE}" 2>/dev/null
    logger -t dslite "NAT and firewall loaded"
fi

logger -t dslite "Done (${TUNNEL_MODE})"
exit 0
