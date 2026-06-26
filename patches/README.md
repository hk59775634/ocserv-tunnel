# ocserv-tunnel 补丁

**基线：** ocserv **1.4.2**（已在 157.15.107.12 生产验证）。`0001-*.patch` 仅供参考；**推荐**使用 `scripts/apply-spec01-edits.py`。

```bash
git clone --depth 1 --branch 1.4.2 https://gitlab.com/openconnect/ocserv.git ocserv-src
cd ocserv-src
python3 ../scripts/apply-spec01-edits.py .
meson setup build --prefix=/usr/local && ninja -C build
```

已有 POP 节点仅替换二进制（不改动 `ocserv.conf`）：

```bash
sudo bash scripts/reinstall-patched-ocserv.sh
```

## 索引

| 产物 | SPEC | 说明 |
|------|------|------|
| `scripts/apply-spec01-edits.py` | SPEC-01 | **主实现**：认证 + 计费 RADIUS 发送 `TunnelGroupName`（VSA 146） |
| `0001-radius-send-tunnel-group-name.patch` | SPEC-01 | 早期 diff（1.4.2 上可能无法直接 `patch -p1`） |
| `radius_tunnel_group.c.snippet` | SPEC-01 | 手工集成参考 |
| `ipc.proto.ref` | SPEC-01 | `sec_auth_cont_msg.group_name` 字段参考 |

## SPEC-01 改动摘要（2026-06-26 已验证）

| 区域 | 改动 |
|------|------|
| `worker-auth.c` | URL / `group-select` / `<group-access>` 解析；`auth_cont` 携带 `group_name` |
| `sec-mod-auth.c` | `req_group_name` 持久化；`radius_auth_bind_group` 于 `auth_pass` 前 |
| `auth/radius.c` | Access-Request 发送 VSA 146；Route B 组名校验 |
| `acct/radius.c` | Accounting-Start 发送 `TunnelGroupName`（完整隧道必需） |
| `ipc.proto` | `sec_auth_cont_msg` 增加 `group_name` |
| radcli | `dictionary.vpnplatform` + 主字典 Cisco-ASA 段 `TunnelGroupName` 146 |

## 验收

```bash
# curl 冒烟
bash scripts/test-route-b-auth.sh 127.0.0.1 10000 demo_agent testuser 'User@123'

# OpenConnect XML 两阶段
bash scripts/test-openconnect-routeb.sh

# 客户端（WSL / Linux）
openconnect https://POP:PORT/demo_agent -u USER --authgroup=demo_agent \
  --servercert=pin-sha256:... --no-dtls
```

后续补丁（尚未包含）：

- SPEC-02 — 内嵌 POP 管理 API（P1）
- SPEC-04 — SIGHUP 时重扫 `auto-select-group` 目录
