# ocserv-tunnel 补丁

在检出冻结标签后的上游 ocserv **1.2.x / 1.4.x** 源码上应用。

```bash
cd ocserv-src
for p in patches/*.patch; do patch -p1 -N < "$p" || echo "补丁需手动处理: $p"; done
```

## 索引

| 补丁 | SPEC | 说明 |
|------|------|------|
| `0001-radius-send-tunnel-group-name.patch` | SPEC-01 | 在 RADIUS Access-Request 中发送 Cisco `TunnelGroupName`（VSA 146） |

后续补丁（脚手架中尚未包含）：

- SPEC-02 — 内嵌 POP 管理 API（P1）
- SPEC-04 — SIGHUP 时重扫 `auto-select-group` 目录（若 POC 未通过）

## SPEC-01 集成说明

**目标：** 客户端连接 `https://pop/{access_key}` 时，ocserv 通过 `select-group-by-url` 选定 authgroup。该组名必须出现在 RADIUS Access-Request 的 Cisco VSA 146（`TunnelGroupName`）中。

**上游调用顺序（sec-mod）：**

1. Worker 发送 auth init，`group_name` 写入 `e->req_group_name`（`sec-mod-auth.c`）。
2. `set_auth_group()` 调用 `module->auth_group()`，填充 `e->acct_info.groupname`。
3. `module->auth_pass()` 在组名确定**之后**执行。

**缺口：** `radius_auth_init()` 仅接收 `common_auth_init_st`（无 group 字段）；`radius_ctx_st` 目前没有 selected-group 存储。

**实现者待办：**

1. 扩展 `common_auth_init_st` 增加 `const char *groupname`，**或** 在 `auth_pass` 前由 sec-mod 调用 `radius_auth_set_group()`。
2. 将 URL 选定的组写入 `pctx->selected_group`（补丁在 `radius_ctx_st` 中增加字段）。
3. 确保 radcli 在 `rc_read_dictionary` 前加载 `dictionary.vpnplatform`。
4. 用 `radclient` / FreeRADIUS debug 验证 VSA 146 等于 `access_key`。

若统一 diff 无法干净应用于你的 ocserv 标签，请参考 `radius_tunnel_group.c.snippet`。
