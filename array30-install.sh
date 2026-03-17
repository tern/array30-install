#!/usr/bin/env bash
# ============================================================================
# array30-install.sh — 行列30輸入法安裝工具 (fcitx5-array) for Ubuntu
# https://github.com/tern/array30-install
#
# Ubuntu 24.04+ 專用，原生編譯，無需容器。
#
# 用法:
#   ./array30-install.sh install        # 全自動安裝
#   ./array30-install.sh uninstall      # 移除 fcitx5-array
#   ./array30-install.sh update-table   # 線上更新行列30字根表
#   ./array30-install.sh diagnose       # 診斷目前安裝狀態
#   ./array30-install.sh backup         # 手動備份
#   ./array30-install.sh restore        # 從備份還原
#
# 授權: GPL-2.0-or-later
# ============================================================================

set -euo pipefail

# ── 常數 ──────────────────────────────────────────────────────────────────
SCRIPT_VERSION="1.0.0"

# 上游來源
FCITX5_ARRAY_AUR="https://aur.archlinux.org/fcitx5-array.git"
FCITX5_ARRAY_GITHUB="https://github.com/ray2501/fcitx5-array"
ARRAY30_CIN_RAW="https://raw.githubusercontent.com/gontera/array30/master"

# 系統路徑（Ubuntu multiarch）
ARRAY_SO="/usr/lib/x86_64-linux-gnu/fcitx5/array.so"
ASSOC_SO="/usr/lib/x86_64-linux-gnu/fcitx5/libassociation.so"
ARRAY_DB="/usr/share/fcitx5/array/array.db"
BACKUP_DIR="$HOME/.local/share/array30-backup"
FCITX5_PROFILE="$HOME/.config/fcitx5/profile"
VERSION_FILE="$BACKUP_DIR/installed-version.txt"

# 顏色（pipe 模式自動關閉）
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' NC=''
fi

# pipe 模式偵測（用於跳過互動確認）
IS_PIPE=false
[[ ! -t 0 ]] && IS_PIPE=true

# ── 工具函式 ──────────────────────────────────────────────────────────────

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
step()  { echo -e "\n${CYAN}── $* ──${NC}"; }

