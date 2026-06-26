#!/usr/bin/env bash
# Route B auth smoke test on POP (URL group + username only)
set -euo pipefail

HOST="${1:-127.0.0.1}"
PORT="${2:-10000}"
GROUP="${3:-demo_agent}"
USER="${4:-testuser}"
PASS="${5:-User@123}"

# Ensure test authgroup exists (placeholder only; does not touch ocserv.conf)
if [[ ! -f "/etc/ocserv/config-per-group/${GROUP}" ]]; then
  echo "# route-b test group ${GROUP}" > "/etc/ocserv/config-per-group/${GROUP}"
  kill -HUP "$(cat /run/ocserv.pid 2>/dev/null || pgrep -x ocserv-main | head -1)" 2>/dev/null || true
  sleep 2
fi

echo "==> [1] RADIUS packet capture (expect Vendor-Specific if patch OK)"
timeout 12 tcpdump -i any -nn "udp port 1812" -c 2 2>&1 &
TP=$!
sleep 1
HTTP_CODE=$(curl -sk -o /tmp/routeb-auth-resp.xml -w '%{http_code}' \
  -X POST "https://${HOST}:${PORT}/${GROUP}" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "username=${USER}" \
  --data-urlencode "password=${PASS}")
wait "$TP" 2>/dev/null || true
echo "    HTTP ${HTTP_CODE}"
head -8 /tmp/routeb-auth-resp.xml 2>/dev/null || true

echo "==> [2] ocserv journal"
journalctl -u ocserv -n 8 --no-pager | grep -iE 'radius|TunnelGroup|auth|testuser' || true

echo "==> [3] FreeRADIUS log tail (157.15.107.244)"
ssh -o ConnectTimeout=8 -o StrictHostKeyChecking=no root@157.15.107.244 \
  'docker exec vpn-platform-freeradius tail -3 /var/log/freeradius/radius.log 2>/dev/null' \
  || echo "    (skip: cannot reach .244)"
