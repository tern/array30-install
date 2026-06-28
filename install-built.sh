#!/usr/bin/env bash
# install-built.sh — 將 ~/.local 內已編譯的 fcitx5-array 安裝到系統路徑
#
# 前置： ARRAY30_ENGINE=fcitx5 bash array30-install.sh install（或已有 ~/.local/lib/fcitx5/array.so）
# 用法： bash install-built.sh
# 說明： docs/POP-OS.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MULTIARCH=$(gcc -print-multiarch 2>/dev/null || echo "x86_64-linux-gnu")
ARRAY_SO="/usr/lib/$MULTIARCH/fcitx5/array.so"
ASSOC_SO="/usr/lib/$MULTIARCH/fcitx5/libassociation.so"
ARRAY_DB="/usr/share/fcitx5/array/array.db"

if ! sudo -n true 2>/dev/null; then
    echo "[INFO] 需要 sudo 權限..."
fi

# 若 apt 因手動升級 fcitx5 5.1.12 而損壞，先修復 libxcb 相依
if ! apt-get check &>/dev/null || {
    dpkg -l fcitx5-modules 2>/dev/null | grep -q '5.1.12' \
    && dpkg -l libxcb-ewmh2 2>/dev/null | grep -q '0.4.1'
}; then
    echo "[INFO] 偵測到 fcitx5/libxcb 相依問題，先執行 fix-apt-deps.sh..."
    sudo bash "$SCRIPT_DIR/fix-apt-deps.sh"
fi

if [[ ! -f "$HOME/.local/lib/fcitx5/array.so" ]]; then
    echo "[ERROR] 找不到編譯產物 ~/.local/lib/fcitx5/array.so"
    echo "請先執行： ARRAY30_ENGINE=fcitx5 bash array30-install.sh install"
    exit 1
fi

sudo apt-get install -y libfmt9
sudo mkdir -p "$(dirname "$ARRAY_SO")" "$(dirname "$ARRAY_DB")" /usr/share/fcitx5/addon /usr/share/fcitx5/inputmethod

sudo cp "$HOME/.local/lib/fcitx5/array.so" "$ARRAY_SO"
sudo cp "$HOME/.local/lib/fcitx5/libassociation.so" "$ASSOC_SO"
sudo ln -sf array.so "$(dirname "$ARRAY_SO")/libarray.so"
sudo cp "$HOME/.local/share/fcitx5/array/array.db" "$ARRAY_DB"
sudo cp "$HOME/.local/share/fcitx5/addon/array.conf" /usr/share/fcitx5/addon/
sudo cp "$HOME/.local/share/fcitx5/addon/association.conf" /usr/share/fcitx5/addon/
sudo cp "$HOME/.local/share/fcitx5/inputmethod/array.conf" /usr/share/fcitx5/inputmethod/

cat > "$HOME/.config/fcitx5/profile" << 'EOF'
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

[GroupOrder]
0=Default
EOF

pkill fcitx5 2>/dev/null || true
sleep 1
fcitx5 -rd
sleep 2
fcitx5-remote -s array
sleep 1
current_im=$(fcitx5-remote -n 2>/dev/null || true)
echo "Current IM: ${current_im:-未知}"
if [[ "$current_im" == "array" ]]; then
    echo "[OK] 行列30 (fcitx5-array) 已安裝並可切換（Ctrl+Space）"
else
    echo "[WARN] 檔案已安裝，但尚未切換到 array。請執行： fcitx5-remote -s array"
    echo "       或執行： bash array30-install.sh diagnose"
fi