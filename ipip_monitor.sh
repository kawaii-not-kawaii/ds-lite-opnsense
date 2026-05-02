#!/bin/bash
LOG="/home/yun/dslite/ipip_monitor.log"
echo "=== Deep Monitor Started $(date) ===" >> "$LOG"
while true; do
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    result=$(ping -c 1 -W 3 183.76.136.137 2>&1)
    if echo "$result" | grep -q "time="; then
        latency=$(echo "$result" | grep -o "time=[0-9.]*" | cut -d= -f2)
        ping_status="OK ${latency}ms"
    else
        ping_status="DOWN"
    fi
    wan_ip=$(ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no root@192.168.0.1 'ip addr show ip6tnl1 2>/dev/null | grep "inet " | awk "{print \$2}"' 2>/dev/null)
    has_dslite="no"
    has_fixedip="no"
    echo "$wan_ip" | grep -q "192.0.0.2" && has_dslite="yes"
    echo "$wan_ip" | grep -q "183.76" && has_fixedip="yes"
    if [ "$has_dslite" = "yes" ]; then
        echo "${ts} PING:${ping_status} DSLITE:PRESENT FIXEDIP:${has_fixedip} ALERT!" >> "$LOG"
    else
        echo "${ts} PING:${ping_status} DSLITE:clean FIXEDIP:${has_fixedip}" >> "$LOG"
    fi
    sleep 10
done
