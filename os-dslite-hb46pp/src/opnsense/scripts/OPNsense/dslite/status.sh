#!/bin/sh

# DS-Lite tunnel status script
# Returns JSON status for the web UI

SCRIPT_DIR=$(dirname "$0")
. "${SCRIPT_DIR}/lib.sh"

# Get basic tunnel info
if tunnel_exists; then
    ifdata=$(ifconfig "${TUNNEL_IF}" 2>/dev/null)
    status="down"
    echo "${ifdata}" | grep -q "RUNNING" && status="up"

    local_v6=$(echo "${ifdata}" | grep "tunnel inet6" | awk '{print $3}')
    remote_v6=$(echo "${ifdata}" | grep "tunnel inet6" | awk '{print $5}')
    ipv4=$(echo "${ifdata}" | grep "inet " | awk '{print $2}')
    mtu_val=$(echo "${ifdata}" | grep "mtu" | head -1 | sed 's/.*mtu //' | awk '{print $1}')

    # Quick connectivity test (1 packet, 2s timeout)
    # Use the tunnel's assigned IPv4 as source (works for both DS-Lite and Fixed IP)
    connectivity="untested"
    if [ "${status}" = "up" ] && [ -n "${ipv4}" ]; then
        if ping -c 1 -W 2 -S "${ipv4}" 8.8.8.8 >/dev/null 2>&1; then
            connectivity="connected"
        else
            connectivity="no internet"
        fi
    fi

    printf '{"tunnel":{"status":"%s","connectivity":"%s","local_v6":"%s","aftr":"%s","ipv4":"%s","mtu":"%s","interface":"%s"}}' \
        "${status}" "${connectivity}" "${local_v6}" "${remote_v6}" "${ipv4}" "${mtu_val}" "${TUNNEL_IF}"
else
    # Check if enabled but not configured
    get_config
    if [ "${DSLITE_ENABLED}" = "1" ]; then
        # Try to figure out why it's not up
        pd_prefix=$(get_pd_prefix)
        if [ -z "${pd_prefix}" ]; then
            reason="Waiting for IPv6 prefix delegation"
        elif [ -z "${AFTR_ADDRESS}" ]; then
            reason="Could not determine AFTR address"
        else
            reason="Not started - click Apply"
        fi
        printf '{"tunnel":{"status":"not configured","connectivity":"offline","local_v6":"-","aftr":"-","ipv4":"-","mtu":"-","interface":"%s","reason":"%s"}}' \
            "${TUNNEL_IF}" "${reason}"
    else
        printf '{"tunnel":{"status":"disabled","connectivity":"offline","local_v6":"-","aftr":"-","ipv4":"-","mtu":"-","interface":"%s","reason":"Service is disabled"}}' \
            "${TUNNEL_IF}"
    fi
fi
