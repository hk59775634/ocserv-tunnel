# ocserv-gate-poc

**独立子项目**：Route B 数据面门禁 G1–G6 验证与交付。

与主平台解耦，仅依赖 POP 上的 ocserv 1.4.x、FreeRADIUS、pop-api 侧车。

## 门禁项

| ID | 内容 | 脚本 / 文档 |
|----|------|-------------|
| G1 | 单域名 + `select-group-by-url`，只输账号密码 | `scripts/g1-select-group-by-url.sh` |
| G2 | 热加组 + SIGHUP，不 restart，老用户不断线 | `scripts/g2-hot-add-group.sh` |
| G3 | `groupconfig=true`，RADIUS 回包 ≥2 类属性生效 | `scripts/g3-groupconfig-radius.sh` |
| G4 | 认证时序调研（TunnelGroupName 补丁落点） | `docs/G4-auth-timing.md` |
| G5 | 同私钥换证 + SIGHUP，隧道不断 | `scripts/g5-cert-reload.sh` |
| G6 | POP API：内嵌 ocserv vs occtl 侧车决策 | `docs/G6-pop-api-decision.md` |

## 快速执行

```bash
# 在 POP 主机（如 157.15.107.244）
export POP_HOST=157.15.107.244
export OCSERV_API_KEY=ocserv_route_b_pop_key_2026
bash gate-poc/scripts/run-all.sh
```

报告输出：`docs/REPORT.md`（自动生成）

## 配置策略

| Profile | 用途 | 关键选项 |
|---------|------|----------|
| **g12** | G1、G2、G5 | `config-per-group` + `groupconfig=false` |
| **g3** | G3 专项 | `groupconfig=true`，**无** `config-per-group` |

> ocserv 上游禁止 `groupconfig=true` 与 `config-per-group` 并存；G1/G2 与 G3 分 profile 验证，P1 Fork 再统一（见 G4/G6 文档）。

## 目录

```
ocserv-gate-poc/
├── README.md
├── REQUIREMENTS.md
├── configs/
│   ├── profile-g12.snippet
│   └── profile-g3.snippet
├── scripts/
│   ├── lib.sh
│   ├── run-all.sh
│   ├── g1-select-group-by-url.sh
│   ├── g2-hot-add-group.sh
│   ├── g3-groupconfig-radius.sh
│   └── g5-cert-reload.sh
└── docs/
    ├── G4-auth-timing.md
    ├── G6-pop-api-decision.md
    └── REPORT.md          # run-all 生成
```

## 依赖

- ocserv ≥ 1.3.0（推荐 1.4.2 源码安装）
- openconnect（客户端探针）
- pop-api 侧车 `:8443`
- FreeRADIUS `127.0.0.1:1812`

## 关联

- 安装脚本：仓库根目录 `scripts/prod-ocserv-install.sh`
- Fork 补丁：仓库根目录 `patches/`
