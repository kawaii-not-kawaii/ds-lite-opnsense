#!/bin/bash
# Cycle MACs on UDM eth9 and check which prefix the ISP delegates.
# Run via: ssh root@192.168.0.1 'bash -s' < mac_cycle.sh

set -u
IF=eth9
LOG=/tmp/mac_cycle.log
: > "$LOG"

# Candidate MACs. Keep OUI locally-administered (02:xx) for randoms.
MACS=(
  "f4:92:bf:8f:18:f2"  # original hardware MAC
  "02:11:22:33:44:55"
  "02:aa:bb:cc:dd:01"
  "02:de:ad:be:ef:01"
  "b4:fb:e4:12:34:56"  # NTT-ish OUI
  "00:03:7f:aa:bb:cc"  # Atheros
  "f4:92:bf:8f:18:fa"  # current spoofed (restore)
)

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

for MAC in "${MACS[@]}"; do
  log "===== trying MAC=$MAC ====="
  pkill -9 odhcp6c 2>/dev/null
  sleep 1
  ip link set "$IF" down
  ip -6 addr flush dev "$IF" scope global 2>/dev/null
  ip link set "$IF" address "$MAC"
  ip link set "$IF" up
  sleep 2
  # odhcp6c should be respawned by supervisor; if not, start it
  if ! pgrep -f "odhcp6c.*$IF" >/dev/null; then
    /usr/sbin/odhcp6c -e -v -s /usr/share/ubios-udapi-server/ubios-odhcp6c-script -D -k -P 56 "$IF" &
    log "spawned odhcp6c manually"
  fi
  # Wait up to 45s for prefix
  for i in $(seq 1 15); do
    sleep 3
    ADDR=$(ip -6 addr show "$IF" | awk '/inet6 2/ {print $2; exit}')
    [ -n "$ADDR" ] && break
  done
  ADDR=$(ip -6 addr show "$IF" | awk '/inet6 2/ {print $2}' | tr '\n' ' ')
  PD=$(ip -6 route show dev "$IF" | grep -v fe80 | head -5 | tr '\n' '|')
  PING=$(ping6 -c 1 -W 2 2404:6800:400a:1000::9a 2>&1 | grep -Eo '[0-9]+ received' || echo "no-reply")
  log "MAC=$MAC ADDR=[$ADDR] ROUTES=[$PD] PING=$PING"
  if echo "$ADDR" | grep -q "2405:"; then
    log "!!!!! GOT VNE PREFIX on MAC=$MAC !!!!!"
    break
  fi
done

log "===== done ====="
