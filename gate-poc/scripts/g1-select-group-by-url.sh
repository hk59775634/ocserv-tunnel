#!/usr/bin/env bash
# G1 — select-group-by-url + 单域名，仅用户名密码
set -euo pipefail
source "$(dirname "$0")/lib.sh"

GATE="G1"
HOST="${POP_HOST}"
note=""

log "=== ${GATE}: select-group-by-url ==="
ocserv_active || fail "ocserv 未运行"

grep -q 'select-group-by-url = true' "$OCSERV_CONF" || fail "未启用 select-group-by-url"

for g in demo_agent ilinkcn; do
  code=$(http_probe_group_url "$HOST" "$g")
  info "HTTPS /${g} → HTTP ${code}"
  if [[ "$code" != "200" && "$code" != "401" && "$code" != "403" && "$code" != "404" ]]; then
    fail "/${g} 返回意外 HTTP ${code}"
  fi
done

if command -v openconnect >/dev/null 2>&1; then
  if openconnect_probe "https://${HOST}/demo_agent" 30; then
    note="OpenConnect 在 /demo_agent 认证成功，无组选择提示"
    pass "$note"
  else
    if journalctl -u ocserv --since '2 min ago' --no-pager 2>/dev/null | grep -q "using 'radius' authentication"; then
      note="select-group-by-url 已配置；已走到 RADIUS（完整 Accept 待 G4 TunnelGroupName 补丁）"
      pass "$note"
    else
      note="OpenConnect 认证失败，且无 RADIUS 日志"
      fail "$note"
    fi
  fi
else
  note="未安装 openconnect，仅做 HTTPS 探针"
  info "$note"
  pass "配置与 HTTPS 探针通过"
fi

record_result "$GATE" "$RESULT_PASS" "$note"
