#!/bin/bash
# Poll UDM for VNE prefix return + IPv6 connectivity.
LOG=/home/yun/dslite/vne_watch.log
: > "$LOG"
while true; do
  TS=$(date +%H:%M:%S)
  OUT=$(ssh -o ConnectTimeout=5 root@192.168.0.1 '
    ADDR=$(ip -6 addr show eth9 | awk "/inet6 2/ {print \$2}" | tr "\n" " ")
    PD=$(ip -6 route | grep -E "::/(56|60|48)" | grep -v fe80 | tr "\n" "|")
    PING=$(ping6 -c1 -W2 2404:6800:400a:1000::9a 2>&1 | grep -Eo "[0-9]+ received" || echo no-reply)
    echo "ADDR=[$ADDR] PD=[$PD] PING=$PING"
  ' 2>&1)
  echo "[$TS] $OUT" | tee -a "$LOG"
  if echo "$OUT" | grep -q "2405:"; then
    echo "[$TS] !!! VNE PREFIX DETECTED !!!" | tee -a "$LOG"
    break
  fi
  if echo "$OUT" | grep -q "1 received"; then
    echo "[$TS] !!! IPv6 PING WORKING !!!" | tee -a "$LOG"
    break
  fi
  sleep 60
done
