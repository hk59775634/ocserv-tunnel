#!/usr/bin/env bash
# 从源码编译 ocserv（select-group-by-url 需 >= 1.3.0；Ubuntu apt 为 1.2.4）
set -euo pipefail

OCSERV_VERSION="${OCSERV_VERSION:-1.4.2}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> 从源码编译 ocserv ${OCSERV_VERSION}"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
  build-essential git meson ninja-build pkg-config gperf \
  libgnutls28-dev libtalloc-dev libseccomp-dev libreadline-dev \
  libnl-route-3-dev libcurl4-gnutls-dev liboath-dev libpam0g-dev \
  libprotobuf-c-dev protobuf-c-compiler liblz4-dev libradcli-dev \
  libev-dev ipcalc-ng libmaxminddb-dev

BUILD_DIR="${TMPDIR:-/tmp}/ocserv-build-$$"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

git clone --depth 1 --branch "${OCSERV_VERSION}" https://gitlab.com/openconnect/ocserv.git

cd ocserv
if compgen -G "${ROOT_DIR}/patches/*.patch" > /dev/null; then
  for p in "${ROOT_DIR}"/patches/*.patch; do
    echo "    补丁: $(basename "$p")"
    patch -p1 -N < "$p" || echo "警告: 补丁 $(basename "$p") 应用失败"
  done
fi

meson setup build --prefix=/usr
ninja -C build
ninja -C build install
ldconfig

echo "==> 已安装: $(ocserv --version 2>&1 | head -1)"
