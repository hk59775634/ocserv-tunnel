#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="${OCSERV_SRC_DIR:-/tmp/ocserv-patch-142}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "${SRC_DIR}"
git checkout -f 1.4.2
git clean -fdx

python3 "${ROOT_DIR}/scripts/apply-spec01-edits.py" "${SRC_DIR}"

rm -rf build
meson setup build --prefix=/usr/local
ninja -C build

install -m 0755 build/src/ocserv /usr/local/sbin/ocserv
install -m 0755 build/src/ocserv-worker /usr/local/sbin/ocserv-worker

install -m 0644 "${ROOT_DIR}/configs/radcli/dictionary.vpnplatform" \
  /etc/radcli/dictionary.vpnplatform
if [[ -f /etc/radcli/dictionary ]] && \
   ! grep -q dictionary.vpnplatform /etc/radcli/dictionary; then
  echo 'INCLUDE /etc/radcli/dictionary.vpnplatform' >> /etc/radcli/dictionary
fi

CONF_BEFORE=$(md5sum /etc/ocserv/ocserv.conf | awk '{print $1}')
systemctl restart ocserv
CONF_AFTER=$(md5sum /etc/ocserv/ocserv.conf | awk '{print $1}')

echo "ocserv: $(ocserv --version 2>&1 | head -1)"
echo "service: $(systemctl is-active ocserv)"
echo "conf_md5 unchanged: $([[ ${CONF_BEFORE} == ${CONF_AFTER} ]] && echo yes || echo NO)"
strings /usr/local/sbin/ocserv | grep -F TunnelGroupName | head -3 || true
