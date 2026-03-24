#!/bin/sh

# DS-Lite shared library functions
# Reads configuration from OPNsense XML config

TUNNEL_IF="gif0"
CONFIG_XML="/conf/config.xml"

# Known ISP AFTR addresses (fallback only - prefer auto-detection)
AFTR_TRANSIX="2001:c28:5:301::11"
AFTR_XPASS="2001:f60:0:200::1"
AFTR_V6CONNECT="2404:8e00::feed:100"

# Prefix-to-AFTR mapping table for Japanese DS-Lite ISPs
# Format: prefix/len|aftr_address (pipe-delimited to avoid IPv6 colon conflict)
# Sources: UDM-Pro config, community documentation, ISP specifications
AFTR_MAP="
2001:c28::/32|2001:c28:5:301::11
2405:6580::/28|2001:c28:5:301::11
2405:6500::/24|2001:c28:5:301::11
2409:10::/30|2001:c28:5:301::11
2409:250::/30|2001:c28:5:301::11
2001:f60::/32|2001:f60:0:200::1
2404:8e00::/32|2404:8e00::feed:100
2404:8e01::/32|2404:8e00::feed:101
"

# Read a value from the OPNsense config XML
# Usage: config_get "xpath"
config_get() {
    local xpath="$1"
    /usr/local/bin/xmllint --xpath "string(${xpath})" "${CONFIG_XML}" 2>/dev/null
}

# Convert an IPv6 address to a fully expanded 32-char hex string
# e.g. 2405:6586:9c00:: -> 240565869c00000000000000000000000
ipv6_to_hex() {
    local addr="$1"
    # Remove prefix length if present
    addr=$(echo "${addr}" | sed 's|/.*||')
    # Use printf through a small python one-liner for reliable expansion
    # Fallback to manual expansion if python not available
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import sys, ipaddress
a = ipaddress.ip_address(sys.argv[1])
print(format(int(a), '032x'))
" "${addr}" 2>/dev/null
        return
    fi
    # Manual expansion: replace :: with enough 0s, then expand each group
    echo "${addr}" | awk -F: '{
        # Count non-empty groups
        n = 0; for(i=1;i<=NF;i++) if($i!="") n++
        out = ""
        for(i=1;i<=NF;i++) {
            if($i == "" && i>1 && i<NF) {
                for(j=0;j<8-n;j++) out = out "0000"
            } else if($i != "") {
                out = out sprintf("%04s", $i)
            }
        }
        gsub(/ /, "0", out)
        print out
    }'
}

# Check if an IPv6 address matches a prefix
# Usage: ipv6_prefix_match "address" "prefix/len"
ipv6_prefix_match() {
    local addr_hex prefix_hex
    local addr="$1"
    local prefix="$2"
    local prefixlen=$(echo "${prefix}" | sed 's|.*/||')
    local prefixaddr=$(echo "${prefix}" | sed 's|/.*||')

    addr_hex=$(ipv6_to_hex "${addr}")
    prefix_hex=$(ipv6_to_hex "${prefixaddr}")

    if [ -z "${addr_hex}" ] || [ -z "${prefix_hex}" ]; then
        return 1
    fi

    # Compare the first prefixlen/4 hex chars (rough, works for /16,/24,/28,/30,/32)
    local hexchars=$(( prefixlen / 4 ))
    local addr_part=$(echo "${addr_hex}" | cut -c1-${hexchars})
    local prefix_part=$(echo "${prefix_hex}" | cut -c1-${hexchars})

    [ "${addr_part}" = "${prefix_part}" ]
}

# Auto-detect AFTR address from delegated prefix using prefix-to-AFTR mapping
# This is the primary discovery mechanism for Japanese DS-Lite ISPs
detect_aftr_from_prefix() {
    local pd_prefix="$1"
    if [ -z "${pd_prefix}" ]; then
        return 1
    fi

    local prefix_addr
    prefix_addr=$(echo "${pd_prefix}" | sed 's|/.*||')

    # Write map to temp file and use redirect instead of pipe
    # (pipe creates subshell which loses echo output)
    local _result=""
    local _tmpfile="/tmp/dslite_aftr_map.tmp"
    echo "${AFTR_MAP}" > "${_tmpfile}"
    while IFS='|' read -r map_prefix map_aftr; do
        # Skip empty lines
        [ -z "${map_prefix}" ] && continue
        # Remove leading/trailing whitespace
        map_prefix=$(echo "${map_prefix}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        map_aftr=$(echo "${map_aftr}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "${map_prefix}" ] && continue

        if ipv6_prefix_match "${prefix_addr}" "${map_prefix}"; then
            _result="${map_aftr}"
            break
        fi
    done < "${_tmpfile}"
    rm -f "${_tmpfile}"

    if [ -n "${_result}" ]; then
        echo "${_result}"
        return 0
    fi
    return 1
}

