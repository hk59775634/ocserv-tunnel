# ocserv 路线 B — 门禁 POC 报告

- **日期**：2026-06-26T03:32:44+00:00
- **主机**：157.15.107.244 (ubuntu)
- **ocserv 版本**：OpenConnect VPN Server 1.4.2
- **子项目**：`services/ocserv-gate-poc`

## 门禁结果

| 项 | 结果 | 备注 |
|----|------|------|
| G1 | PASS | `select-group-by-url` 已启用；HTTPS `/demo_agent`/`/ilinkcn` 可达；RADIUS 模块已触发（完整 Accept 待 G4 补丁） |
| G2 | PASS | pop-api 热加组 + SIGHUP；PID 不变；新组 URL 可达 |
| G3 | PASS | profile-g3 + `groupconfig=true`；RADIUS Accept 含 Filter-Id + Session-Timeout |
| G4 | PASS | 见 [G4-auth-timing.md](./G4-auth-timing.md) |
| G5 | PASS | 同私钥换证 + SIGHUP；PID 不变；指纹已变更 |
| G6 | PASS | 选定 **P2 侧车**，见 [G6-pop-api-decision.md](./G6-pop-api-decision.md) |

## 总体结论

- [x] **进入 P1**（ocserv-vpnplatform Fork + TunnelGroupName 补丁）
- **已知限制**：原生 ocserv 未发 VSA 146，OpenConnect 全链路 Accept 依赖 P1 补丁；G1/G2/G5 控制面与 reload 已验证

## 复测

```bash
export POP_HOST=127.0.0.1 OCSERV_API_KEY=ocserv_route_b_pop_key_2026
bash /opt/vpn-platform/services/ocserv-gate-poc/scripts/run-all.sh
```

## 参考

- [G4-auth-timing.md](./G4-auth-timing.md)
- [G6-pop-api-decision.md](./G6-pop-api-decision.md)
- [REQUIREMENTS.md](../REQUIREMENTS.md)
