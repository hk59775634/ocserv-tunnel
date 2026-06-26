#!/usr/bin/env bash
# Rebuild ocserv with SPEC-01 TunnelGroupName patch only.
# Does NOT modify /etc/ocserv/* or qosnatd-managed configuration.
set -euo pipefail

OCSERV_VERSION="${OCSERV_VERSION:-1.4.2}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${ROOT:-${SCRIPT_DIR}}"
SRC_DIR="${OCSERV_SRC_DIR:-/tmp/ocserv-patch-142}"
INSTALL_RADCLI_DICT="${INSTALL_RADCLI_DICT:-1}"

echo "==> SPEC-01 patch rebuild (ocserv ${OCSERV_VERSION})"
echo "    Source: ${SRC_DIR}"
echo "    Patches: ${ROOT_DIR}/patches/"

export DEBIAN_FRONTEND=noninteractive
need_pkgs=0
for pkg in meson ninja-build libradcli-dev libgnutls28-dev libtalloc-dev \
  libseccomp-dev libreadline-dev libnl-route-3-dev libcurl4-gnutls-dev \
  liboath-dev libpam0g-dev libprotobuf-c-dev protobuf-c-compiler liblz4-dev \
  libev-dev gperf; do
  dpkg -s "$pkg" >/dev/null 2>&1 || need_pkgs=1
done
if [[ "$need_pkgs" -eq 1 ]]; then
  apt-get update
  apt-get install -y build-essential git meson ninja-build pkg-config gperf \
    libgnutls28-dev libtalloc-dev libseccomp-dev libreadline-dev \
    libnl-route-3-dev libcurl4-gnutls-dev liboath-dev libpam0g-dev \
    libprotobuf-c-dev protobuf-c-compiler liblz4-dev libradcli-dev \
    libev-dev ipcalc-ng libmaxminddb-dev
fi

if [[ ! -d "${SRC_DIR}/.git" ]]; then
  rm -rf "${SRC_DIR}"
  git clone --depth 1 --branch "${OCSERV_VERSION}" \
    https://gitlab.com/openconnect/ocserv.git "${SRC_DIR}"
else
  cd "${SRC_DIR}"
  git fetch --depth 1 origin "refs/tags/${OCSERV_VERSION}:refs/tags/${OCSERV_VERSION}" 2>/dev/null || true
  git checkout -f "${OCSERV_VERSION}"
  git clean -fdx
fi

cd "${SRC_DIR}"
for p in "${ROOT_DIR}"/patches/*.patch; do
  [[ -f "$p" ]] || continue
  echo "    applying $(basename "$p")"
  patch -p1 -N < "$p" || {
    echo "    patch failed, falling back to apply-spec01-edits.py"
    python3 "${ROOT_DIR}/scripts/apply-spec01-edits.py" "${SRC_DIR}"
    break
  }
done
if ! grep -q PW_TUNNELGROUPNAME "${SRC_DIR}/src/auth/radius.c" 2>/dev/null; then
  python3 "${ROOT_DIR}/scripts/apply-spec01-edits.py" "${SRC_DIR}"
fi

rm -rf build
meson setup build --prefix=/usr/local
ninja -C build

echo "==> Installing binaries only (ocserv, ocserv-worker)"
install -m 0755 build/src/ocserv /usr/local/sbin/ocserv
install -m 0755 build/src/ocserv-worker /usr/local/sbin/ocserv-worker
ldconfig 2>/dev/null || true

if [[ "${INSTALL_RADCLI_DICT}" == "1" ]]; then
  echo "==> radcli dictionary.vpnplatform (minimal, no radiusclient.conf changes)"
  install -m 0644 "${ROOT_DIR}/configs/radcli/dictionary.vpnplatform" \
    /etc/radcli/dictionary.vpnplatform
  if [[ -f /etc/radcli/dictionary ]] && \
     ! grep -q dictionary.vpnplatform /etc/radcli/dictionary; then
    echo 'INCLUDE /etc/radcli/dictionary.vpnplatform' >> /etc/radcli/dictionary
  fi
fi

echo "==> Restart ocserv"
systemctl restart ocserv
systemctl is-active ocserv
ocserv --version 2>&1 | head -1
strings /usr/local/sbin/ocserv | grep -F 'TunnelGroupName' | head -3 || true
echo "==> Done. /etc/ocserv was not modified."
