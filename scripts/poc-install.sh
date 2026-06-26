#!/usr/bin/env bash
# POC installer: upstream ocserv on Ubuntu 24.04 + vpn-platform configs
# Usage: sudo ./scripts/poc-install.sh
set -euo pipefail

OCSERV_VERSION="${OCSERV_VERSION:-1.2.7}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> ocserv-vpnplatform POC install (ocserv ${OCSERV_VERSION})"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
  build-essential \
  git \
  meson \
  ninja-build \
  pkg-config \
  libgnutls28-dev \
  libtalloc-dev \
  libseccomp-dev \
  libreadline-dev \
  libnl-route-3-dev \
  libcurl4-gnutls-dev \
  liboath-dev \
  libpam0g-dev \
  libprotobuf-c-dev \
  protobuf-c-compiler \
  liblz4-dev \
  libradcli-dev \
  radcli \
  curl

BUILD_DIR="${TMPDIR:-/tmp}/ocserv-build-$$"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

echo "==> Cloning ocserv"
git clone --depth 1 --branch "ocserv-${OCSERV_VERSION}" https://gitlab.com/openconnect/ocserv.git || {
  echo "Tag ocserv-${OCSERV_VERSION} not found; cloning default branch"
  git clone --depth 1 https://gitlab.com/openconnect/ocserv.git
}

cd ocserv

if compgen -G "${ROOT_DIR}/patches/*.patch" > /dev/null; then
  echo "==> Applying vpnplatform patches"
  for p in "${ROOT_DIR}"/patches/*.patch; do
    echo "    patch: $(basename "$p")"
    patch -p1 < "$p" || echo "WARN: patch $(basename "$p") failed — apply manually or use .snippet"
  done
fi

echo "==> Building ocserv"
meson setup build --prefix=/usr
ninja -C build
ninja -C build install

echo "==> Installing vpn-platform configs"
install -d /etc/ocserv/ocserv.d
install -d /etc/ocserv/config-per-group
install -m 0644 "${ROOT_DIR}/configs/vpn-platform.conf" /etc/ocserv/ocserv.d/vpn-platform.conf

install -d /etc/radcli
if [[ -f /etc/radcli/radiusclient.conf ]]; then
  echo "    radcli config exists; merge dictionary manually"
else
  if [[ -f /etc/radcli/radiusclient-ocserv.conf ]]; then
    cp /etc/radcli/radiusclient-ocserv.conf /etc/radcli/radiusclient.conf
  fi
fi
install -m 0644 "${ROOT_DIR}/configs/radcli/dictionary.vpnplatform" /etc/radcli/dictionary.vpnplatform

# Ensure main ocserv.conf includes ocserv.d
if [[ -f /etc/ocserv/ocserv.conf ]] && ! grep -q 'ocserv.d/vpn-platform.conf' /etc/ocserv/ocserv.conf; then
  echo 'include = /etc/ocserv/ocserv.d/vpn-platform.conf' >> /etc/ocserv/ocserv.conf
fi

# Sample group for POC
echo '# POC group ilinkcn' > /etc/ocserv/config-per-group/ilinkcn

echo "==> Building pop-api sidecar (P2)"
if command -v go >/dev/null 2>&1; then
  (cd "${ROOT_DIR}/pop-api" && go build -o /usr/local/bin/ocserv-pop-api .)
  install -m 0644 "${ROOT_DIR}/deploy/systemd/ocserv-pop-api.service" /etc/systemd/system/ocserv-pop-api.service
else
  echo "WARN: go not installed; skip pop-api build"
fi

echo ""
echo "POC install complete."
echo "Next steps:"
echo "  1. Edit /etc/radcli/radiusclient.conf (RADIUS server, include dictionary.vpnplatform)"
echo "  2. Configure TLS certs in /etc/ocserv/"
echo "  3. systemctl enable --now ocserv"
echo "  4. Set OCSERV_API_KEY in /etc/ocserv/pop-api.env and enable ocserv-pop-api (optional P2)"
echo "  5. Run POC checklist: docs/ocserv-route-b-p0-poc-checklist.md"
