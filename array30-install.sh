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

# ── 編譯 ──────────────────────────────────────────────────────────────────

install_build_deps() {
    step "安裝編譯依賴"

    local deps=(
        build-essential cmake extra-cmake-modules git
        fcitx5 libfcitx5core-dev libfcitx5config-dev libfcitx5utils-dev fcitx5-modules-dev
        libsqlite3-dev libfmt-dev gettext pkg-config zstd
        sqlite3
    )

    # 檢查哪些套件需要安裝
    local to_install=()
    for pkg in "${deps[@]}"; do
        if ! dpkg -l "$pkg" 2>/dev/null | grep -q '^ii'; then
            to_install+=("$pkg")
        fi
    done

    if [[ ${#to_install[@]} -eq 0 ]]; then
        ok "所有編譯依賴已安裝"
        return
    fi

    info "需要安裝 ${#to_install[@]} 個套件: ${to_install[*]}"
    confirm "即將安裝以上套件，繼續？" || {
        err "編譯依賴是必要的，無法跳過"
        exit 1
    }

    need_sudo
    sudo apt-get update -qq 2>&1 | tail -1
    sudo apt-get install -y "${to_install[@]}" 2>&1 | tail -5
    ok "編譯依賴已安裝"
}

fetch_source() {
    local build_dir="$1"
    step "取得 fcitx5-array 原始碼"

    local src_url=""
    local src_version=""

    # 嘗試從 AUR PKGBUILD 取得上游 source URL
    info "從 AUR 取得 PKGBUILD..."
    local aur_dir
    aur_dir=$(mktemp -d)

    if git clone --depth 1 "$FCITX5_ARRAY_AUR" "$aur_dir/fcitx5-array" 2>/dev/null; then
        local pkgbuild="$aur_dir/fcitx5-array/PKGBUILD"
        if [[ -f "$pkgbuild" ]]; then
            # 解析 pkgver
            src_version=$(grep -oP '^pkgver=\K.*' "$pkgbuild" | tr -d '"' || true)
            # 解析 source=() 中的 URL — 替換 $pkgver
            src_url=$(grep -oP "source=\(['\"]?\K[^'\"]+" "$pkgbuild" | head -1 || true)
            if [[ -n "$src_url" ]] && [[ -n "$src_version" ]]; then
                src_url=$(echo "$src_url" | sed "s/\\\$pkgver/$src_version/g" | sed "s/\${pkgver}/$src_version/g")
                info "PKGBUILD 解析成功: v$src_version"
            else
                src_url=""
            fi
        fi
    fi

    rm -rf "$aur_dir"

    # Fallback: 直接從 GitHub repo clone
    if [[ -z "$src_url" ]]; then
        warn "PKGBUILD 解析失敗，使用 fallback: $FCITX5_ARRAY_GITHUB"
        info "從 GitHub clone fcitx5-array..."
        if git clone --depth 1 "$FCITX5_ARRAY_GITHUB" "$build_dir/fcitx5-array-src"; then
            src_version=$(cd "$build_dir/fcitx5-array-src" && git describe --tags 2>/dev/null || git rev-parse --short HEAD)
            ok "原始碼取得成功 (git: $src_version)"
            echo "$src_version" > "$build_dir/source-version.txt"
            return 0
        else
            err "無法從 GitHub 取得原始碼"
            exit 1
        fi
    fi

    # 從解析出的 URL 下載 tarball
    info "下載原始碼: $src_url"
    local tarball="$build_dir/source.tar.gz"
    if ! curl -fL "$src_url" -o "$tarball" 2>/dev/null; then
        # 重試一次
        warn "下載失敗，重試..."
        if ! curl -fL "$src_url" -o "$tarball" 2>/dev/null; then
            warn "tarball 下載失敗，嘗試 git clone fallback..."
            if git clone --depth 1 "$FCITX5_ARRAY_GITHUB" "$build_dir/fcitx5-array-src"; then
                src_version=$(cd "$build_dir/fcitx5-array-src" && git describe --tags 2>/dev/null || git rev-parse --short HEAD)
                ok "原始碼取得成功 (git fallback: $src_version)"
                echo "$src_version" > "$build_dir/source-version.txt"
                return 0
            fi
            err "無法取得原始碼"
            exit 1
        fi
    fi

    # 解壓 tarball
    mkdir -p "$build_dir/fcitx5-array-src"
    tar -xf "$tarball" -C "$build_dir/fcitx5-array-src" --strip-components=1
    echo "$src_version" > "$build_dir/source-version.txt"
    ok "原始碼取得成功: v$src_version"
}

compile_array() {
    local build_dir="$1"
    local src_dir="$build_dir/fcitx5-array-src"
    step "編譯 fcitx5-array"

    if [[ ! -d "$src_dir" ]]; then
        err "找不到原始碼目錄: $src_dir"
        exit 1
    fi

    info "執行 cmake..."
    if ! cmake -B "$build_dir/build" -S "$src_dir" \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release 2>&1 | tee "$build_dir/cmake.log" | tail -5; then
        err "cmake 設定失敗，log 已儲存到 ~/array30-build-error.log"
        cp "$build_dir/cmake.log" ~/array30-build-error.log
        exit 1
    fi

    info "編譯中..."
    if ! cmake --build "$build_dir/build" -- -j"$(nproc)" 2>&1 | tee "$build_dir/build.log" | tail -5; then
        err "編譯失敗，log 已儲存到 ~/array30-build-error.log"
        cat "$build_dir/cmake.log" "$build_dir/build.log" 2>/dev/null > ~/array30-build-error.log
        exit 1
    fi

    ok "編譯成功"
}

stage_and_install() {
    local build_dir="$1"
    step "安裝到系統"

    # Stage to temp directory
    local staging="$build_dir/staging"
    mkdir -p "$staging"
    DESTDIR="$staging" cmake --install "$build_dir/build" 2>&1 | tail -3
    ok "staging 完成"

    # 找出 staging 內的檔案
    local staged_so_dir="$staging/usr/lib/fcitx5"
    # 若 cmake install 使用了不同路徑，嘗試找
    if [[ ! -d "$staged_so_dir" ]]; then
        staged_so_dir=$(find "$staging" -name "array.so" -printf "%h" -quit 2>/dev/null || true)
    fi

    if [[ -z "$staged_so_dir" ]] || [[ ! -f "$staged_so_dir/array.so" ]]; then
        err "找不到編譯產出的 array.so"
        err "staging 目錄內容:"
        find "$staging" -type f 2>/dev/null | head -20
        exit 1
    fi

    # 建立目標目錄
    need_sudo
    sudo mkdir -p "$(dirname "$ARRAY_SO")"
    sudo mkdir -p "$(dirname "$ARRAY_DB")"
    sudo mkdir -p /usr/share/fcitx5/addon
    sudo mkdir -p /usr/share/fcitx5/inputmethod

    # 複製 .so 檔
    sudo cp "$staged_so_dir/array.so" "$ARRAY_SO"
    ok "已安裝 array.so"

    if [[ -f "$staged_so_dir/libassociation.so" ]]; then
        sudo cp "$staged_so_dir/libassociation.so" "$ASSOC_SO"
        ok "已安裝 libassociation.so"
    fi

    # 建立 libarray.so symlink
    local so_dir
    so_dir=$(dirname "$ARRAY_SO")
    sudo ln -sf "$ARRAY_SO" "$so_dir/libarray.so"
    ok "已建立 libarray.so → array.so symlink"

    # 複製 array.db
    local staged_db
    staged_db=$(find "$staging" -name "array.db" -type f -print -quit 2>/dev/null || true)
    if [[ -n "$staged_db" ]]; then
        sudo cp "$staged_db" "$ARRAY_DB"
        ok "已安裝 array.db"
    else
        warn "staging 中找不到 array.db，可能需要 update-table 來建立"
    fi

    # 複製 .conf 檔
    local staged_addon
    staged_addon=$(find "$staging" -path "*/addon/array.conf" -type f -print -quit 2>/dev/null || true)
    if [[ -n "$staged_addon" ]]; then
        sudo cp "$staged_addon" /usr/share/fcitx5/addon/array.conf
        ok "已安裝 addon/array.conf"
    fi

    local staged_im
    staged_im=$(find "$staging" -path "*/inputmethod/array.conf" -type f -print -quit 2>/dev/null || true)
    if [[ -n "$staged_im" ]]; then
        sudo cp "$staged_im" /usr/share/fcitx5/inputmethod/array.conf
        ok "已安裝 inputmethod/array.conf"
    fi

    # 記錄版本
    mkdir -p "$BACKUP_DIR"
    if [[ -f "$build_dir/source-version.txt" ]]; then
        cp "$build_dir/source-version.txt" "$VERSION_FILE"
        ok "已記錄安裝版本: $(cat "$VERSION_FILE")"
    fi

    ok "fcitx5-array 檔案已安裝到系統"
}

# ── fcitx5 Profile 管理 ──────────────────────────────────────────────────

setup_profile() {
    step "設定 fcitx5 Profile"

    if [[ ! -f "$FCITX5_PROFILE" ]]; then
        info "建立 fcitx5 profile（含 keyboard-us + array）"
        mkdir -p "$(dirname "$FCITX5_PROFILE")"
        cat > "$FCITX5_PROFILE" << 'PROFEOF'
[Groups/0]
# Group Name
Name=預設
# Layout
Default Layout=us
# Default Input Method
DefaultIM=keyboard-us

[Groups/0/Items/0]
# Name
Name=keyboard-us
# Layout
Layout=

[Groups/0/Items/1]
# Name
Name=array
# Layout
Layout=

[GroupOrder]
0=預設
PROFEOF
        ok "已建立 profile 並加入 array"
        return
    fi

    # 備份 profile
    cp "$FCITX5_PROFILE" "$FCITX5_PROFILE.bak.$(date +%s)"

    # 檢查是否已有 array (native)
    if grep -q "Name=array$" "$FCITX5_PROFILE"; then
        ok "原生 array 已在 profile 中"
        return
    fi

    # 在 profile 中加入 array
    local max_idx
    max_idx=$(grep -oP 'Groups/0/Items/\K[0-9]+' "$FCITX5_PROFILE" | sort -n | tail -1)

    if [[ -n "$max_idx" ]]; then
        local new_idx=$((max_idx + 1))
        sed -i "/^\[GroupOrder\]/i\\
[Groups/0/Items/$new_idx]\\
# Name\\
Name=array\\
# Layout\\
Layout=\\
" "$FCITX5_PROFILE"
        ok "已將原生 array 加入 profile (Items/$new_idx)"
    else
        warn "無法自動修改 profile，請用 fcitx5-configtool 手動新增"
    fi
}

restart_fcitx5() {
    step "重啟 fcitx5"
    pkill fcitx5 2>/dev/null || true
    sleep 1
    fcitx5 -rd &>/dev/null &
    disown
    sleep 2
    ok "fcitx5 已重啟"
}

verify_array_loaded() {
    pkill fcitx5 2>/dev/null || true
    sleep 1
    FCITX_LOG=default=5 fcitx5 -rd &>/tmp/fcitx5-array-verify.log &
    disown
    sleep 3

    if grep -q "Loaded addon array" /tmp/fcitx5-array-verify.log 2>/dev/null; then
        ok "array addon 載入成功"
        return 0
    else
        local error
        error=$(grep -i "Failed.*array\|Could not load addon array" /tmp/fcitx5-array-verify.log 2>/dev/null || true)
        if [[ -n "$error" ]]; then
            err "$error"
        fi
        return 1
    fi
}

# ── Stub functions ────────────────────────────────────────────────────────

do_install() {
    step "行列30 (fcitx5-array) 安裝程序"
    echo ""
    info "此腳本將:"
    info "  1. 檢查環境並設定繁體中文語系"
    info "  2. 安裝 fcitx5 輸入法框架（如需要）"
    info "  3. 原生編譯 fcitx5-array"
    info "  4. 安裝並設定行列30輸入法"
    echo ""

    # 前置檢查
    check_ubuntu
    check_network
    check_disk_space

    # 語系與 fcitx5
    setup_locale
    setup_fcitx5

    # 備份現有安裝
    if [[ -f "$ARRAY_SO" ]] || [[ -f "$ARRAY_DB" ]]; then
        do_backup
    fi

    # 編譯依賴
    install_build_deps

    # 建立暫存目錄
    local build_dir
    build_dir=$(mktemp -d /tmp/array30-build-XXXX)
    trap "rm -rf $build_dir" EXIT

    # 取得原始碼 + 編譯 + 安裝
    fetch_source "$build_dir"
    compile_array "$build_dir"
    stage_and_install "$build_dir"

    # 設定 profile + 重啟
    setup_profile
    restart_fcitx5

    # 驗證
    step "驗證安裝結果"
    sleep 2
    if verify_array_loaded; then
        echo ""
        ok "================================================"
        ok "  行列30 (fcitx5-array) 安裝成功！"
        ok "  按 Ctrl+Space 切換輸入法"
        ok "  支援 W+數字 符號輸入、簡碼、萬用字元"
        ok "================================================"
    else
        err "安裝完成但 array addon 載入失敗"
        err "請執行 ./array30-install.sh diagnose 檢查問題"
        exit 1
    fi
}

do_update_table() { err "update-table: 尚未實作"; exit 1; }
do_diagnose()     { err "diagnose: 尚未實作"; exit 1; }
do_uninstall()    { err "uninstall: 尚未實作"; exit 1; }

do_backup() {
    step "備份目前的 fcitx5-array 檔案"
    mkdir -p "$BACKUP_DIR"
    local ts
    ts=$(date +%Y%m%d-%H%M%S)
    local bak="$BACKUP_DIR/$ts"
    mkdir -p "$bak"

    [[ -f "$ARRAY_SO" ]]    && cp "$ARRAY_SO" "$bak/array.so"    && ok "已備份 array.so"
    [[ -f "$ASSOC_SO" ]]    && cp "$ASSOC_SO" "$bak/libassociation.so" && ok "已備份 libassociation.so"
    [[ -f "$ARRAY_DB" ]]    && cp "$ARRAY_DB" "$bak/array.db"    && ok "已備份 array.db"
    [[ -f /usr/share/fcitx5/addon/array.conf ]]      && cp /usr/share/fcitx5/addon/array.conf "$bak/addon-array.conf"
    [[ -f /usr/share/fcitx5/inputmethod/array.conf ]] && cp /usr/share/fcitx5/inputmethod/array.conf "$bak/inputmethod-array.conf"

    # metadata
    {
        echo "timestamp=$ts"
        echo "fcitx5_version=$(fcitx5 --version 2>/dev/null | head -1 || echo unknown)"
        echo "source_version=$(cat "$VERSION_FILE" 2>/dev/null || echo unknown)"
        if [[ -f "$ARRAY_DB" ]] && command -v sqlite3 &>/dev/null; then
            echo "db_main_count=$(sqlite3 "$ARRAY_DB" "SELECT count(*) FROM main;" 2>/dev/null || echo 0)"
            echo "db_simple_count=$(sqlite3 "$ARRAY_DB" "SELECT count(*) FROM simple;" 2>/dev/null || echo 0)"
            echo "db_phrase_count=$(sqlite3 "$ARRAY_DB" "SELECT count(*) FROM phrase;" 2>/dev/null || echo 0)"
        fi
    } > "$bak/metadata.txt"

    ok "備份完成: $bak"
}

do_restore() {
    step "從備份還原"

    if [[ ! -d "$BACKUP_DIR" ]]; then
        err "找不到備份目錄 $BACKUP_DIR"
        exit 1
    fi

    # 列出可用備份
    echo "可用的備份:"
    local backups=()
    while IFS= read -r -d '' dir; do
        local name
        name=$(basename "$dir")
        if [[ -f "$dir/array.db" ]] || [[ -f "$dir/array.so" ]]; then
            backups+=("$name")
            local meta
            meta=$(cat "$dir/metadata.txt" 2>/dev/null || echo "metadata 遺失")
            echo "  $((${#backups[@]}))) $name"
            echo "$meta" | head -3 | sed 's/^/       /'
        fi
    done < <(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

    if [[ ${#backups[@]} -eq 0 ]]; then
        err "沒有找到可用的備份"
        exit 1
    fi

    read -rp "選擇要還原的備份編號 [1-${#backups[@]}]: " choice
    if [[ -z "$choice" ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt ${#backups[@]} ]]; then
        err "無效的選擇"
        exit 1
    fi

    local selected="${backups[$((choice-1))]}"
    local src="$BACKUP_DIR/$selected"

    need_sudo
    [[ -f "$src/array.so" ]]    && sudo cp "$src/array.so" "$ARRAY_SO"    && ok "已還原 array.so"
    [[ -f "$src/libassociation.so" ]] && sudo cp "$src/libassociation.so" "$ASSOC_SO" && ok "已還原 libassociation.so"
    [[ -f "$src/array.db" ]]    && sudo cp "$src/array.db" "$ARRAY_DB"    && ok "已還原 array.db"
    [[ -f "$src/addon-array.conf" ]]      && sudo cp "$src/addon-array.conf" /usr/share/fcitx5/addon/array.conf
    [[ -f "$src/inputmethod-array.conf" ]] && sudo cp "$src/inputmethod-array.conf" /usr/share/fcitx5/inputmethod/array.conf

    restart_fcitx5
    ok "還原完成"
}

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
