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
