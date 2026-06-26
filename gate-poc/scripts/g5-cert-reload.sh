#!/usr/bin/env bash
# G5 — 同私钥换证 + SIGHUP，进程不退出
set -euo pipefail
source "$(dirname "$0")/lib.sh"

GATE="G5"
note=""
CERT_BACKUP="/tmp/ocserv-gate-g5-cert.bak"

log "=== ${GATE}: 同私钥证书热更新 ==="
ocserv_active || fail "ocserv 未运行"

pid_before=$(ocserv_pid)
fp_before=$(cert_fingerprint "$OCSERV_CERT")
cp -a "$OCSERV_CERT" "$CERT_BACKUP"

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
[[ "$fp_before" != "$fp_after" ]] || fail "换证后证书指纹未变化"

pop_api POST /api/v1/reload >/dev/null
sleep 2

pid_after=$(ocserv_pid)
ocserv_active || fail "证书热更新后 ocserv 崩溃"

if [[ "$pid_before" != "$pid_after" ]]; then
  note="SIGHUP 后 PID 变化，可能发生 restart"
  fail "$note"
fi

note="SIGHUP 成功 pid=${pid_after}；证书指纹 ${fp_before}→${fp_after}"
pass "$note"
record_result "$GATE" "$RESULT_PASS" "$note"

cp -a "$CERT_BACKUP" "$OCSERV_CERT"
pop_api POST /api/v1/reload >/dev/null 2>&1 || true
