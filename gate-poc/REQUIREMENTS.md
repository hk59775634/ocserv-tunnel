# ocserv 门禁需求 — G1～G6

> 子项目 `gate-poc` 验收标准。通过定义见各脚本 exit code 与 `docs/REPORT.md`。

## G1 — select-group-by-url + 单域名

**需求**

- `select-group-by-url = true`
- 连接 `https://{pop}/{access_key}` 与另一 access_key，**不出现组下拉框**
- 用户仅输入 username + password

**验收**

- OpenConnect 连 `/demo_agent`、`/ilinkcn` 均成功，日志无组选择提示
- HTTPS 探针确认 URL 路径被 ocserv 接受

---

## G2 — 热加组 + SIGHUP

**需求**

| 步骤 | 操作 | 期望 |
|------|------|------|
| 1 | 用户 A 连 `/a`，长 ping | 稳定 |
| 2 | 不 restart，新增 `config-per-group/c` + SIGHUP | 主进程不退出 |
| 3 | 用户 A ping | 不中断（≤1 DPD 周期抖动可接受） |
| 4 | 新用户连 `/c` | 认证走到 RADIUS |

**验收**

- SIGHUP 前后 `ocserv-main` PID 不变
- pop-api `POST /api/v1/groups` + reload 成功
- 新组 URL 可发起认证

---

## G3 — groupconfig=true + RADIUS 回包

**需求**

- `auth = "radius[...,groupconfig=true,...]"`
- Access-Accept 至少 **2 类**属性在 ocserv 侧生效（Filter-Id、Session-Timeout、DNS 等）

**约束**

- 与 `config-per-group` 互斥 → 使用 **profile-g3** 独立验证

**验收**

- `occtl show users` 或 debug log 可见 RADIUS 下发的属性

---

## G4 — TunnelGroupName 认证时序（调研）

**需求**

- 确认 URL 选定 authgroup **是否早于** RADIUS Access-Request
- 明确 P1 补丁文件 + 函数落点

**交付**

- `docs/G4-auth-timing.md`（不阻塞 G1～G3 自动化）

---

## G5 — 同私钥换证 + SIGHUP

**需求**

| 步骤 | 操作 | 期望 |
|------|------|------|
| 1 | 用户在线 | 稳定 |
| 2 | 同路径覆盖 `server-cert.pem`（私钥不变） | — |
| 3 | SIGHUP | 无 crash |
| 4 | 老会话 | 不中断 |
| 5 | 新连接 | 信任新证书 |

**验收**

- SIGHUP 后 PID 不变；新 cert fingerprint 与旧不同

---

## G6 — POP API 形态决策

**需求**

| 方案 | 说明 |
|------|------|
| P1 内嵌 ocserv | HTTP 管理口在 ocserv 进程内 |
| P2 occtl 侧车 | 独立 pop-api，filesystem + SIGHUP + occtl |

**交付**

- `docs/G6-pop-api-decision.md` 含选定方案、理由、P1 额外人天估算

---

## P1 启动条件（引用主清单）

1. G1、G2、G3、G5 = 通过
2. G6 已选定 P1 或 P2
3. G4 无「不可实现」结论
