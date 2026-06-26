#!/usr/bin/env bash
# Install ocserv on Route B POP (157.15.107.244)
# Ubuntu apt ships 1.2.4 without select-group-by-url — builds 1.2.7 from source when needed.
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
RADIUS_SECRET="${RADIUS_SECRET:-testing123}"
RADIUS_HOST="${RADIUS_HOST:-127.0.0.1}"
RADIUS_PORT="${RADIUS_PORT:-1812}"
OCSERV_TCP_PORT="${OCSERV_TCP_PORT:-443}"
VPN_SUBNET="${VPN_SUBNET:-192.168.100.0/24}"
OCSERV_VERSION="${OCSERV_VERSION:-1.4.2}"

export DEBIAN_FRONTEND=noninteractive

need_source_build() {
  if ! command -v ocserv >/dev/null 2>&1; then
    return 0
  fi
  local ver
  ver="$(ocserv --version 2>&1 | awk '{print $4}')"
  # select-group-by-url requires >= 1.3.0; Ubuntu apt ships 1.2.4
  dpkg --compare-versions "${ver}" ge "1.3.0" 2>/dev/null && return 1
  return 0
}

echo "==> Base packages"
apt-get update
apt-get install -y libradcli4 gnutls-bin openssl

if need_source_build; then
  echo "==> Building ocserv ${OCSERV_VERSION} (apt too old for select-group-by-url)"
  bash "${ROOT}/scripts/build-ocserv.sh"
else
  echo "==> ocserv $(ocserv --version 2>&1 | head -1) OK"
  apt-get install -y ocserv || true
fi

echo "==> TLS certificate (self-signed POC)"
install -d -m 0755 /etc/ocserv/certs
if [[ ! -f /etc/ocserv/certs/server-cert.pem ]]; then
  certtool --generate-privkey --outfile /etc/ocserv/certs/server-key.pem
  cat > /tmp/ocserv-cert.tmpl << 'TMPL'
cn = "vpn-pop.local"
organization = "VPN Platform"
expiration_days = 825
signing_key
encryption_key
tls_www_server
TMPL
  certtool --generate-self-signed \
    --load-privkey /etc/ocserv/certs/server-key.pem \
    --template /tmp/ocserv-cert.tmpl \
    --outfile /etc/ocserv/certs/server-cert.pem
  chmod 600 /etc/ocserv/certs/server-key.pem
  chmod 644 /etc/ocserv/certs/server-cert.pem
fi

echo "==> Platform snippet"
install -d /etc/ocserv/ocserv.d /etc/ocserv/config-per-group
install -m 0644 "${ROOT}/configs/vpn-platform.conf" /etc/ocserv/ocserv.d/vpn-platform.conf

for g in demo_agent ilinkcn routebtest sslauto1; do
  [[ -f "/etc/ocserv/config-per-group/${g}" ]] || echo "# managed by vpn-platform" > "/etc/ocserv/config-per-group/${g}"
done

echo "==> radcli → FreeRADIUS (${RADIUS_HOST}:${RADIUS_PORT})"
install -d /etc/radcli
install -m 0644 "${ROOT}/configs/radcli/dictionary.vpnplatform" /etc/radcli/dictionary.vpnplatform
if [[ -f /etc/radcli/dictionary ]]; then
  grep -q dictionary.vpnplatform /etc/radcli/dictionary || \
    echo 'INCLUDE /etc/radcli/dictionary.vpnplatform' >> /etc/radcli/dictionary
else
  cat > /etc/radcli/dictionary << 'EOF'
INCLUDE /etc/radcli/dictionary.compat
INCLUDE /etc/radcli/dictionary.microsoft
INCLUDE /etc/radcli/dictionary.vpnplatform
EOF
fi
if [[ ! -f /etc/radcli/radiusclient.conf ]]; then
  cat > /etc/radcli/radiusclient.conf << EOF
authserver     ${RADIUS_HOST}:${RADIUS_PORT}
acctserver     ${RADIUS_HOST}:${RADIUS_PORT}
servers        /etc/radcli/servers
dictionary     /etc/radcli/dictionary
default_realm
radius_timeout 10
radius_retries 3
EOF
else
  sed -i "s|^authserver.*|authserver     ${RADIUS_HOST}:${RADIUS_PORT}|" /etc/radcli/radiusclient.conf
  sed -i "s|^acctserver.*|acctserver     ${RADIUS_HOST}:${RADIUS_PORT}|" /etc/radcli/radiusclient.conf
fi
cat > /etc/radcli/servers << EOF
${RADIUS_HOST}    ${RADIUS_SECRET}
EOF
chmod 600 /etc/radcli/servers

echo "==> ocserv.conf"
cat > /etc/ocserv/ocserv.conf << EOF
# VPN Platform Route B — prod-ocserv-install.sh
auth-timeout = 240
ban-time = 300
max-ban-score = 80
ban-reset-time = 1200
tcp-port = ${OCSERV_TCP_PORT}
udp-port = ${OCSERV_TCP_PORT}
run-as-user = ocserv
run-as-group = ocserv
socket-file = /run/ocserv.socket
pid-file = /run/ocserv.pid
device = vpns
predictable-ips = true
default-domain = vpn.local
ipv4-network = ${VPN_SUBNET}
dns = 1.1.1.1
dns = 8.8.8.8
tunnel-all-dns = true
keepalive = 32400
dpd = 90
mobile-dpd = 1800
switch-to-tcp-timeout = 25
try-mtu-discovery = true
server-cert = /etc/ocserv/certs/server-cert.pem
server-key = /etc/ocserv/certs/server-key.pem
tls-priorities = "NORMAL:%SERVER_PRECEDENCE:%COMPAT:-VERS-SSL3.0:-VERS-TLS1.0:-VERS-TLS1.1"
max-clients = 512
max-same-clients = 128
rate-limit-ms = 100
cisco-client-compat = true
dtls-legacy = true

# VPN Platform Route B (from ocserv.d/vpn-platform.conf — inlined, no include= in 1.4.x)
select-group-by-url = true
auto-select-group = true
config-per-group = /etc/ocserv/config-per-group/
auth = "radius[config=/etc/radcli/radiusclient.conf,nas-identifier=pop-default]"
EOF

echo "==> IP forwarding"
grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.d/99-vpn-platform.conf 2>/dev/null || \
  echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-vpn-platform.conf
sysctl -p /etc/sysctl.d/99-vpn-platform.conf >/dev/null || true

echo "==> Config test"
ocserv -t -c /etc/ocserv/ocserv.conf 2>&1 || ocserv --test-config -c /etc/ocserv/ocserv.conf 2>&1 || true

echo "==> Start ocserv"
systemctl enable ocserv
systemctl restart ocserv
sleep 3
systemctl is-active ocserv
systemctl status ocserv --no-pager | head -15

echo "==> Verify"
ss -tlnp | grep ":${OCSERV_TCP_PORT}" || true
if [[ -f /run/ocserv.pid ]]; then
  echo "pid=$(cat /run/ocserv.pid)"
  ln -sf /run/ocserv.pid /var/run/ocserv.pid 2>/dev/null || cp -f /run/ocserv.pid /var/run/ocserv.pid
fi
occtl show status 2>/dev/null || true

echo "==> pop-api status"
curl -sf -H "X-API-Key: ocserv_route_b_pop_key_2026" http://127.0.0.1:8443/api/v1/status || true
echo
echo "Done. Test: openconnect https://$(hostname -I | awk '{print $1}')/demo_agent -u testuser"
