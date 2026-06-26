#!/usr/bin/env bash
# G5 — same private key, replace cert + SIGHUP, process survives
set -euo pipefail
source "$(dirname "$0")/lib.sh"

GATE="G5"
note=""
CERT_BACKUP="/tmp/ocserv-gate-g5-cert.bak"

log "=== ${GATE}: cert reload same private key ==="
ocserv_active || fail "ocserv not running"

pid_before=$(ocserv_pid)
fp_before=$(cert_fingerprint "$OCSERV_CERT")
cp -a "$OCSERV_CERT" "$CERT_BACKUP"

# Re-issue cert with same key, different validity (new serial)
cat > /tmp/g5-cert.tmpl << 'TMPL'
cn = "vpn-pop-g5-reload"
organization = "VPN Platform G5"
expiration_days = 800
signing_key
encryption_key
tls_www_server
TMPL

certtool --generate-self-signed \
  --load-privkey "$OCSERV_KEY" \
  --template /tmp/g5-cert.tmpl \
  --outfile "$OCSERV_CERT"

fp_after=$(cert_fingerprint "$OCSERV_CERT")
[[ "$fp_before" != "$fp_after" ]] || fail "fingerprint unchanged after reissue"

pop_api POST /api/v1/reload >/dev/null
sleep 2

pid_after=$(ocserv_pid)
ocserv_active || fail "ocserv crashed after cert reload"

if [[ "$pid_before" != "$pid_after" ]]; then
  note="PID changed after SIGHUP — possible restart"
  fail "$note"
fi

note="SIGHUP OK pid=${pid_after}; cert ${fp_before}→${fp_after}"
pass "$note"
record_result "$GATE" "$RESULT_PASS" "$note"

# restore original cert for production
cp -a "$CERT_BACKUP" "$OCSERV_CERT"
pop_api POST /api/v1/reload >/dev/null 2>&1 || true