# Try DNS resolution for AFTR hostname
resolve_aftr_dns() {
    local hostname="$1"
    if [ -z "${hostname}" ]; then
        return 1
    fi

    # Use drill (available on FreeBSD/OPNsense)
    local result
    result=$(drill AAAA "${hostname}" 2>/dev/null | grep -A1 "ANSWER SECTION" | \
        grep "AAAA" | awk '{print $NF}' | head -1)

    if [ -n "${result}" ]; then
        echo "${result}"
        return 0
    fi
    return 1
}

# Get DS-Lite configuration values
get_config() {
    DSLITE_ENABLED=$(config_get "//OPNsense/dslite/enabled")
    ISP_PROFILE=$(config_get "//OPNsense/dslite/isp_profile")
    WAN_INTERFACE=$(config_get "//OPNsense/dslite/wan_interface")
    AFTR_ADDRESS=$(config_get "//OPNsense/dslite/aftr_address")
    AFTR_HOSTNAME=$(config_get "//OPNsense/dslite/aftr_hostname")
    B4_ADDRESS=$(config_get "//OPNsense/dslite/b4_address")
    AFTR_V4_ADDRESS=$(config_get "//OPNsense/dslite/aftr_v4_address")
    MTU=$(config_get "//OPNsense/dslite/mtu")
    MSS_CLAMP=$(config_get "//OPNsense/dslite/mss_clamp")
    NAT_ENABLED=$(config_get "//OPNsense/dslite/nat_enabled")

    # Defaults
    B4_ADDRESS="${B4_ADDRESS:-192.0.0.2}"
    AFTR_V4_ADDRESS="${AFTR_V4_ADDRESS:-192.0.0.1}"
    MTU="${MTU:-1460}"
    MSS_CLAMP="${MSS_CLAMP:-1420}"
    NAT_ENABLED="${NAT_ENABLED:-1}"

    # AFTR discovery priority:
    # 1. Explicit address in config (user override)
    # 2. Auto-detect from PD prefix (prefix-to-AFTR mapping)
    # 3. DNS resolution of AFTR hostname
    # 4. ISP profile hardcoded fallback
    if [ -z "${AFTR_ADDRESS}" ]; then
        # Try auto-detection from PD prefix
        local pd_prefix
        pd_prefix=$(get_pd_prefix)
        if [ -n "${pd_prefix}" ]; then
            local detected
            detected=$(detect_aftr_from_prefix "${pd_prefix}")
            if [ -n "${detected}" ]; then
                AFTR_ADDRESS="${detected}"
                logger -t dslite "Auto-detected AFTR ${AFTR_ADDRESS} from prefix ${pd_prefix}"
            fi
        fi
    fi

    if [ -z "${AFTR_ADDRESS}" ] && [ -n "${AFTR_HOSTNAME}" ]; then
        # Try DNS resolution
        local resolved
        resolved=$(resolve_aftr_dns "${AFTR_HOSTNAME}")
        if [ -n "${resolved}" ]; then
            AFTR_ADDRESS="${resolved}"
            logger -t dslite "Resolved AFTR ${AFTR_ADDRESS} from hostname ${AFTR_HOSTNAME}"
        fi
    fi

    if [ -z "${AFTR_ADDRESS}" ]; then
        # Fallback to ISP profile hardcoded address
        case "${ISP_PROFILE}" in
            transix)  AFTR_ADDRESS="${AFTR_TRANSIX}" ;;
            xpass)    AFTR_ADDRESS="${AFTR_XPASS}" ;;
            v6connect) AFTR_ADDRESS="${AFTR_V6CONNECT}" ;;
        esac
        if [ -n "${AFTR_ADDRESS}" ]; then
            logger -t dslite "Using fallback AFTR ${AFTR_ADDRESS} from ISP profile ${ISP_PROFILE}"
        fi
    fi
}

