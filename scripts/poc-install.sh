#!/usr/bin/env bash
# POC 安装：Ubuntu 24.04 上编译上游 ocserv + 平台配置
# 用法: sudo ./scripts/poc-install.sh
set -euo pipefail

OCSERV_VERSION="${OCSERV_VERSION:-1.2.7}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> ocserv POC 安装（目标版本 ${OCSERV_VERSION}）"

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

echo "==> 克隆 ocserv 源码"
git clone --depth 1 --branch "ocserv-${OCSERV_VERSION}" https://gitlab.com/openconnect/ocserv.git || {
  echo "未找到标签 ocserv-${OCSERV_VERSION}，克隆默认分支"
  git clone --depth 1 https://gitlab.com/openconnect/ocserv.git
}

cd ocserv

if compgen -G "${ROOT_DIR}/patches/*.patch" > /dev/null; then
  echo "==> 应用平台补丁"
  for p in "${ROOT_DIR}"/patches/*.patch; do
    echo "    补丁: $(basename "$p")"
    patch -p1 < "$p" || echo "警告: 补丁 $(basename "$p") 失败 — 请手动应用或参考 .snippet"
  done
fi

echo "==> 编译 ocserv"
meson setup build --prefix=/usr
ninja -C build
ninja -C build install

echo "==> 安装平台配置"
install -d /etc/ocserv/ocserv.d
install -d /etc/ocserv/config-per-group
install -m 0644 "${ROOT_DIR}/configs/vpn-platform.conf" /etc/ocserv/ocserv.d/vpn-platform.conf

install -d /etc/radcli
if [[ -f /etc/radcli/radiusclient.conf ]]; then
  echo "    radcli 配置已存在，请手动合并 dictionary.vpnplatform"
else
  if [[ -f /etc/radcli/radiusclient-ocserv.conf ]]; then
    cp /etc/radcli/radiusclient-ocserv.conf /etc/radcli/radiusclient.conf
  fi
fi
install -m 0644 "${ROOT_DIR}/configs/radcli/dictionary.vpnplatform" /etc/radcli/dictionary.vpnplatform

if [[ -f /etc/ocserv/ocserv.conf ]] && ! grep -q 'ocserv.d/vpn-platform.conf' /etc/ocserv/ocserv.conf; then
  echo 'include = /etc/ocserv/ocserv.d/vpn-platform.conf' >> /etc/ocserv/ocserv.conf
fi

echo '# POC 示例组 ilinkcn' > /etc/ocserv/config-per-group/ilinkcn

echo "==> 编译 pop-api 侧车（P2）"
if command -v go >/dev/null 2>&1; then
  (cd "${ROOT_DIR}/pop-api" && go build -o /usr/local/bin/ocserv-pop-api .)
  install -m 0644 "${ROOT_DIR}/deploy/systemd/ocserv-pop-api.service" /etc/systemd/system/ocserv-pop-api.service
else
  echo "警告: 未安装 go，跳过 pop-api 编译"
fi

echo ""
echo "POC 安装完成。"
echo "后续步骤:"
echo "  1. 编辑 /etc/radcli/radiusclient.conf（RADIUS 地址、dictionary.vpnplatform）"
echo "  2. 配置 /etc/ocserv/ 下的 TLS 证书"
echo "  3. systemctl enable --now ocserv"
echo "  4. 在 /etc/ocserv/pop-api.env 设置 OCSERV_API_KEY 并启用 ocserv-pop-api（可选 P2）"
echo "  5. 运行门禁测试: bash gate-poc/scripts/run-all.sh"
