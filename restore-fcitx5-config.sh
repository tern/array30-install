#!/usr/bin/env bash
# restore-fcitx5-config.sh — 從備份還原 fcitx5 輸入法設定
set -euo pipefail

TARGET_HOME="${HOME}"
SAVE_DIR="$TARGET_HOME/.local/share/fcitx5-config-saved"
SRC="${1:-$SAVE_DIR/latest}"

info() { echo "[INFO] $*"; }
ok()   { echo "[OK] $*"; }
err()  { echo "[ERR] $*" >&2; }

if [[ ! -d "$SRC" ]]; then
    err "找不到備份: $SRC"
    exit 1
fi

info "從 $SRC 還原 fcitx5 設定..."

pkill fcitx5 2>/dev/null || true
sleep 1

mkdir -p "$TARGET_HOME/.config/fcitx5" "$TARGET_HOME/.config/autostart" "$TARGET_HOME/.local/bin"

[[ -f "$SRC/profile" ]] && cp "$SRC/profile" "$TARGET_HOME/.config/fcitx5/profile" && ok "已還原 profile"
[[ -f "$SRC/config" ]] && cp "$SRC/config" "$TARGET_HOME/.config/fcitx5/config" && ok "已還原 config"
[[ -f "$SRC/pam_environment" ]] && cp "$SRC/pam_environment" "$TARGET_HOME/.pam_environment" && ok "已還原 pam_environment"
[[ -f "$SRC/fcitx5.desktop" ]] && cp "$SRC/fcitx5.desktop" "$TARGET_HOME/.config/autostart/fcitx5.desktop" && ok "已還原 autostart"
[[ -f "$SRC/fcitx5-start-array.sh" ]] && cp "$SRC/fcitx5-start-array.sh" "$TARGET_HOME/.local/bin/fcitx5-start-array.sh" && chmod +x "$TARGET_HOME/.local/bin/fcitx5-start-array.sh" && ok "已還原啟動腳本"

if command -v gsettings &>/dev/null; then
    gsettings set org.gnome.desktop.wm.keybindings switch-input-source '[]' 2>/dev/null || true
    gsettings set org.gnome.desktop.wm.keybindings switch-input-source-backward '[]' 2>/dev/null || true
    gsettings set org.freedesktop.ibus.general.hotkey trigger '[]' 2>/dev/null || true
    gsettings set org.freedesktop.ibus.general.hotkey triggers '[]' 2>/dev/null || true
    ok "已清除 GNOME / ibus 衝突熱鍵"
fi

export GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx
fcitx5 -rd &>/dev/null &
sleep 3
fcitx5-remote -o 2>/dev/null || true

ok "還原完成。目前輸入法: $(fcitx5-remote -n 2>/dev/null || echo unknown)"