confirm() {
    local prompt="${1:-Continue?}"
    if [[ "$IS_PIPE" == true ]]; then
        return 0  # pipe 模式自動確認
    fi
    read -rp "$(echo -e "${YELLOW}$prompt [y/N]${NC} ")" ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

need_sudo() {
    if ! sudo -n true 2>/dev/null; then
        info "需要 sudo 權限來安裝套件到系統目錄"
    fi
}

# ── 環境檢查 ──────────────────────────────────────────────────────────────

check_ubuntu() {
    # 檢查 x86_64
    local arch
    arch=$(uname -m)
    if [[ "$arch" != "x86_64" ]]; then
        err "此工具僅支援 x86_64 架構（偵測到: $arch）"
        exit 1
    fi

    # 檢查 Ubuntu 24.04+
    if [[ ! -f /etc/os-release ]]; then
        err "找不到 /etc/os-release，無法識別作業系統"
        exit 1
    fi

    local id version_id
    id=$(grep -oP '^ID=\K.*' /etc/os-release | tr -d '"')
    version_id=$(grep -oP '^VERSION_ID=\K.*' /etc/os-release | tr -d '"')

    if [[ "$id" != "ubuntu" ]]; then
        err "此工具僅支援 Ubuntu（偵測到: $id）"
        exit 1
    fi

    # 比較版本：24.04+
    local major minor
    major=$(echo "$version_id" | cut -d. -f1)
    minor=$(echo "$version_id" | cut -d. -f2)
    if [[ "$major" -lt 24 ]] || { [[ "$major" -eq 24 ]] && [[ "$minor" -lt 4 ]]; }; then
        err "需要 Ubuntu 24.04 或更新版本（偵測到: $version_id）"
        exit 1
    fi

    ok "Ubuntu $version_id (x86_64)"
}

check_network() {
    if ! curl -fsI https://github.com --connect-timeout 5 &>/dev/null; then
        err "無法連線到網路（嘗試連線 github.com 失敗）"
        exit 1
    fi
    ok "網路連線正常"
}

check_disk_space() {
    local avail_mb
    avail_mb=$(df -BM --output=avail / | tail -1 | tr -d ' M')
    if [[ "$avail_mb" -lt 1500 ]]; then
        warn "磁碟空間不足（可用: ${avail_mb}MB，建議: 1500MB+）"
        warn "編譯過程需要暫存空間，可能導致失敗"
    else
        ok "磁碟空間: ${avail_mb}MB 可用"
    fi
}

# ── 語系與輸入法設定 ──────────────────────────────────────────────────────

setup_locale() {
    step "檢查繁體中文語系"

    # 檢查 zh_TW.UTF-8 locale 是否已產生
    if locale -a 2>/dev/null | grep -qi 'zh_TW\.utf-\?8'; then
        ok "繁體中文語系 (zh_TW.UTF-8) 已安裝"
    else
        warn "未偵測到繁體中文語系 (zh_TW.UTF-8)"
        confirm "系統目前非繁體中文環境，即將安裝繁體中文語系並切換，繼續？" || {
            info "跳過語系設定"
            return
        }

        info "安裝繁體中文語言套件..."
        need_sudo

        # 基本語言套件
        sudo apt-get install -y language-pack-zh-hant fonts-noto-cjk 2>&1 | tail -3

        # GNOME 桌面額外套件
        if [[ "${XDG_CURRENT_DESKTOP:-}" == *"GNOME"* ]]; then
            sudo apt-get install -y language-pack-gnome-zh-hant 2>&1 | tail -3
        fi

        # 產生 locale
        sudo locale-gen zh_TW.UTF-8 2>&1 | tail -1
        sudo update-locale LANG=zh_TW.UTF-8

        # 切換桌面 UI 語系
        if [[ "${XDG_CURRENT_DESKTOP:-}" == *"GNOME"* ]]; then
            gsettings set org.gnome.system.locale region 'zh_TW.UTF-8' 2>/dev/null || true
        fi

        ok "繁體中文語系已安裝"
        warn "語系切換需要登出再登入才會完全生效"
        info "fcitx5-array 安裝不受影響，將繼續進行"
    fi
}

setup_fcitx5() {
    step "檢查 fcitx5 輸入法框架"

    if command -v fcitx5 &>/dev/null; then
        ok "fcitx5 已安裝: $(fcitx5 --version 2>/dev/null | head -1)"
    else
        info "fcitx5 未安裝，開始安裝..."
        confirm "即將安裝 fcitx5 輸入法框架及相關套件，繼續？" || {
            err "fcitx5 是必要元件，無法跳過"
            exit 1
        }
        need_sudo
        sudo apt-get install -y fcitx5 fcitx5-chinese-addons 2>&1 | tail -3
        ok "fcitx5 已安裝"
    fi

    # 確保 libfmt runtime 存在
    if ! dpkg -l 'libfmt[0-9]*' 2>/dev/null | grep -q '^ii'; then
        info "安裝 libfmt runtime..."
        need_sudo
        sudo apt-get install -y libfmt9 2>&1 | tail -2
    fi

    # 設定 fcitx5 為預設輸入法框架
    if command -v im-config &>/dev/null; then
        im-config -n fcitx5 2>/dev/null || true
    fi

    # 設定 IM 環境變數
    setup_im_env
}

setup_im_env() {
    local profile_file="$HOME/.profile"
    local marker="# fcitx5 輸入法環境變數（由 array30-install.sh 自動新增）"

    # 用 marker 偵測是否已經設定過，避免重複寫入
    if grep -qF "$marker" "$profile_file" 2>/dev/null; then
        return
    fi

    info "設定輸入法環境變數到 $profile_file"
    {
        echo ""
        echo "$marker"
        echo "export GTK_IM_MODULE=fcitx"
        echo "export QT_IM_MODULE=fcitx"
        echo 'export XMODIFIERS=@im=fcitx'
    } >> "$profile_file"
    ok "已寫入 IM 環境變數"
}

# ── Stub functions ────────────────────────────────────────────────────────

do_install()      { err "install: 尚未實作"; exit 1; }
do_update_table() { err "update-table: 尚未實作"; exit 1; }
do_diagnose()     { err "diagnose: 尚未實作"; exit 1; }
do_uninstall()    { err "uninstall: 尚未實作"; exit 1; }
do_backup()       { err "backup: 尚未實作"; exit 1; }
do_restore()      { err "restore: 尚未實作"; exit 1; }

# ── 主程式 ────────────────────────────────────────────────────────────────

show_help() {
    cat << 'EOF'
行列30輸入法安裝工具 (fcitx5-array) — Ubuntu 24.04+ 專用

用法: ./array30-install.sh <command>

Commands:
  install        全自動安裝 fcitx5-array
                 偵測環境 → 安裝中文語系 → 原生編譯 → 安裝

  update-table   線上更新行列30字根表
                 從 gontera/array30 下載最新 CIN 字根表並重建 array.db

  diagnose       診斷目前安裝狀態
                 檢查套件、檔案、ABI、字根表、Profile 及 addon 載入

  uninstall      移除 fcitx5-array 並切回 table-based array30

  backup         手動備份目前的 array.so/array.db/conf 檔案

  restore        從備份還原

  help           顯示此說明

行列30 vs table-based array30:
  原生 fcitx5-array 支援：
    - W+數字鍵 符號輸入（接近 Windows 行列體驗）
    - 一級/二級簡碼
    - 萬用字元查詢（? 和 *）
    - 詞組輸入
    - 聯想詞
    - 反查碼（Ctrl+Alt+E）

  table-based array30:
    - 基本行列輸入，不支援上述進階功能

Version: v1.0.0
License: GPL-2.0-or-later
EOF
}

main() {
    local cmd="${1:-help}"
    case "$cmd" in
        install)       do_install ;;
        update-table)  do_update_table ;;
        diagnose)      do_diagnose ;;
        uninstall)     do_uninstall ;;
        backup)        do_backup ;;
        restore)       do_restore ;;
        help|--help|-h) show_help ;;
        *)
            err "未知的命令: $cmd"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
