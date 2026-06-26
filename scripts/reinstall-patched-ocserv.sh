#!/usr/bin/env bash
# Reinstall patched ocserv 1.4.2 on POP — binaries only, preserve /etc/ocserv/*
set -euo pipefail

SRC_DIR="${OCSERV_SRC_DIR:-/tmp/ocserv-patch-142}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF_MD5_BEFORE=$(md5sum /etc/ocserv/ocserv.conf | awk '{print $1}')

echo "==> Stop ocserv"
systemctl stop ocserv 2>/dev/null || true

echo "==> Remove old ocserv binaries"
for bin in /usr/local/sbin/ocserv /usr/local/sbin/ocserv-worker \
           /usr/sbin/ocserv /usr/sbin/ocserv-worker; do
  [[ -f "$bin" ]] && rm -f "$bin" && echo "    removed $bin"
done

echo "==> Build patched ocserv 1.4.2"
export DEBIAN_FRONTEND=noninteractive
need=0
for pkg in meson ninja-build libradcli-dev libgnutls28-dev libtalloc-dev \
  libseccomp-dev libreadline-dev libnl-route-3-dev libcurl4-gnutls-dev \
  liboath-dev libpam0g-dev libprotobuf-c-dev protobuf-c-compiler liblz4-dev \
  libev-dev gperf git; do
  dpkg -s "$pkg" >/dev/null 2>&1 || need=1
done
if [[ "$need" -eq 1 ]]; then
  apt-get update
  apt-get install -y build-essential git meson ninja-build pkg-config gperf \
    libgnutls28-dev libtalloc-dev libseccomp-dev libreadline-dev \
    libnl-route-3-dev libcurl4-gnutls-dev liboath-dev libpam0g-dev \
    libprotobuf-c-dev protobuf-c-compiler liblz4-dev libradcli-dev \
    libev-dev ipcalc-ng libmaxminddb-dev
fi

if [[ ! -d "${SRC_DIR}/.git" ]]; then
  rm -rf "${SRC_DIR}"
  git clone --depth 1 --branch 1.4.2 \
    https://gitlab.com/openconnect/ocserv.git "${SRC_DIR}"
fi

cd "${SRC_DIR}"
git checkout -f 1.4.2
git clean -fdx
python3 "${ROOT_DIR}/scripts/apply-spec01-edits.py" "${SRC_DIR}"

rm -rf build
meson setup build --prefix=/usr/local
ninja -C build

echo "==> Install binaries only"
install -m 0755 build/src/ocserv /usr/local/sbin/ocserv
install -m 0755 build/src/ocserv-worker /usr/local/sbin/ocserv-worker
ldconfig 2>/dev/null || true

echo "==> radcli dictionary.vpnplatform (minimal)"
install -m 0644 "${ROOT_DIR}/configs/radcli/dictionary.vpnplatform" \
  /etc/radcli/dictionary.vpnplatform
if [[ -f /etc/radcli/dictionary ]] && \
   ! grep -q dictionary.vpnplatform /etc/radcli/dictionary; then
  echo 'INCLUDE /etc/radcli/dictionary.vpnplatform' >> /etc/radcli/dictionary
fi
bash "${ROOT_DIR}/scripts/fix-radcli-dict.sh"

echo "==> Start ocserv (config unchanged)"
systemctl start ocserv
sleep 2

CONF_MD5_AFTER=$(md5sum /etc/ocserv/ocserv.conf | awk '{print $1}')
echo "ocserv: $(/usr/local/sbin/ocserv --version 2>&1 | head -1)"
echo "service: $(systemctl is-active ocserv)"
echo "conf_md5 before=$CONF_MD5_BEFORE after=$CONF_MD5_AFTER"
if [[ "$CONF_MD5_BEFORE" != "$CONF_MD5_AFTER" ]]; then
  echo "ERROR: ocserv.conf was modified!" >&2
  exit 1
fi
echo "conf_unchanged=OK"
strings /usr/local/sbin/ocserv | grep -F TunnelGroupName | head -2 || true
