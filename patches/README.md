# ocserv-vpnplatform patches

Apply on top of upstream ocserv **1.2.x** after checking out the frozen tag.

```bash
cd ocserv-src
for p in patches/*.patch; do patch -p1 < "$p"; done
```

## Index

| Patch | SPEC | Description |
|-------|------|-------------|
| `0001-radius-send-tunnel-group-name.patch` | SPEC-01 | Send Cisco `TunnelGroupName` (VSA 146) in RADIUS Access-Request |

Future patches (not in scaffold):

- SPEC-02 — embedded POP management API (P1)
- SPEC-04 — `auto-select-group` directory rescan on SIGHUP (if POC fails)

## SPEC-01 integration notes

**Goal:** When the client connects to `https://pop/{access_key}`, ocserv selects `authgroup` via `select-group-by-url`. That group name must appear in the RADIUS Access-Request as Cisco VSA 146 (`TunnelGroupName`).

**Upstream call order (sec-mod):**

1. Worker sends auth init with `group_name` → stored in `e->req_group_name` (`sec-mod-auth.c`).
2. `set_auth_group()` calls `module->auth_group()` → fills `e->acct_info.groupname`.
3. `module->auth_pass()` runs **after** group is known.

**Gap:** `radius_auth_init()` only receives `common_auth_init_st` (no group field). `radius_ctx_st` has no selected-group storage today.

**Implementer TODO:**

1. Extend `common_auth_init_st` with `const char *groupname` **or** add `radius_auth_set_group(void *ctx, const char *group)` called from sec-mod before `auth_pass`.
2. Store URL-selected group in `pctx->selected_group` (patch adds field to `radius_ctx_st`).
3. Ensure `dictionary.vpnplatform` is loaded by radcli before `rc_read_dictionary`.
4. Verify with `radclient` / FreeRADIUS debug that VSA 146 equals `access_key`.

If the unified diff does not apply cleanly to your exact 1.2.x tag, use `radius_tunnel_group.c.snippet` as the reference implementation.
