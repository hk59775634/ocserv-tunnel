#!/usr/bin/env bash
# 清除 gate-poc 配置缓存，下次运行从当前 ocserv.conf 重建
set -euo pipefail
rm -f /etc/ocserv/ocserv.conf.gate-poc.base
echo "已清除 gate-poc 配置缓存"
