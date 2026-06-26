#!/usr/bin/env bash
# Shared helpers for ocserv-gate-poc
set -euo pipefail

GATE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export GATE_ROOT

POP_HOST="${POP_HOST:-127.0.0.1}"
POP_API_URL="${POP_API_URL:-http://127.0.0.1:8443}"
OCSERV_API_KEY="${OCSERV_API_KEY:-ocserv_route_b_pop_key_2026}"
OCSERV_CONF="${OCSERV_CONF:-/etc/ocserv/ocserv.conf}"
OCSERV_PID_FILE="${OCSERV_PID_FILE:-/run/ocserv.pid}"
OCSERV_CERT="${OCSERV_CERT:-/etc/ocserv/certs/server-cert.pem}"
OCSERV_KEY="${OCSERV_KEY:-/etc/ocserv/certs/server-key.pem}"
OCSERV_GROUP_DIR="${OCSERV_GROUP_DIR:-/etc/ocserv/config-per-group}"
VPN_USER="${VPN_USER:-testuser}"
VPN_PASS="${VPN_PASS:-User@123}"
CERT_PIN="${CERT_PIN:-pin-sha256:+hKBZZFU9ou9kc01OAYtUQQPpjeB9kkaQp3X3mhDzpE=}"
CONF_SNAPSHOT="/tmp/ocserv-gate-poc.snapshot"

RESULT_PASS="PASS"
RESULT_FAIL="FAIL"
RESULT_SKIP="SKIP"
RESULT_INFO="INFO"

log() { echo "[$(date -Iseconds)] $*"; }
pass() { log "PASS: $*"; }
fail() { log "FAIL: $*"; return 1; }
info() { log "INFO: $*"; }

ocserv_pid() {
  if [[ -f "$OCSERV_PID_FILE" ]]; then
    cat "$OCSERV_PID_FILE"
  else
    pgrep -x ocserv-main || true
  fi
}

ocserv_active() {
  systemctl is-active --quiet ocserv
}

pop_api() {
  local method=$1 path=$2
  shift 2
  curl -sf -X "$method" \
    -H "X-API-Key: ${OCSERV_API_KEY}" \
    -H "Content-Type: application/json" \
    "$POP_API_URL${path}" "$@"
}

write_conf_with_profile() {
  local profile=$1
  local snippet="${GATE_ROOT}/configs/profile-${profile}.snippet"
  local base="${GATE_ROOT}/configs/ocserv-base.conf"
  [[ -f "$snippet" ]] || fail "missing ${snippet}"
  [[ -f "$base" ]] || fail "missing ${base}"
  cat "$base" > "$OCSERV_CONF"
  echo "" >> "$OCSERV_CONF"
  echo "# Profile ${profile} — ocserv-gate-poc" >> "$OCSERV_CONF"
  cat "$snippet" >> "$OCSERV_CONF"
}

save_conf() {
  cp -a "$OCSERV_CONF" "$CONF_SNAPSHOT"
}

restore_conf() {
  if [[ -f "$CONF_SNAPSHOT" ]]; then
    cp -a "$CONF_SNAPSHOT" "$OCSERV_CONF"
    restart_ocserv
  fi
}

restart_ocserv() {
  if ! ocserv -t -c "$OCSERV_CONF" >/dev/null 2>&1; then
    ocserv --test-config -c "$OCSERV_CONF" >/dev/null 2>&1 || fail "invalid ocserv.conf"
  fi
  systemctl restart ocserv
  sleep 3
  ocserv_active || fail "ocserv not active"
}

apply_profile() {
  local profile=$1
  write_conf_with_profile "$profile"
  restart_ocserv
}

restore_profile() {
  restore_conf
}

cert_fingerprint() {
  openssl x509 -in "$1" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2
}

openconnect_probe() {
  local url=$1
  local timeout_sec=${2:-25}
  local out rc
  if command -v script >/dev/null 2>&1; then
    out=$(script -q -c "printf '%s\n' '${VPN_PASS}' | timeout ${timeout_sec} openconnect '${url}' -u '${VPN_USER}' --servercert='${CERT_PIN}' --passwd-on-stdin --authenticate" /dev/null 2>&1) || true
  else
    out=$(printf '%s\n' "$VPN_PASS" | timeout "$timeout_sec" openconnect "$url" \
      -u "$VPN_USER" --servercert="$CERT_PIN" --passwd-on-stdin --authenticate 2>&1) || true
  fi
  echo "$out" | grep -qi 'Login failed\|Authentication failed' && return 1
  echo "$out" | grep -qi 'Got CONNECT response\|CSTP connected\|Authentication succeeded' && return 0
  return 1
}

http_probe_group_url() {
  local host=$1 group=$2
  local code
  code=$(curl -sk -o /dev/null -w '%{http_code}' --connect-timeout 5 \
    "https://${host}/${group}" || echo "000")
  echo "$code"
}

record_result() {
  local gate=$1 result=$2 note=$3
  echo "| ${gate} | ${result} | ${note} |" >> "${GATE_ROOT}/docs/REPORT.md"
}
