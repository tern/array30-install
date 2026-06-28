#!/usr/bin/env bash
# fix-fcitx5-hotkey.sh — 修復 Ctrl+Space 無法切換輸入法（Pop!_OS COSMIC）
set -euo pipefail

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
PROFILE="$TARGET_HOME/.config/fcitx5/profile"
CONFIG="$TARGET_HOME/.config/fcitx5/config"
PAM_ENV="$TARGET_HOME/.pam_environment"
AUTOSTART="$TARGET_HOME/.config/autostart/fcitx5.desktop"
WRAPPER="$TARGET_HOME/.local/bin/fcitx5-start-array.sh"

info() { echo "[INFO] $*"; }
ok()   { echo "[OK] $*"; }

info "更新 fcitx5 設定（ActiveByDefault、熱鍵、profile）..."

mkdir -p "$(dirname "$PROFILE")" "$(dirname "$WRAPPER")" "$(dirname "$AUTOSTART")"

# 環境變數（fcitx5 模組在 GTK/Qt 註冊為 fcitx）
cat > "$PAM_ENV" << 'EOF'
GTK_IM_MODULE DEFAULT=fcitx
QT_IM_MODULE DEFAULT=fcitx
XMODIFIERS DEFAULT=@im=fcitx
GLFW_IM_MODULE DEFAULT=ibus
EOF

# 啟用熱鍵：Ctrl+Space 與 Super+Space（fcitx5 需使用 [Hotkey/TriggerKeys] 區段格式）
cat > "$CONFIG" << 'EOF'
[Behavior]
ActiveByDefault=True
ShareInputState=No
PreloadInputMethod=True
ShowInputMethodInformation=True
EnabledAddons=chewing,array

[Hotkey]
EnumerateWithTriggerKeys=True

[Hotkey/TriggerKeys]
0=Control+space
1=Super+space

[Hotkey/EnumerateGroupForwardKeys]
0=Super+space

[Hotkey/EnumerateGroupBackwardKeys]
0=Shift+Super+space
EOF

# profile：keyboard-us + array + chewing（必須在 fcitx5 停止時寫入，否則會被覆寫）
cat > "$PROFILE" << 'EOF'
[Groups/0]
# Group Name
Name=Default
# Layout
Default Layout=us
# Default Input Method
DefaultIM=array

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

[Groups/0/Items/2]
# Name
Name=chewing
# Layout
Layout=

[GroupOrder]
0=Default
EOF

# 啟動腳本
cat > "$WRAPPER" << 'EOF'
#!/bin/bash
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
export LD_LIBRARY_PATH="$HOME/.local/lib:${LD_LIBRARY_PATH:-}"

if pgrep -x fcitx5 >/dev/null 2>&1; then
    exit 0
fi

fcitx5 -rd
sleep 2
fcitx5-remote -o 2>/dev/null || true
EOF
chmod +x "$WRAPPER"

# autostart
cat > "$AUTOSTART" << EOF
[Desktop Entry]
Name=Fcitx5
Comment=Start Fcitx5 Input Method
Exec=$WRAPPER
Type=Application
X-GNOME-Autostart-enabled=true
EOF

chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config/fcitx5" "$PAM_ENV" "$WRAPPER" "$AUTOSTART"

# 同步 /etc/environment（需 root）
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    for kv in GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx 'XMODIFIERS=@im=fcitx'; do
        key="${kv%%=*}"
        if grep -q "^${key}=" /etc/environment 2>/dev/null; then
            sed -i "s|^${key}=.*|${kv}|" /etc/environment
        else
            echo "$kv" >> /etc/environment
        fi
    done
    ok "已更新 /etc/environment"
fi

# 解除 GNOME / ibus 與 fcitx5 熱鍵衝突（Super+Space、Ctrl+Space）
if command -v gsettings &>/dev/null; then
    sudo -u "$TARGET_USER" gsettings set org.gnome.desktop.wm.keybindings switch-input-source '[]' 2>/dev/null || true
    sudo -u "$TARGET_USER" gsettings set org.gnome.desktop.wm.keybindings switch-input-source-backward '[]' 2>/dev/null || true
    sudo -u "$TARGET_USER" gsettings set org.freedesktop.ibus.general.hotkey triggers '[]' 2>/dev/null || true
    sudo -u "$TARGET_USER" gsettings set org.freedesktop.ibus.general.hotkey trigger '[]' 2>/dev/null || true
    ok "已清除 GNOME / ibus 衝突熱鍵"
fi

# 重啟 fcitx5
sudo -u "$TARGET_USER" pkill fcitx5 2>/dev/null || true
sleep 1
sudo -u "$TARGET_USER" env GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx \
    fcitx5 -rd &>/dev/null &
sleep 3
sudo -u "$TARGET_USER" fcitx5-remote -o 2>/dev/null || true

state=$(sudo -u "$TARGET_USER" fcitx5-remote 2>/dev/null || echo 0)
ok "fcitx5 狀態: $state （0=關閉 1=待命 2=啟用）"
echo ""
echo "請試："
echo "  Ctrl+Space  或  Super+Space（Windows 鍵 + 空白）切換輸入法"
echo "  fcitx5-remote -s chewing   切到注音"
echo "  fcitx5-remote -s array     切到行列30"
echo ""
echo "若仍無效，請登出再登入使環境變數生效。"