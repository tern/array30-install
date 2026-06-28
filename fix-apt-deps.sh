#!/usr/bin/env bash
# fix-apt-deps.sh — 修復 Pop!_OS / Ubuntu 上 fcitx5 5.1.12 與 libxcb 不相容造成的 apt 損壞
#
# 典型錯誤：
#   fcitx5-modules : 相依關係: libxcb-ewmh2 (>= 0.4.2) 但 0.4.1 卻將被安裝
#
# 用法： sudo bash fix-apt-deps.sh
# 說明： docs/POP-OS.md
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    err "請用 sudo 執行： sudo bash $0"
    exit 1
fi

tmpdir=""
cleanup() {
    [[ -n "$tmpdir" && -d "$tmpdir" ]] && rm -rf "$tmpdir"
}
trap cleanup EXIT

tmpdir=$(mktemp -d)

info "修復 fcitx5 5.1.12 與 libxcb 版本不相容問題..."

debs=(
    "http://archive.ubuntu.com/ubuntu/pool/main/x/xcb-util-wm/libxcb-ewmh2_0.4.2-1_amd64.deb"
    "http://archive.ubuntu.com/ubuntu/pool/main/x/xcb-util-wm/libxcb-icccm4_0.4.2-1_amd64.deb"
    "http://archive.ubuntu.com/ubuntu/pool/main/x/xcb-util-keysyms/libxcb-keysyms1_0.4.1-1_amd64.deb"
)

for url in "${debs[@]}"; do
    info "下載 $(basename "$url")..."
    curl -fL "$url" -o "$tmpdir/$(basename "$url")"
done

info "安裝新版 libxcb 套件..."
dpkg -i "$tmpdir"/*.deb

info "修復 apt 相依關係..."
apt-get --fix-broken install -y
apt-get install -y libfmt9

trap - EXIT
cleanup
tmpdir=""

ok "apt 相依關係已修復"
info "已安裝：libxcb-ewmh2 0.4.2, libxcb-icccm4 0.4.2, libxcb-keysyms1 0.4.1, libfmt9"