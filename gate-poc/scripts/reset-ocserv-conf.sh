#!/usr/bin/env bash
# Remove gate-poc profile cache so next run rebuilds base from current ocserv.conf
set -euo pipefail
rm -f /etc/ocserv/ocserv.conf.gate-poc.base
echo "Removed gate-poc base cache"
