# G6 — POP API 形态决策

> **日期**：2026-06-26  
> **决策人**：ocserv-gate-poc 子项目  
> **状态**：**已选定 P2（occtl 侧车）**

---

## 1. 方案对比

| 维度 | P1 内嵌 ocserv | P2 occtl 侧车（当前） |
|------|----------------|----------------------|
| 部署单元 | 单二进制 ocserv + HTTP | `ocserv-pop-api` systemd + ocserv |
| 组热加 | 直接写配置 + SIGHUP | pop-api 写 `config-per-group` + SIGHUP ✅ |
| 证书热更 | 写 PEM + SIGHUP | `PUT /api/v1/certificate` ✅ |
| 按组踢线 | sec-mod IPC 原生 | 侧车需 `occtl` / 未来 P1 补丁 |
| 开发量 | Fork + sec-mod HTTP + IPC：**+8～12 人日** | **已实现**（`pop-api/main.go`） |
| 运维 | 单进程 | 双进程（ocserv + pop-api） |
| Worker 契约 | 同一 OpenAPI | 同一 OpenAPI ✅ |

---

## 2. 评估过程

### P1 内嵌 — 复杂度

1. **HTTP 管理口**：需在 ocserv main/sec-mod 增加 listener（:8443），与 VPN :443 隔离。
2. **踢线接口**：`disconnect-all-by-group` 需 sec-mod → worker IPC，涉及 `ctl` protobuf 扩展。
3. **安全**：API Key、TLS、mTLS 与 GPL 分发合规。
4. **预估**：在 | 1.5～2 周（含测试），高于 POC 阶段预算。

### P2 侧车 — 已验证能力

| API | 157.15.107.244 状态 |
|-----|---------------------|
| `GET /api/v1/status` | ✅ `running: true` |
| `POST /api/v1/reload` | ✅ SIGHUP |
| `POST /api/v1/groups` | ✅ 热加组 |
| `PUT /api/v1/certificate` | ✅ 已实现（G5 脚本验证） |
| `POST .../disconnect-all` | ⚠️ 依赖 occtl socket（1.4.2 路径 `/run/ocserv.socket.*`） |

平台 Worker `device_api_actions` **已对接 P2**，无需改控制面。

---

## 3. 决策

```
选定方案：P2（occtl 侧车）
理由：
  1. POC/M0 已部署且通过 G2/G5 reload 验证；
  2. P1 内嵌预估 +8～12 人日，不阻塞 Route B 控制面上线；
  3. OpenAPI 契约一致，后续可无缝替换为 P1 内嵌实现；
  4. 踢线能力可 P1.1 通过 occtl 适配或 Fork SPEC-02 补齐。

预估 P1 额外人天：8～12（若未来合并内嵌 API）
P2 维护成本：低（单 Go 二进制，无 ocserv 重编译）
```

---

## 4. 后续路线

| 阶段 | 动作 |
|------|------|
| **M0（当前）** | 维持 P2；G1–G5 用侧车 SIGHUP |
| **P1** | Fork + TunnelGroupName（G4）；踢线可先 `occtl disconnect` 封装 |
| **P2+（可选）** | SPEC-02 内嵌 HTTP，侧车退役 |

---

## 5. G6 结论

**✅ PASS — 采用 P2 occtl 侧车，P1 内嵌列为可选增强，不阻塞立项。**
