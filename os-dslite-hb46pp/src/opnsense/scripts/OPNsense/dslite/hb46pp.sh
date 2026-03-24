#!/bin/sh

# HB46PP - HTTP-Based IPv4 over IPv6 Provisioning Protocol client
# Discovers provisioning server via DNS, retrieves tunnel parameters,
# and registers prefix with the AFTR.

SCRIPT_DIR=$(dirname "$0")
. "${SCRIPT_DIR}/lib.sh"

HB46PP_CACHE="/var/db/dslite_hb46pp.json"
HB46PP_DNS="4over6.info"

# Discover provisioning server URL from DNS TXT record
discover_server() {
    local txt_record
    # Extract TXT record content between quotes using backticks (csh-safe)
    txt_record=`drill TXT "${HB46PP_DNS}" 2>/dev/null | grep "v=v6mig-1" | awk -F'"' '{print $2}'`
    if [ -z "${txt_record}" ]; then
        # Try with ISP DNS server
        local wan_if
        wan_if=$(config_get "//interfaces/${WAN_INTERFACE}/if")
        wan_if="${wan_if:-${WAN_INTERFACE}}"
        local dns_server
        dns_server=$(cat "/tmp/${wan_if}_nameserverv6" 2>/dev/null | head -1)
        if [ -n "${dns_server}" ]; then
            txt_record=`drill TXT "${HB46PP_DNS}" "@${dns_server}" 2>/dev/null | grep "v=v6mig-1" | awk -F'"' '{print $2}'`
        fi
    fi

    if [ -z "${txt_record}" ]; then
        logger -t dslite "HB46PP: Failed to discover provisioning server via DNS"
        return 1
    fi

    # Parse TXT record: v=v6mig-1 url=https://... t=b
    PROV_URL=`echo "${txt_record}" | sed 's/.*url=//' | sed 's/ .*//'`
    PROV_TLS=`echo "${txt_record}" | sed 's/.*t=//' | sed 's/ .*//'`

    if [ -z "${PROV_URL}" ]; then
        logger -t dslite "HB46PP: No URL in DNS TXT record"
        return 1
    fi

    logger -t dslite "HB46PP: Discovered provisioning server: ${PROV_URL}"
    return 0
}

# Query provisioning server for tunnel parameters
provision() {
    local user="$1"
    local pass="$2"
    local token="$3"

    if [ -z "${PROV_URL}" ]; then
        discover_server || return 1
    fi

    # Build query parameters
    local params="vendorid=000000&product=OPNsense&version=1_0&capability=dslite,ipip"
    if [ -n "${user}" ] && [ -n "${pass}" ]; then
        params="${params}&user=${user}&pass=${pass}"
    fi
    if [ -n "${token}" ]; then
        params="${params}&token=${token}"
    fi

    # TLS verification
    local tls_flag="-sk"
    if [ "${PROV_TLS}" = "b" ]; then
        tls_flag="-s"
    fi

    # Query provisioning server over IPv6
    local response
    response=$(curl -6 ${tls_flag} --max-time 15 "${PROV_URL}?${params}" 2>/dev/null)

    if [ -z "${response}" ]; then
        logger -t dslite "HB46PP: No response from provisioning server"
        return 1
    fi

    # Check auth status
    local auth_status
    auth_status=$(echo "${response}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('auth',''))" 2>/dev/null)

    case "${auth_status}" in
        ok)
            logger -t dslite "HB46PP: Authentication successful"
            ;;
        bad)
            logger -t dslite "HB46PP: Authentication failed"
            return 1
            ;;
        req)
            logger -t dslite "HB46PP: Server requires authentication but no credentials provided"
            return 1
            ;;
        *)
            logger -t dslite "HB46PP: Auth status: ${auth_status}"
            ;;
    esac

    # Cache the response
    echo "${response}" > "${HB46PP_CACHE}"
    chmod 600 "${HB46PP_CACHE}"

    logger -t dslite "HB46PP: Provisioning data cached"
    return 0
}

# Parse cached provisioning data and extract tunnel parameters
parse_provisioning() {
    if [ ! -f "${HB46PP_CACHE}" ]; then
        logger -t dslite "HB46PP: No cached provisioning data"
        return 1
    fi

    # Parse JSON response using python3
    eval $(python3 -c "
import sys, json

with open('${HB46PP_CACHE}') as f:
    data = json.load(f)

# Get preferred order
order = data.get('order', [])
print(f'HB46PP_ORDER=\"{\" \".join(order)}\"')
print(f'HB46PP_TTL=\"{data.get(\"ttl\", 86400)}\"')
print(f'HB46PP_TOKEN=\"{data.get(\"token\", \"\")}\"')
print(f'HB46PP_SERVICE=\"{data.get(\"service_name\", \"\")}\"')
print(f'HB46PP_ENABLER=\"{data.get(\"enabler_name\", \"\")}\"')

# IPIP parameters (fixed IP)
ipip = data.get('ipip', [])
if ipip:
    tunnel = ipip[0]
    print(f'HB46PP_IPIP_LOCAL=\"{tunnel.get(\"ipv6_local\", \"\")}\"')
    print(f'HB46PP_IPIP_REMOTE=\"{tunnel.get(\"ipv6_remote\", \"\")}\"')
    ipv4 = tunnel.get('ipv4', '')
    # Strip /32 if present
    print(f'HB46PP_IPIP_V4=\"{ipv4.split(\"/\")[0]}\"')

# DS-Lite parameters
dslite = data.get('dslite', {})
if dslite:
    print(f'HB46PP_DSLITE_AFTR=\"{dslite.get(\"aftr\", \"\")}\"')
" 2>/dev/null)

    if [ -z "${HB46PP_ORDER}" ]; then
        logger -t dslite "HB46PP: Failed to parse provisioning data"
        return 1
    fi

    logger -t dslite "HB46PP: Service=${HB46PP_SERVICE} Order=${HB46PP_ORDER}"
    return 0
}

# Get the TTL for re-provisioning
get_ttl() {
    parse_provisioning 2>/dev/null
    echo "${HB46PP_TTL:-86400}"
}

# Get cached token
get_token() {
    parse_provisioning 2>/dev/null
    echo "${HB46PP_TOKEN}"
}
