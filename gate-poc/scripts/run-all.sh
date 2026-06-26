#!/usr/bin/env bash
# 运行全部 ocserv 门禁测试（G1–G6）并生成 REPORT.md
set -euo pipefail

GATE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${GATE_ROOT}/scripts/lib.sh"

SCRIPT_DIR="${GATE_ROOT}/scripts"
REPORT="${GATE_ROOT}/docs/REPORT.md"
mkdir -p "${GATE_ROOT}/docs"

OCSERV_VER=$(ocserv --version 2>&1 | head -1 || echo "未知")
HOST=$(hostname -f 2>/dev/null || hostname)

cat > "$REPORT" << EOF
# ocserv 路线 B — 门禁 POC 报告

- **日期**：$(date -Iseconds)
- **主机**：${HOST} (${POP_HOST})
- **ocserv 版本**：${OCSERV_VER}
- **子项目**：\`gate-poc/\`

## 门禁结果

| 项 | 结果 | 备注 |
|----|------|------|
EOF

overall=0

# 快照当前生产配置（G12 profile）
save_conf
write_conf_with_profile g12
restart_ocserv

run_gate() {
  local name=$1 script=$2
  log ">>> 开始 ${name}"
  if bash "$script"; then
    info "${name} 完成"
  else
    overall=1
    record_result "$name" "$RESULT_FAIL" "见脚本输出"
    log ">>> ${name} 未通过"
  fi
}

# G4/G6 为静态文档
record_g_static() {
  local gate=$1 file=$2
  if [[ -f "$file" ]]; then
    record_result "$gate" "$RESULT_PASS" "见 $(basename "$file")"
  else
    record_result "$gate" "$RESULT_FAIL" "缺少 $(basename "$file")"
    overall=1
  fi
}

run_gate G1 "${SCRIPT_DIR}/g1-select-group-by-url.sh" || true
run_gate G2 "${SCRIPT_DIR}/g2-hot-add-group.sh" || true
run_gate G3 "${SCRIPT_DIR}/g3-groupconfig-radius.sh" || true
record_g_static G4 "${GATE_ROOT}/docs/G4-auth-timing.md"
run_gate G5 "${SCRIPT_DIR}/g5-cert-reload.sh" || true
record_g_static G6 "${GATE_ROOT}/docs/G6-pop-api-decision.md"

restore_conf || true

{
  echo ""
  echo "## 总体结论"
  if [[ "$overall" -eq 0 ]]; then
    echo "- [x] **进入 P1**（ocserv Fork + TunnelGroupName 补丁）"
  else
    echo "- [ ] 部分门禁未通过，见上表"
  fi
  echo ""
  echo "## 参考"
  echo "- G4: [G4-auth-timing.md](./G4-auth-timing.md)"
  echo "- G6: [G6-pop-api-decision.md](./G6-pop-api-decision.md)"
} >> "$REPORT"

log "报告已写入: ${REPORT}"
exit "$overall"
