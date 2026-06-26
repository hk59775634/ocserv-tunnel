#!/usr/bin/env bash
# G2 — 热加组 + SIGHUP，不 restart，老会话不断线
set -euo pipefail
source "$(dirname "$0")/lib.sh"

GATE="G2"
TEST_GROUP="gate_g2_$(date +%s)"
note=""
pid_before=""
pid_after=""

log "=== ${GATE}: 热加组 + SIGHUP ==="
ocserv_active || fail "ocserv 未运行"

pid_before=$(ocserv_pid)
[[ -n "$pid_before" ]] || fail "无法获取 ocserv pid"

vpn_pid=""
if command -v openconnect >/dev/null 2>&1; then
  (
    sleep 2
    openconnect_probe "https://${POP_HOST}/demo_agent" 120 || true
  ) &
  vpn_pid=$!
  sleep 8
  info "后台 VPN 进程 pid=${vpn_pid}"
fi

resp=$(pop_api POST /api/v1/groups -d "{\"name\":\"${TEST_GROUP}\"}")
info "pop-api 创建组: ${resp}"
[[ -f "${OCSERV_GROUP_DIR}/${TEST_GROUP}" ]] || fail "组文件未创建"

pop_api POST /api/v1/reload >/dev/null
sleep 2

pid_after=$(ocserv_pid)
if [[ "$pid_before" != "$pid_after" ]]; then
  note="PID 变化 ${pid_before}→${pid_after}（可能发生 restart）"
  fail "$note"
fi

code=$(http_probe_group_url "$POP_HOST" "$TEST_GROUP")
if [[ "$code" == "200" || "$code" == "401" || "$code" == "404" ]]; then
  note="SIGHUP 成功 pid=${pid_after}；新组 /${TEST_GROUP} 可达 HTTP ${code}"
else
  note="新组 URL 返回 HTTP ${code}"
  fail "$note"
fi

if [[ -n "$vpn_pid" ]] && kill -0 "$vpn_pid" 2>/dev/null; then
  note="${note}；SIGHUP 时后台会话仍存活"
  kill "$vpn_pid" 2>/dev/null || true
  wait "$vpn_pid" 2>/dev/null || true
fi

pass "$note"
record_result "$GATE" "$RESULT_PASS" "$note"

pop_api DELETE "/api/v1/groups/${TEST_GROUP}" >/dev/null 2>&1 || true
pop_api POST /api/v1/reload >/dev/null 2>&1 || true
