# ocserv-tunnel

基于 [ocserv](https://gitlab.com/openconnect/ocserv) 的多租户 SSL VPN POP 节点，面向 VPN 平台的 **Route B** 数据面集成。

单域名 + `select-group-by-url`（`https://{pop域名}/{access_key}`）、RADIUS `TunnelGroupName`（Cisco VSA 146）、SIGHUP 热加组、POP 管理 API 侧车。

## 功能

- **URL 选组** — 等价 ASAv `group-url`，通过 `select-group-by-url` 实现
- **RADIUS 认证** — radcli + FreeRADIUS，策略由 Access-Accept 下发
- **热加组** — 写入 `config-per-group/{access_key}` 后 SIGHUP，无需 restart
- **POP API（P2 侧车）** — Go HTTP API，供平台 Worker 下发配置
- **门禁 POC G1–G6** — `gate-poc/` 自动化验收脚本
- **Fork 补丁** — RADIUS 发送 TunnelGroupName VSA 146（SPEC-01，P1）

## 快速开始（Ubuntu 24.04 POP）

```bash
git clone https://github.com/hk59775634/ocserv-tunnel.git
cd ocserv-tunnel
sudo bash scripts/prod-ocserv-install.sh
```

编译并部署 pop-api 侧车：

```bash
cd pop-api && go build -o ocserv-pop-api .
sudo install -m 0755 ocserv-pop-api /usr/local/bin/
sudo cp deploy/systemd/ocserv-pop-api.service /etc/systemd/system/
# 在 /etc/ocserv/pop-api.env 中设置 OCSERV_API_KEY
sudo systemctl enable --now ocserv-pop-api
```

运行门禁测试：

```bash
export POP_HOST=127.0.0.1 OCSERV_API_KEY=your_key
bash gate-poc/scripts/run-all.sh
```

## 目录结构

```
ocserv-tunnel/
├── configs/           # ocserv.d 片段 + radcli 字典
├── patches/           # ocserv Fork 补丁（TunnelGroupName）
├── pop-api/           # P2 侧车 REST API
├── deploy/systemd/    # systemd 单元文件
├── scripts/           # 编译与生产安装脚本
└── gate-poc/          # G1–G6 门禁 POC
```

## POP API（P2 侧车）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v1/status` | ocserv 运行状态 |
| POST | `/api/v1/reload` | SIGHUP 热加载 |
| POST | `/api/v1/groups` | 热添加 config-per-group 组 |
| DELETE | `/api/v1/groups/{name}` | 删除组 |
| PUT | `/api/v1/certificate` | TLS 证书热更新 |

请求头：`X-API-Key: <OCSERV_API_KEY>`

## 门禁 POC 结果

详见 [`gate-poc/docs/REPORT.md`](gate-poc/docs/REPORT.md)。POP API 形态决策：**P2 侧车**（[G6 说明](gate-poc/docs/G6-pop-api-decision.md)）。

## ocserv 版本

- Ubuntu apt 自带 **1.2.4**（不支持 `select-group-by-url`）
- 安装脚本会在需要时从源码编译 **1.4.2**
- 基线标签：`1.4.2`

## 许可证

源自 ocserv 的补丁遵循 **GPLv2**。配置、pop-api 侧车与脚本遵循与 ocserv 集成工作相同的许可策略。
