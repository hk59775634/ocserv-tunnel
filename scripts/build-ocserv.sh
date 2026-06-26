#!/usr/bin/env bash
# 从源码编译带 SPEC-01 补丁的 ocserv（select-group-by-url 需 >= 1.3.0）
set -euo pipefail

OCSERV_VERSION="${OCSERV_VERSION:-1.4.2}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> 从源码编译 ocserv ${OCSERV_VERSION}（SPEC-01 补丁）"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
  build-essential git meson ninja-build pkg-config gperf python3 \
  libgnutls28-dev libtalloc-dev libseccomp-dev libreadline-dev \
  libnl-route-3-dev libcurl4-gnutls-dev liboath-dev libpam0g-dev \
  libprotobuf-c-dev protobuf-c-compiler liblz4-dev libradcli-dev \
  libev-dev ipcalc-ng libmaxminddb-dev

BUILD_DIR="${TMPDIR:-/tmp}/ocserv-build-$$"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

git clone --depth 1 --branch "${OCSERV_VERSION}" https://gitlab.com/openconnect/ocserv.git

cd ocserv
python3 "${ROOT_DIR}/scripts/apply-spec01-edits.py" .

meson setup build --prefix=/usr
ninja -C build
ninja -C build install
ldconfig

echo "==> 已安装: $(ocserv --version 2>&1 | head -1)"
