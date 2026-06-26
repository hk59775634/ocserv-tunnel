#!/usr/bin/env bash
# Simulate OpenConnect XML aggregate auth (init -> auth-reply on /auth)
set -euo pipefail

HOST="${1:-127.0.0.1}"
PORT="${2:-10000}"
GROUP="${3:-demo_agent}"
USER="${4:-testuser}"
PASS="${5:-User@123}"
BASE="https://${HOST}:${PORT}"

COOKIES=$(mktemp)
INIT=$(mktemp)
AUTH=$(mktemp)
trap 'rm -f "$COOKIES" "$INIT" "$AUTH"' EXIT

echo "==> [1] XML init (group-access, POST to /)"
cat >"$INIT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<config-auth client="vpn" type="init" aggregate-auth-version="2">
<version who="vpn">v9.12</version>
<device-id>linux-64</device-id>
<group-access>${BASE}/${GROUP}</group-access>
</config-auth>
EOF

curl -sk -c "$COOKIES" -b "$COOKIES" \
  -H 'Content-Type: application/xml; charset=utf-8' \
  -H 'X-Aggregate-Auth: 1' \
  -H 'User-Agent: AnyConnect Linux' \
  -d @"$INIT" "${BASE}/" -o /tmp/oc-init.xml -w 'init_http=%{http_code}\n'
head -6 /tmp/oc-init.xml

echo "==> [2] XML auth-reply (POST to /auth)"
cat >"$AUTH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<config-auth client="vpn" type="auth-reply" aggregate-auth-version="2">
<version who="vpn">v9.12</version>
<auth>
<username>${USER}</username>
<password>${PASS}</password>
</auth>
</config-auth>
EOF

timeout 12 tcpdump -i any -nn "udp port 1812 and host 157.15.107.244" -c 2 2>&1 &
TP=$!
sleep 1
HTTP_CODE=$(curl -sk -c "$COOKIES" -b "$COOKIES" \
  -H 'Content-Type: application/xml; charset=utf-8' \
  -H 'X-Aggregate-Auth: 1' \
  -H 'User-Agent: AnyConnect Linux' \
  -d @"$AUTH" "${BASE}/auth" -o /tmp/oc-auth.xml -w '%{http_code}')
wait "$TP" 2>/dev/null || true
echo "auth_http=${HTTP_CODE}"
grep -E 'type=|auth id=' /tmp/oc-auth.xml | head -3
journalctl -u ocserv -n 6 --no-pager | grep -iE 'radius|TunnelGroup|testuser|group' || true