# Get the WAN interface's global IPv6 address
get_wan_ipv6() {
    local wan_if
    # Resolve OPNsense interface name to real device name
    wan_if=$(config_get "//interfaces/${WAN_INTERFACE}/if")
    if [ -z "${wan_if}" ]; then
        wan_if="${WAN_INTERFACE}"
    fi

    # Get the first global scope IPv6 address
    ifconfig "${wan_if}" 2>/dev/null | \
        grep "inet6" | grep -v "fe80" | grep -v "::1" | \
        head -1 | awk '{print $2}' | sed 's/%.*$//'
}

# Get DHCPv6-PD prefix from OPNsense temp files or interface addresses
get_pd_prefix() {
    local wan_if
    wan_if=$(config_get "//interfaces/${WAN_INTERFACE}/if")
    wan_if="${wan_if:-${WAN_INTERFACE}}"

    # Method 1: OPNsense stores DHCPv6-PD prefix in /tmp/<if>_prefixv6
    local prefix_file="/tmp/${wan_if}_prefixv6"
    if [ -f "${prefix_file}" ]; then
        cat "${prefix_file}" 2>/dev/null | head -1 | grep -o '[0-9a-f:]*::/[0-9]*'
        return
    fi

    # Method 2: query ifctl for PD info
    local ifctl_result
    ifctl_result=$(/usr/local/sbin/ifctl -i "${wan_if}" -6pd -l 2>/dev/null)
    if [ -n "${ifctl_result}" ] && [ -f "${ifctl_result}" ]; then
        cat "${ifctl_result}" 2>/dev/null | head -1 | grep -o '[0-9a-f:]*::/[0-9]*'
        return
    fi

    # Method 3: Derive prefix from global IPv6 on any interface
    # NTT IPoE delegates PD to LAN, so check all interfaces for a global address
    # and extract the /56 prefix from it
    local global_addr
    global_addr=$(ifconfig -a 2>/dev/null | grep "inet6 2" | grep -v "fe80" | grep -v "::1" | \
        head -1 | awk '{print $2}' | sed 's/%.*$//')
    if [ -n "${global_addr}" ] && command -v python3 >/dev/null 2>&1; then
        python3 -c "
import sys, ipaddress
addr = ipaddress.ip_address(sys.argv[1])
# Extract /56 network prefix
net = ipaddress.ip_network(str(addr) + '/56', strict=False)
print(str(net))
" "${global_addr}" 2>/dev/null
        return
    fi

    # Method 3 fallback without python: rough extraction
    if [ -n "${global_addr}" ]; then
        # Take the first 14 hex chars (56 bits = 14 nibbles) of expanded address
        local prefix_part
        prefix_part=$(echo "${global_addr}" | sed 's/::.*//; s/:[0-9a-f]*:[0-9a-f]*:[0-9a-f]*$//')
        if [ -n "${prefix_part}" ]; then
            echo "${prefix_part}::/56"
            return
        fi
    fi
}

# Check if tunnel interface exists and is configured
tunnel_exists() {
    ifconfig "${TUNNEL_IF}" >/dev/null 2>&1
}

# Get tunnel status as JSON
get_tunnel_status() {
    if tunnel_exists; then
        local ifdata
        ifdata=$(ifconfig "${TUNNEL_IF}" 2>/dev/null)
        local status="down"
        echo "${ifdata}" | grep -q "UP" && status="up"

        local local_v6
        local_v6=$(echo "${ifdata}" | grep "tunnel inet6" | awk '{print $3}')

        local remote_v6
        remote_v6=$(echo "${ifdata}" | grep "tunnel inet6" | awk '{print $5}')

        local mtu
        mtu=$(echo "${ifdata}" | grep "mtu" | head -1 | sed 's/.*mtu //' | awk '{print $1}')

        printf '{"tunnel":{"status":"%s","local_v6":"%s","aftr":"%s","mtu":"%s","interface":"%s"}}' \
            "${status}" "${local_v6}" "${remote_v6}" "${mtu}" "${TUNNEL_IF}"
    else
        printf '{"tunnel":{"status":"not configured","local_v6":"-","aftr":"-","mtu":"-","interface":"%s"}}' \
            "${TUNNEL_IF}"
    fi
}
