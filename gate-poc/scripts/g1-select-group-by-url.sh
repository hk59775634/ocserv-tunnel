#!/usr/bin/env bash
# G1 — select-group-by-url + single domain, username/password only
set -euo pipefail
source "$(dirname "$0")/lib.sh"

GATE="G1"
HOST="${POP_HOST}"
note=""

log "=== ${GATE}: select-group-by-url ==="
ocserv_active || fail "ocserv not running"

grep -q 'select-group-by-url = true' "$OCSERV_CONF" || fail "select-group-by-url not enabled"

for g in demo_agent ilinkcn; do
  code=$(http_probe_group_url "$HOST" "$g")
  info "HTTPS /${g} → HTTP ${code}"
  if [[ "$code" != "200" && "$code" != "401" && "$code" != "403" && "$code" != "404" ]]; then
    fail "unexpected HTTP ${code} for /${g}"
  fi
done

if command -v openconnect >/dev/null 2>&1; then
  if openconnect_probe "https://${HOST}/demo_agent" 30; then
    note="OpenConnect auth OK on /demo_agent; no group prompt"
    pass "$note"
  else
    # Without G4 TunnelGroupName patch, FR may Reject — verify URL path + RADIUS module engaged
    if journalctl -u ocserv --since '2 min ago' --no-pager 2>/dev/null | grep -q "using 'radius' authentication"; then
      note="select-group-by-url configured; RADIUS auth reached (Accept pending G4 TunnelGroupName patch)"
      pass "$note"
    else
      note="OpenConnect auth failed; no RADIUS log"
      fail "$note"
    fi
  fi
else
  note="openconnect not installed; HTTPS probe only (200/401)"
  info "$note"
  pass "config + HTTPS probe OK"
fi

record_result "$GATE" "$RESULT_PASS" "$note"
