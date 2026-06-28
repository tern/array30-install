#!/usr/bin/env bash
# save-fcitx5-config.sh — 保存目前可用的 fcitx5 輸入法設定
set -euo pipefail

TARGET_HOME="${HOME}"
SAVE_DIR="$TARGET_HOME/.local/share/fcitx5-config-saved"
TS=$(date +%Y%m%d-%H%M%S)
DEST="$SAVE_DIR/$TS"

info() { echo "[INFO] $*"; }
ok()   { echo "[OK] $*"; }

mkdir -p "$DEST"

info "保存 fcitx5 設定到 $DEST ..."

for f in profile config; do
    if [[ -f "$TARGET_HOME/.config/fcitx5/$f" ]]; then
        cp "$TARGET_HOME/.config/fcitx5/$f" "$DEST/$f"
        ok "已保存 fcitx5/$f"
    fi
done

[[ -f "$TARGET_HOME/.pam_environment" ]] && cp "$TARGET_HOME/.pam_environment" "$DEST/pam_environment"
[[ -f "$TARGET_HOME/.config/autostart/fcitx5.desktop" ]] && cp "$TARGET_HOME/.config/autostart/fcitx5.desktop" "$DEST/fcitx5.desktop"
[[ -f "$TARGET_HOME/.local/bin/fcitx5-start-array.sh" ]] && cp "$TARGET_HOME/.local/bin/fcitx5-start-array.sh" "$DEST/fcitx5-start-array.sh"

if command -v gsettings &>/dev/null; then
    {
        echo "switch-input-source=$(gsettings get org.gnome.desktop.wm.keybindings switch-input-source)"
        echo "switch-input-source-backward=$(gsettings get org.gnome.desktop.wm.keybindings switch-input-source-backward)"
        echo "ibus-trigger=$(gsettings get org.freedesktop.ibus.general.hotkey trigger)"
        echo "ibus-triggers=$(gsettings get org.freedesktop.ibus.general.hotkey triggers)"
    } > "$DEST/gsettings.txt"
    ok "已保存 gsettings"
fi

{
    echo "timestamp=$TS"
    echo "fcitx5_version=$(fcitx5 --version 2>/dev/null | head -1 || echo unknown)"
    echo "current_im=$(fcitx5-remote -n 2>/dev/null || echo unknown)"
    echo "fcitx5_running=$(pgrep -c fcitx5 2>/dev/null || echo 0)"
    grep -E '^(GTK_IM_MODULE|QT_IM_MODULE|XMODIFIERS)=' /etc/environment 2>/dev/null || true
} > "$DEST/metadata.txt"

ln -sfn "$DEST" "$SAVE_DIR/latest"
ok "已建立捷徑: $SAVE_DIR/latest -> $DEST"
echo ""
echo "設定已保存。還原請執行："
echo "  bash ~/array30-install/restore-fcitx5-config.sh"