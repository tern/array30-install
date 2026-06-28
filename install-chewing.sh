#!/usr/bin/env bash
# install-chewing.sh — 安裝 fcitx5 新酷音（注音輸入法）
set -euo pipefail

FCITX5_PROFILE="${HOME}/.config/fcitx5/profile"

info()  { echo "[INFO] $*"; }
ok()    { echo "[OK] $*"; }
warn()  { echo "[WARN] $*"; }

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    if ! sudo -n true 2>/dev/null; then
        echo "[INFO] 需要 sudo 權限安裝 fcitx5-chewing"
    fi
    exec sudo bash "$0"
fi

info "安裝 fcitx5-chewing（新酷音 / 注音）..."
apt-get install -y fcitx5-chewing

# 以實際使用者身份更新 profile（sudo 下取 SUDO_USER）
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
PROFILE="$TARGET_HOME/.config/fcitx5/profile"

if [[ ! -f "$PROFILE" ]] || ! grep -q '^Name=chewing$' "$PROFILE" 2>/dev/null; then
    # 直接寫入完整 profile，避免 sed 破壞結構或被 fcitx5 覆寫後缺 chewing
    cat > "$PROFILE" << 'PROFEOF'
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=array

[Groups/0/Items/0]
Name=keyboard-us
Layout=

[Groups/0/Items/1]
Name=array
Layout=

[Groups/0/Items/2]
Name=chewing
Layout=

[GroupOrder]
0=Default
PROFEOF
    ok "已更新 profile（keyboard-us + array + chewing）"
else
    ok "chewing 已在 profile 中"
fi
chown "$TARGET_USER:$TARGET_USER" "$PROFILE"

# 重啟 fcitx5（以使用者身份）
if id "$TARGET_USER" &>/dev/null; then
    sudo -u "$TARGET_USER" pkill fcitx5 2>/dev/null || true
    sleep 1
    sudo -u "$TARGET_USER" fcitx5 -rd &>/dev/null &
    sleep 2
fi

ok "新酷音（注音）已安裝"
echo "切換方式：Ctrl+Space 或執行 fcitx5-remote -s chewing"