# ocserv 路线 B — 门禁 POC 报告

- **日期**：2026-06-26
- **控制面**：157.15.107.244 (ubuntu)
- **数据面 POP**：157.15.107.12 (ubuntu, qosnatd 管理配置)
- **ocserv 版本**：OpenConnect VPN Server 1.4.2（SPEC-01 补丁）
- **子项目**：`gate-poc/`

## 门禁结果

| 项 | 结果 | 备注 |
|----|------|------|
| G1 | 通过 | `select-group-by-url`；HTTPS `/demo_agent`/`/ilinkcn` 可达 |
| G2 | 通过 | pop-api 热加组 + SIGHUP；PID 不变 |
| G3 | 通过 | profile-g3 + `groupconfig=true`；RADIUS Accept 含 Filter-Id |
| G4 | 通过 | SPEC-01 补丁已落地；见 [G4-auth-timing.md](./G4-auth-timing.md) |
| G5 | 通过 | 同私钥换证 + SIGHUP；PID 不变 |
| G6 | 通过 | 选定 **P2 侧车** |

## SPEC-01 端到端（POP .12，2026-06-26）

| 测试 | 结果 |
|------|------|
| curl `POST /{access_key}` + 用户名密码 | RADIUS Accept，HTTP `type=complete` |
| OpenConnect `--authenticate` | 获取 `webvpn` cookie |
| OpenConnect 完整隧道（WSL） | `CSTP connected`，分配 `10.250.0.x`，ping 网关 OK |
| FreeRADIUS 1812 | Access-Request 含 TunnelGroupName VSA（包长 107–136 字节） |
| FreeRADIUS 1813 | Accounting-Start 含 TunnelGroupName（补丁 `acct/radius.c`） |

## 总体结论

- [x] **SPEC-01 完成** — Route B 数据面认证 + 隧道已在生产 POP 验证
- [x] **进入平台集成** — 控制面 157.15.107.244 Route B API / FreeRADIUS 联调通过

## 复测

```bash
# 门禁
export POP_HOST=127.0.0.1 OCSERV_API_KEY=ocserv_route_b_pop_key_2026
bash gate-poc/scripts/run-all.sh

# Route B 冒烟（POP 本机）
bash scripts/test-route-b-auth.sh 127.0.0.1 10000 demo_agent testuser 'User@123'

# OpenConnect 客户端
openconnect https://POP:PORT/demo_agent -u testuser --authgroup=demo_agent \
  --servercert=pin-sha256:... --no-dtls
```

## 参考

- [G4-auth-timing.md](./G4-auth-timing.md)
- [G6-pop-api-decision.md](./G6-pop-api-decision.md)
- [REQUIREMENTS.md](../REQUIREMENTS.md)
- [patches/README.md](../../patches/README.md)
