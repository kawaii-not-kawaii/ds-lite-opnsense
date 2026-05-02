#!/bin/bash
# Run on UDM-Pro to enable IPIP Fixed IP.
set -u
USER_ID="P25290523"
PASS="ODQJALQO"
IF=eth9
STATE=/data/udapi-config/ubios-udapi-server/ubios-udapi-server.state

mkdir -p /run/hb46pp
chmod 700 /run/hb46pp
printf '%s' "$USER_ID" > /run/hb46pp/$IF.user
printf '%s' "$PASS"    > /run/hb46pp/$IF.pass
chmod 600 /run/hb46pp/$IF.*

cp "$STATE" "$STATE.bak.$(date +%s)"

python3 - <<PYEOF
import json, sys
p = "$STATE"
d = json.load(open(p))
hb = d["interfaces"][12]["ipv6"].setdefault("hb46pp", {})
hb["capability"] = "ipip"
hb["enabled"] = True
hb["authentication"] = {"user": "$USER_ID", "password": "$PASS"}
json.dump(d, open(p, "w"), indent=2)
print("state patched: capability=ipip, auth set")
PYEOF

echo "=== killing old hb46pp ==="
pkill -f "ubnt-hb46pp" 2>/dev/null || true
sleep 1

echo "=== running ubnt-hb46pp ipip $IF -1 -x ==="
timeout 60 /usr/bin/ubnt-hb46pp ipip "$IF" -1 -x 2>&1 | tail -40
RC=$?
echo "=== rc=$RC ==="
echo "=== /run/hb46pp/$IF.json ==="
cat /run/hb46pp/$IF.json 2>/dev/null || echo "(no json yet)"
echo "=== ip6tnl1 ==="
ip -6 tunnel show ip6tnl1
echo "=== ip6tnl1 routes ==="
ip route show dev ip6tnl1 2>/dev/null
