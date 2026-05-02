#!/bin/bash
# DNS connectivity test - tries multiple DNS servers and domains
# Logs successes and failures

LOG="/home/yun/dslite/dns_test.log"
echo "=== DNS Test Started $(date) ===" >> "$LOG"

DNS_SERVERS=(
    "8.8.8.8|Google"
    "8.8.4.4|Google2"
    "1.1.1.1|Cloudflare"
    "1.0.0.1|Cloudflare2"
    "9.9.9.9|Quad9"
    "208.67.222.222|OpenDNS"
    "192.168.0.1|UDM-Pro"
)

DOMAINS=(
    "google.com"
    "github.com"
    "cloudflare.com"
    "amazon.co.jp"
    "asahi-net.or.jp"
    "v6connect.net"
)

while true; do
    ts=$(date '+%Y-%m-%d %H:%M:%S')

    for server_pair in "${DNS_SERVERS[@]}"; do
        server="${server_pair%|*}"
        name="${server_pair#*|}"

        for domain in "${DOMAINS[@]}"; do
            # Time the query
            start=$(date +%s%N)
            result=$(dig +short +time=3 +tries=1 "@${server}" "${domain}" A 2>&1)
            end=$(date +%s%N)
            elapsed_ms=$(( (end - start) / 1000000 ))

            if [ -n "${result}" ] && echo "${result}" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
                echo "${ts} OK ${name}(${server}) ${domain} -> $(echo ${result} | head -1) ${elapsed_ms}ms" >> "$LOG"
            else
                echo "${ts} FAIL ${name}(${server}) ${domain} (${elapsed_ms}ms): ${result}" >> "$LOG"
            fi
        done
    done

    sleep 60
done
