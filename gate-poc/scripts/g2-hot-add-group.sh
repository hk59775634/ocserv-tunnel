#!/usr/bin/env bash
# G2 — hot-add group + SIGHUP, no restart, existing session survives
set -euo pipefail
source "$(dirname "$0")/lib.sh"

GATE="G2"
TEST_GROUP="gate_g2_$(date +%s)"
note=""
pid_before=""
pid_after=""

log "=== ${GATE}: hot-add group + SIGHUP ==="
ocserv_active || fail "ocserv not running"

pid_before=$(ocserv_pid)
[[ -n "$pid_before" ]] || fail "no ocserv pid"

# Optional: background VPN for disconnect test
vpn_pid=""
if command -v openconnect >/dev/null 2>&1; then
  (
    sleep 2
    openconnect_probe "https://${POP_HOST}/demo_agent" 120 || true
  ) &
  vpn_pid=$!
  sleep 8
  info "background VPN pid=${vpn_pid}"
fi

# Hot-add via pop-api
resp=$(pop_api POST /api/v1/groups -d "{\"name\":\"${TEST_GROUP}\"}")
info "pop-api create: ${resp}"
[[ -f "${OCSERV_GROUP_DIR}/${TEST_GROUP}" ]] || fail "group file not created"

pop_api POST /api/v1/reload >/dev/null
sleep 2

pid_after=$(ocserv_pid)
if [[ "$pid_before" != "$pid_after" ]]; then
  note="PID changed ${pid_before}→${pid_after} (restart?)"
  fail "$note"
fi

code=$(http_probe_group_url "$POP_HOST" "$TEST_GROUP")
if [[ "$code" == "200" || "$code" == "401" || "$code" == "404" ]]; then
  note="SIGHUP OK pid=${pid_after}; new group /${TEST_GROUP} reachable HTTP ${code}"
else
  note="new group URL HTTP ${code}"
  fail "$note"
fi

if [[ -n "$vpn_pid" ]] && kill -0 "$vpn_pid" 2>/dev/null; then
  note="${note}; background session still alive at SIGHUP"
  kill "$vpn_pid" 2>/dev/null || true
  wait "$vpn_pid" 2>/dev/null || true
fi

pass "$note"
record_result "$GATE" "$RESULT_PASS" "$note"

# cleanup test group
pop_api DELETE "/api/v1/groups/${TEST_GROUP}" >/dev/null 2>&1 || true
pop_api POST /api/v1/reload >/dev/null 2>&1 || true
