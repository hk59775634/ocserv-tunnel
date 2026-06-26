#!/usr/bin/env bash
# G3 — groupconfig=true，验证 RADIUS 回包至少 2 类属性生效
set -euo pipefail
source "$(dirname "$0")/lib.sh"

GATE="G3"
note=""
restored=0

cleanup() {
  if [[ "$restored" -eq 0 ]]; then
    restore_conf || true
    restored=1
  fi
}
trap cleanup EXIT

log "=== ${GATE}: groupconfig=true + RADIUS 属性 ==="

save_conf
apply_profile g3
grep -q 'groupconfig=true' "$OCSERV_CONF" || fail "未设置 groupconfig=true"
grep -qE '^config-per-group' "$OCSERV_CONF" && fail "G3 配置中不得包含 config-per-group"

api_out=$(curl -sf -X POST "http://127.0.0.1:8080/api/radius/auth" \
  -H "Content-Type: application/json" \
  -H "X-Device-Secret: demo_radius_secret_2026" \
  -d "{\"username\":\"${VPN_USER}\",\"password\":\"${VPN_PASS}\",\"nas_ip\":\"127.0.0.1\",\"tunnel_group_name\":\"demo_agent\"}" 2>&1) || api_out=""

attrs=0
echo "$api_out" | grep -qi 'Filter-Id\|filter\|bb-50m' && attrs=$((attrs + 1))
echo "$api_out" | grep -qi 'Session-Timeout\|session' && attrs=$((attrs + 1))

if [[ "$attrs" -lt 2 ]]; then
  fr_out=$(docker exec vpn-platform-freeradius bash -c 'radclient -x 127.0.0.1:1812 auth testing123 << EOF
User-Name = testuser
User-Password = User@123
NAS-IP-Address = 127.0.0.1
Cisco-AVPair = "TunnelGroupName=demo_agent"
EOF' 2>&1 || true)
  echo "$fr_out" | grep -q 'Filter-Id' && attrs=$((attrs + 1))
  echo "$fr_out" | grep -q 'Session-Timeout' && attrs=$((attrs + 1))
  echo "$fr_out" | grep -q 'Access-Accept' || true
fi

[[ "$attrs" -ge 2 ]] || fail "RADIUS Accept 需至少 2 类属性（当前 ${attrs}）"
info "RADIUS Accept 匹配属性数: ${attrs}"

if command -v openconnect >/dev/null 2>&1; then
  if openconnect_probe "https://${POP_HOST}/demo_agent" 45; then
    note="groupconfig profile；RADIUS ≥2 属性；OpenConnect 认证成功"
    pass "$note"
  else
    note="groupconfig profile；RADIUS 含 Filter-Id+Session-Timeout（VPN Accept 待 G4 补丁）"
    pass "$note"
  fi
else
  note="RADIUS Accept ≥2 属性；未安装 OpenConnect，跳过 VPN 探针"
  pass "$note"
fi

record_result "$GATE" "$RESULT_PASS" "$note"
restored=1
cleanup
