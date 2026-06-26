#!/usr/bin/env python3
"""Apply SPEC-01 TunnelGroupName edits to ocserv 1.4.2 source tree."""
from __future__ import annotations

import sys
from pathlib import Path


def insert_before(text: str, needle: str, insert: str, label: str) -> str:
    idx = text.find(needle)
    if idx < 0:
        raise SystemExit(f"{label}: anchor not found")
    if insert.strip() in text[:idx]:
        print(f"{label}: already present")
        return text
    return text[:idx] + insert + text[idx:]


def insert_after(text: str, needle: str, insert: str, label: str) -> str:
    idx = text.find(needle)
    if idx < 0:
        raise SystemExit(f"{label}: anchor not found")
    if insert.strip() in text:
        print(f"{label}: already present")
        return text
    pos = idx + len(needle)
    return text[:pos] + insert + text[pos:]


def main() -> None:
    root = Path(sys.argv[1])

    sec_mod_h = root / "src/sec-mod.h"
    text = sec_mod_h.read_text()
    text = insert_after(
        text,
        "\tconst char *user_agent;\n",
        "\tconst char *groupname; /* URL-selected authgroup (SPEC-01) */\n",
        "sec-mod.h",
    )
    sec_mod_h.write_text(text)

    sec_mod_auth = root / "src/sec-mod-auth.c"
    text = sec_mod_auth.read_text()
    text = insert_after(
        text,
        "\t\tst.user_agent = req->user_agent;\n",
        "\t\tst.groupname = req->group_name;\n",
        "sec-mod-auth.c st.groupname",
    )
    # Persist URL group before auth_init; st.groupname reads e->req_group_name.
    text = insert_before(
        text,
        "\tif (e->module) {\n\t\tcommon_auth_init_st st;\n",
        (
            "\tif (req->group_name != NULL) {\n"
            "\t\tstrlcpy(e->req_group_name, req->group_name,\n"
            "\t\t\tsizeof(e->req_group_name));\n"
            "\t}\n\n"
        ),
        "sec-mod-auth.c early req_group_name",
    )
    text = text.replace(
        "\t\tst.groupname = req->group_name;\n",
        "\t\tst.groupname = e->req_group_name[0] ? e->req_group_name : req->group_name;\n",
        1,
    )
    auth_cont_needle = (
        "\tret = e->module->auth_pass(e->auth_ctx, req->password,\n"
        "\t\t\t\t   strlen(req->password));\n"
    )
    auth_cont_insert = (
        "\tif (e->req_group_name[0] != 0 && (e->auth_type & AUTH_TYPE_RADIUS))\n"
        "\t\tradius_auth_bind_group(e->auth_ctx, e->req_group_name);\n\n"
    )
    text = insert_before(text, auth_cont_needle, auth_cont_insert, "sec-mod-auth.c bind group before pass")
    cont_group_needle = (
        "\tif (e->req_group_name[0] != 0 && (e->auth_type & AUTH_TYPE_RADIUS))\n"
        "\t\tradius_auth_bind_group(e->auth_ctx, e->req_group_name);\n"
    )
    cont_group_insert = (
        "\tif (req->group_name != NULL && req->group_name[0] != 0) {\n"
        "\t\tstrlcpy(e->req_group_name, req->group_name,\n"
        "\t\t\tsizeof(e->req_group_name));\n"
        "\t}\n\n"
    )
    if "req->group_name != NULL && req->group_name[0]" not in text:
        text = insert_before(
            text, cont_group_needle, cont_group_insert, "sec-mod-auth.c cont group_name"
        )
    if '#include "auth/radius.h"' not in text:
        text = text.replace(
            '#include <config.h>\n',
            '#include <config.h>\n#ifdef HAVE_RADIUS\n#include "auth/radius.h"\n#endif\n',
            1,
        )
    sec_mod_auth.write_text(text)

    worker_auth = root / "src/worker-auth.c"
    text = worker_auth.read_text()
    worker_needle = (
        "\t\tret = send_msg_to_secmod(\n"
        "\t\t\tws, sd, CMD_SEC_AUTH_INIT, &ireq,\n"
    )
    worker_insert = (
        "\t\tif (ireq.group_name == NULL && ws->groupname[0] != 0)\n"
        "\t\t\tireq.group_name = ws->groupname;\n\n"
    )
    text = insert_before(text, worker_needle, worker_insert, "worker-auth.c group before init")

    group_access_fn = (
        "\n/* OpenConnect init sends authgroup in <group-access>URL</group-access> (SPEC-01). */\n"
        "static int parse_group_access_url(worker_st *ws, char *body,\n"
        "\t\t\t\t    unsigned int body_length, char **groupname_out)\n"
        "{\n"
        "\tchar *p, *end, *path;\n"
        "\n"
        "\tif (body == NULL || body_length == 0 || groupname_out == NULL)\n"
        "\t\treturn -1;\n"
        "\tif (memmem(body, body_length, \"<?xml\", 5) == NULL)\n"
        "\t\treturn -1;\n"
        "\n"
        "\tp = strcasestr(body, \"<group-access>\");\n"
        "\tif (p == NULL)\n"
        "\t\treturn -1;\n"
        "\tp += sizeof(\"<group-access>\") - 1;\n"
        "\tend = strcasestr(p, \"</group-access>\");\n"
        "\tif (end == NULL || end <= p)\n"
        "\t\treturn -1;\n"
        "\n"
        "\t*groupname_out = talloc_strndup(ws->req.body, p, end - p);\n"
        "\tif (*groupname_out == NULL)\n"
        "\t\treturn -1;\n"
        "\n"
        "\tpath = strstr(*groupname_out, \"://\");\n"
        "\tif (path != NULL) {\n"
        "\t\tpath = strchr(path + 3, '/');\n"
        "\t\tif (path != NULL) {\n"
        "\t\t\tpath++;\n"
        "\t\t\tif (path[0] != 0)\n"
        "\t\t\t\tmemmove(*groupname_out, path, strlen(path) + 1);\n"
        "\t\t}\n"
        "\t}\n"
        "\tif ((*groupname_out)[0] == 0) {\n"
        "\t\ttalloc_free(*groupname_out);\n"
        "\t\t*groupname_out = NULL;\n"
        "\t\treturn -1;\n"
        "\t}\n"
        "\treturn 0;\n"
        "}\n"
        "\n"
    )
    if "parse_group_access_url" not in text:
        text = text.replace(
            "int post_auth_handler(worker_st *ws, unsigned int http_ver)\n",
            group_access_fn + "int post_auth_handler(worker_st *ws, unsigned int http_ver)\n",
            1,
        )
    group_access_call = (
        "\t\tif (ret < 0 &&\n"
        "\t\t    parse_group_access_url(ws, req->body, req->body_length,\n"
        "\t\t\t\t\t     &groupname) == 0)\n"
        "\t\t\tret = 0;\n"
    )
    if "parse_group_access_url(ws" not in text:
        text = insert_before(
            text,
            "\t\tif (ret < 0) {\n"
            "\t\t\toclog(ws, LOG_HTTP_DEBUG, \"failed reading groupname\");\n",
            group_access_call,
            "worker-auth.c group-access",
        )
    cont_needle = (
        "\t\t\tret = send_msg_to_secmod(\n"
        "\t\t\t\tws, sd, CMD_SEC_AUTH_CONT, &areq,\n"
    )
    cont_insert = (
        "\t\t\tif (ws->groupname[0] != 0)\n"
        "\t\t\t\tareq.group_name = ws->groupname;\n\n"
    )
    text = insert_before(text, cont_needle, cont_insert, "worker-auth.c group on auth cont")
    worker_auth.write_text(text)

    ipc_proto = root / "src/ipc.proto"
    ipc_text = ipc_proto.read_text()
    if "group_name = 5" not in ipc_text:
        ipc_text = ipc_text.replace(
            "message sec_auth_cont_msg\n"
            "{\n"
            "\trequired string password = 2;\n"
            "\trequired bytes sid = 3;\n"
            "\trequired string ip = 4;\n"
            "}",
            "message sec_auth_cont_msg\n"
            "{\n"
            "\trequired string password = 2;\n"
            "\trequired bytes sid = 3;\n"
            "\trequired string ip = 4;\n"
            "\toptional string group_name = 5; /* URL authgroup (SPEC-01) */\n"
            "}",
            1,
        )
        ipc_proto.write_text(ipc_text)

    radius_h = root / "src/auth/radius.h"
    text = radius_h.read_text()
    text = insert_after(
        text,
        "\tchar user_agent[MAX_AGENT_NAME];\n",
        "\tchar selected_group[MAX_GROUPNAME_SIZE]; /* URL authgroup (SPEC-01) */\n",
        "radius.h",
    )
    radius_h.write_text(text)
    rh = radius_h.read_text()
    if "radius_auth_bind_group" not in rh:
        radius_h.write_text(rh + "\nvoid radius_auth_bind_group(void *ctx, const char *group);\n")

    radius_c = root / "src/auth/radius.c"
    text = radius_c.read_text()

    # Remove broken prior auth_pass insertions (VSA after rc_aaa or inside state block).
    broken = (
        "\tret = rc_aaa(pctx->vctx->rh, 0, send, &recvd, pctx->pass_msg, 0,\n"
        "\t\t     PW_ACCESS_REQUEST);\tif (pctx->selected_group[0] != 0) {"
    )
    if broken in text:
        text = text.replace(
            broken,
            "\tret = rc_aaa(pctx->vctx->rh, 0, send, &recvd, pctx->pass_msg, 0,\n"
            "\t\t     PW_ACCESS_REQUEST);",
            1,
        )
    vsa_marker = (
        "\tif (pctx->selected_group[0] != 0) {\n"
        "\t\tif (rc_avpair_add(pctx->vctx->rh, &send, PW_TUNNELGROUPNAME,"
    )
    while vsa_marker in text:
        start = text.find(vsa_marker)
        end = text.find(
            '\t\t\t  "radius-auth: no selected_group; TunnelGroupName omitted for user \'%s\'",\n'
            "\t\t\t  pctx->username);\n"
            "\t}\n",
            start,
        )
        if end < 0:
            break
        end = text.find("\n", end + 1) + 1
        text = text[:start] + text[end:]

    text = insert_after(
        text,
        "#define RP_DOWNSTREAM_SPEED_LIMIT VATTRID_SET(2, 10055)\n",
        "\n/* Cisco-ASA TunnelGroupName - VSA 146 / vendor 3076 (SPEC-01) */\n"
        "#ifndef PW_TUNNELGROUPNAME\n"
        "#define PW_TUNNELGROUPNAME VATTRID_SET(146, 3076)\n"
        "#endif\n",
        "radius.c define",
    )
    text = insert_after(
        text,
        "\t\t\tsizeof(pctx->user_agent));\n",
        "\n"
        "\tpctx->selected_group[0] = 0;\n"
        "\tif (info->groupname && info->groupname[0] != 0)\n"
        "\t\tstrlcpy(pctx->selected_group, info->groupname,\n"
        "\t\t\tsizeof(pctx->selected_group));\n",
        "radius.c auth_init",
    )
    vsa_block = (
        "\tif (pctx->selected_group[0] != 0) {\n"
        "\t\tif (rc_avpair_add(pctx->vctx->rh, &send, PW_TUNNELGROUPNAME,\n"
        "\t\t\t\t  pctx->selected_group, -1, 0) == NULL) {\n"
        "\t\t\toc_syslog(LOG_ERR,\n"
        '\t\t\t\t  "%s:%u: error adding TunnelGroupName VSA for user \'%s\' group \'%s\'",\n'
        "\t\t\t\t  __func__, __LINE__, pctx->username,\n"
        "\t\t\t\t  pctx->selected_group);\n"
        "\t\t\tret = ERR_AUTH_FAIL;\n"
        "\t\t\tgoto cleanup;\n"
        "\t\t}\n"
        "\t\toc_syslog(LOG_DEBUG,\n"
        '\t\t\t  "radius-auth: sending TunnelGroupName=\'%s\' for user \'%s\'",\n'
        "\t\t\t  pctx->selected_group, pctx->username);\n"
        "\t} else {\n"
        "\t\toc_syslog(LOG_DEBUG,\n"
        '\t\t\t  "radius-auth: no selected_group; TunnelGroupName omitted for user \'%s\'",\n'
        "\t\t\t  pctx->username);\n"
        "\t}\n"
        "\n"
    )
    # Insert immediately after the PW_STATE cleanup block, before rc_aaa.
    state_close = (
        "\t\ttalloc_free(pctx->state);\n"
        "\t\tpctx->state = NULL;\n"
        "\t}\n"
    )
    text = insert_after(text, state_close, "\n" + vsa_block, "radius.c auth_pass")
    bind_fn = (
        "\nvoid radius_auth_bind_group(void *ctx, const char *group)\n"
        "{\n"
        "\tstruct radius_ctx_st *pctx = ctx;\n\n"
        "\tif (pctx == NULL || group == NULL || group[0] == 0)\n"
        "\t\treturn;\n"
        "\tstrlcpy(pctx->selected_group, group, sizeof(pctx->selected_group));\n"
        "}\n"
    )
    if "radius_auth_bind_group" not in text:
        text = text.replace(
            "static int radius_auth_group(void *ctx, const char *suggested, char *groupname,",
            bind_fn + "\nstatic int radius_auth_group(void *ctx, const char *suggested, char *groupname,",
            1,
        )
    # Route B: after RADIUS OK, trust URL group that was sent as TunnelGroupName.
    group_trust = (
        "\tif (suggested != NULL) {\n"
        "\t\tif (pctx->selected_group[0] != 0 &&\n"
        "\t\t    strcmp(suggested, pctx->selected_group) == 0) {\n"
        "\t\t\tstrlcpy(groupname, suggested, groupname_size);\n"
        "\t\t\treturn 0;\n"
        "\t\t}\n"
    )
    text = insert_after(
        text,
        "\tgroupname[0] = 0;\n\n\tif (suggested != NULL) {\n",
        (
            "\t\tif (pctx->selected_group[0] != 0 &&\n"
            "\t\t    strcmp(suggested, pctx->selected_group) == 0) {\n"
            "\t\t\tstrlcpy(groupname, suggested, groupname_size);\n"
            "\t\t\treturn 0;\n"
            "\t\t}\n"
        ),
        "radius.c trust url group",
    )
    radius_c.write_text(text)

    acct_radius = root / "src/acct/radius.c"
    acct_text = acct_radius.read_text()
    # Fix acct vendor macro block (must match auth/radius.c, not VENDOR_BIT_SIZE=32).
    old_acct_vendor = (
        "/* Cisco-ASA TunnelGroupName - VSA 146 / vendor 3076 (SPEC-01 acct) */\n"
        "#ifndef PW_TUNNELGROUPNAME\n"
        "#ifndef VENDOR_BIT_SIZE\n"
        "#define VENDOR_BIT_SIZE 32\n"
    )
    if old_acct_vendor in acct_text:
        start = acct_text.find("/* Cisco-ASA TunnelGroupName - VSA 146 / vendor 3076 (SPEC-01 acct) */")
        end = acct_text.find("#endif\n", start) + len("#endif\n")
        acct_text = acct_text[:start] + acct_text[end:]
    if "PW_TUNNELGROUPNAME VATTRID_SET(146, 3076)" not in acct_text:
        acct_text = insert_after(
            acct_text,
            '#include "acct/radius.h"\n',
            (
                "\n/* Cisco-ASA TunnelGroupName - VSA 146 / vendor 3076 (SPEC-01 acct) */\n"
                "#ifndef VENDOR_BIT_SIZE\n"
                "#define VENDOR_BIT_SIZE 16\n"
                "#define VENDOR_MASK 0xffff\n"
                "#else\n"
                "#define VENDOR_MASK 0xffffffff\n"
                "#endif\n"
                "#ifndef PW_TUNNELGROUPNAME\n"
                "#define VATTRID_SET(a, v) \\\n"
                "\t((a) | ((uint64_t)((v) & VENDOR_MASK)) << VENDOR_BIT_SIZE)\n"
                "#define PW_TUNNELGROUPNAME VATTRID_SET(146, 3076)\n"
                "#endif\n"
            ),
            "acct/radius.c define",
        )
    if "radius-acct: error adding TunnelGroupName" not in acct_text:
        acct_insert = (
            "\tif (ai->groupname[0] != 0) {\n"
            "\t\tif (rc_avpair_add(rh, send, PW_TUNNELGROUPNAME, ai->groupname,\n"
            "\t\t\t\t  -1, 0) == NULL) {\n"
            "\t\t\toc_syslog(LOG_ERR,\n"
            '\t\t\t\t  "radius-acct: error adding TunnelGroupName for group \'%s\'",\n'
            "\t\t\t\t  ai->groupname);\n"
            "\t\t}\n"
            "\t}\n"
        )
        acct_text = insert_before(
            acct_text,
            "\trc_avpair_add(rh, send, PW_CALLING_STATION_ID, ai->remote_ip, -1, 0);\n",
            acct_insert,
            "acct/radius.c TunnelGroupName",
        )
    acct_radius.write_text(acct_text)

    print("SPEC-01 edits applied OK")


if __name__ == "__main__":
    main()
