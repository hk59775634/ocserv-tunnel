#!/usr/bin/env bash
# Build ocserv from source (select-group-by-url requires >= 1.3.0; Ubuntu apt is 1.2.4)
set -euo pipefail

OCSERV_VERSION="${OCSERV_VERSION:-1.4.2}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> Build ocserv ${OCSERV_VERSION} from source"

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
    echo "    patch: $(basename "$p")"
    patch -p1 -N < "$p" || echo "WARN: patch $(basename "$p") failed"
  done
fi

meson setup build --prefix=/usr
ninja -C build
ninja -C build install
ldconfig

echo "==> Installed: $(ocserv --version 2>&1 | head -1)"
