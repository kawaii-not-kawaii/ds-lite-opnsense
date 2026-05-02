#!/bin/bash
# Manually configure IPIP Fixed IP tunnel on UDM-Pro using Asahi Net params.
set -u
IF=eth9
IID_FULL="0000:0000:0000:0000:0000:7A91:E279:0000"
REMOTE_V6="2001:0C28:0005:0300:0000:0000:0000:1011"
FIXED_V4="122.145.226.121"

# Derive local tunnel address from NGN /64 prefix + IID low-64
PREFIX=$(ip -6 -o addr show dev $IF | awk '/inet6 2/ {print $4; exit}' | cut -d/ -f1)
if [ -z "$PREFIX" ]; then echo "no IPv6 on $IF"; exit 1; fi

LOCAL_V6=$(python3 -c "
import ipaddress
prefix=ipaddress.IPv6Address('$PREFIX')
iid=ipaddress.IPv6Address('$IID_FULL')
local=(int(prefix) & (0xFFFF_FFFF_FFFF_FFFF<<64)) | (int(iid) & 0xFFFF_FFFF_FFFF_FFFF)
print(ipaddress.IPv6Address(local))
")

echo "PREFIX=$PREFIX"
echo "LOCAL_V6=$LOCAL_V6"
echo "REMOTE_V6=$REMOTE_V6"
echo "FIXED_V4=$FIXED_V4"

# Add local address to eth9 if not already (needed so tunnel can source from it)
ip -6 addr add "$LOCAL_V6/64" dev $IF 2>/dev/null || true

echo "=== reconfigure ip6tnl1 ==="
ip link set ip6tnl1 down 2>/dev/null || true
# Use mode ipip6 (ipip-over-ipv6) — this is IPv4-in-IPv6
ip -6 tunnel change ip6tnl1 mode ipip6 remote "$REMOTE_V6" local "$LOCAL_V6" encaplimit none 2>&1 || \
  ip -6 tunnel add ip6tnl1 mode ipip6 remote "$REMOTE_V6" local "$LOCAL_V6" encaplimit none
ip link set ip6tnl1 mtu 1460 up

# Remove any bogus 192.0.0.2 from the tunnel
ip addr flush dev ip6tnl1 2>/dev/null
ip addr add "$FIXED_V4/32" dev ip6tnl1

echo "=== set default v4 route via tunnel ==="
ip route del default 2>/dev/null
ip route add default dev ip6tnl1

echo "=== state ==="
ip -6 tunnel show ip6tnl1
ip addr show ip6tnl1
ip route show default

echo "=== NAT test ==="
ping -c 2 -W 2 -I ip6tnl1 8.8.8.8 2>&1 | tail -5
echo "=== our public IP ==="
curl -s --max-time 8 -4 https://ifconfig.me 2>&1
echo
