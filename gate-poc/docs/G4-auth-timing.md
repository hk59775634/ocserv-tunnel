# G4 — 认证时序调研：TunnelGroupName 补丁落点

> **基线**：ocserv **1.4.2**（`/tmp/ocserv-build-*/ocserv` 源码）  
> **结论**：URL 选组 **早于** RADIUS Access-Request，但 **未传入** radius 模块；P1 补丁可行。

---

## 1. 调用链（sec-mod）

```
Worker (select-group-by-url)
  └─ SecAuthInitMsg.group_name = URL path (access_key)
       └─ handle_sec_auth_init()          [sec-mod-auth.c:876]
            ├─ auth_init(&st)             [L942–951]  ← st 无 groupname
            ├─ req→e->req_group_name       [L988–990]  ← 组名在此写入
            └─ … → 等待密码
       └─ handle_sec_auth_cont()
            └─ auth_pass(password)         [L830]      ← RADIUS Access-Request
            └─ check_group()               [L414]      ← 组校验在 RADIUS **之后**
```

**关键发现**

| 时点 | `req_group_name` | RADIUS 包 |
|------|------------------|-----------|
| `auth_init` | 尚未写入 `e`（同函数内顺序在 auth_init **之后**） | 未发送 |
| `auth_pass` | 已存在于 `e->req_group_name` | **此时发送** Access-Request |
| `check_group` | 已存在 | 已成功 Accept 之后 |

`common_auth_init_st`（`sec-mod.h:62–68`）仅有 `username/ip/user_agent`，**无 groupname**。

---

## 2. 原生 ocserv 行为

- `radius_auth_init()` 只读 `common_auth_init_st`，无法获知 URL 组。
- `radius_auth_pass()` 调用 `rc_aaa()` 发 Access-Request，**不含** Cisco VSA 146。
- 组名在 RADIUS 成功后由 `check_group()` → `radius_auth_group()` 写入 `acct_info.groupname`（用于会话，非 Access-Request）。

Route B 需要：**Access-Request 携带 `TunnelGroupName={access_key}`**，供 FreeRADIUS rlm_rest 解析租户。

---

## 3. P1 补丁方案（推荐）

### 3.1 改动文件

| 文件 | 改动 |
|------|------|
| `src/sec-mod.h` | `common_auth_init_st` 增加 `const char *groupname` |
| `src/sec-mod-auth.c` | `handle_sec_auth_init`：`st.groupname = req->group_name`（**在 auth_init 之前**） |
| `src/auth/radius.h` | `radius_ctx_st` 增加 `char selected_group[MAX_GROUPNAME_SIZE]` |
| `src/auth/radius.c` | `radius_auth_init`：复制 `info->groupname`；`radius_auth_pass`：VSA 146 |
| `configs/radcli/dictionary.vpnplatform` | 已有 `TunnelGroupName` 146 |

### 3.2 补丁落点（函数级）

```c
// sec-mod-auth.c — handle_sec_auth_init, before auth_init()
st.groupname = req->group_name;   // NEW

// radius.c — radius_auth_init()
if (info->groupname)
    strlcpy(pctx->selected_group, info->groupname, sizeof(pctx->selected_group));

// radius.c — radius_auth_pass(), before rc_aaa()
rc_avpair_add(..., PW_TUNNELGROUPNAME, pctx->selected_group, ...);
```

参考脚手架：`patches/0001-radius-send-tunnel-group-name.patch`（需按 1.4.2 路径 rebase，`auth/radius.c` 已内建）。

### 3.3 验收

```bash
# FreeRADIUS debug 或 radclient 抓包
# Access-Request 含 Cisco-AVPair TunnelGroupName=demo_agent
```

---

## 4. 与 G3（groupconfig）的关系

- `groupconfig=true` 与 `config-per-group` **互斥**（ocserv 启动校验）。
- G1/G2 用 **profile-g12**；G3 用 **profile-g3**。
- P1 目标：Fork 后评估 **SIGHUP 重扫组目录 + RADIUS Class 组** 是否可替代双 profile（见 SPEC-04）。

---

## 5. 结论

| 问题 | 结论 |
|------|------|
| URL 选组是否早于 RADIUS？ | **是**（`req->group_name` 在 auth_init 同请求内可用） |
| 原生是否发送 TunnelGroupName？ | **否** |
| 补丁是否可实现？ | **是**，扩展 `common_auth_init_st` 即可 |
| 阻塞项 | 无 |

**G4 状态：✅ 调研完成，P1 可开工**
