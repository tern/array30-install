# Pop!_OS 24.04 安裝紀錄（COSMIC 桌面）

本文整理在 **Pop!_OS 24.04 LTS（COSMIC / Wayland）** 上安裝原生 **fcitx5-array** 行列30的實際過程、踩坑與解法。已驗證可正常使用（`fcitx5-remote -n` → `array`）。

## 環境摘要

| 項目 | 值 |
|------|-----|
| 發行版 | Pop!_OS 24.04 LTS（`ID=pop`, `ID_LIKE=ubuntu debian`） |
| 桌面 | COSMIC（Wayland） |
| 架構 | x86_64 |
| fcitx5 | 5.1.12-2（曾手動升級，見下文） |
| 語系 | zh_TW.UTF-8 |

## 推薦安裝流程

```bash
git clone https://github.com/tern/array30-install.git
cd array30-install

# 1. 全自動安裝（編譯 + 安裝到系統）
ARRAY30_ENGINE=fcitx5 bash array30-install.sh install

# 若曾手動升級 fcitx5 5.1.12 導致 apt 損壞，先修復：
sudo bash fix-apt-deps.sh

# 若已編譯完成、只需複製到系統（較快）：
bash install-built.sh

# 2. 驗證
bash array30-install.sh diagnose
fcitx5-remote -n          # 應顯示 array
```

安裝完成後以 **Ctrl+Space** 切換輸入法。若登入後不是行列30：

```bash
fcitx5-remote -s array
```

## 實際處理過程（問題 → 原因 → 解法）

### 1. `array30-install.sh` 拒絕 Pop!_OS

**現象：** `此工具僅支援 Ubuntu（偵測到: pop）`

**原因：** 早期版本只檢查 `ID=ubuntu`。

**解法：** v1.1.1 起接受 `ubuntu`、`pop` 及 `ID_LIKE` 含 `ubuntu` 的發行版。

---

### 2. `diagnose` 中途退出

**現象：** 報告只印到「fcitx5-table-array30: 未安裝」就結束，exit code 1。

**原因：** `set -euo pipefail` 下，`libfmt` 未安裝時 `dpkg -l 'libfmt*' | ...` 管道失敗。

**解法：** 查詢改為 `... || true`；apt 檢查區分「需 root」與「真的損壞」。

---

### 3. apt 相依關係損壞（`libfmt9` 裝不上）

**現象：**

```
E: 未能滿足相依關係
 fcitx5-modules : 相依關係: libxcb-ewmh2 (>= 0.4.2) 但 0.4.1-1.1build3 卻將被安裝
```

**原因：** 曾用 `dpkg -i --force-depends` 手動裝上 **fcitx5 5.1.12**（例如 `install-fcitx5-upgrade.sh`），但 Pop!_OS 官方源仍提供較舊的 `libxcb-*`：

| 套件 | Pop!_OS 內建 | fcitx5-modules 5.1.12 需要 |
|------|-------------|---------------------------|
| libxcb-ewmh2 | 0.4.1 | **≥ 0.4.2** |
| libxcb-icccm4 | 0.4.1 | **≥ 0.4.2** |
| libxcb-keysyms1 | 0.4.0 | **≥ 0.4.1** |

**解法：** 執行 `fix-apt-deps.sh`，從 Ubuntu archive 安裝新版 libxcb，再 `apt-get --fix-broken install` 與 `libfmt9`。

```bash
sudo bash fix-apt-deps.sh
```

> **建議：** 在 Pop!_OS 上不要手動 `dpkg -i --force-depends` 升級 fcitx5；優先使用本工具的原生編譯路徑，或維持發行版預設的 fcitx5 5.1.7。

---

### 4. `fix-apt-deps.sh`：`tmpdir: 未綁定的變數`

**現象：** 腳本結束時報 `tmpdir: 未綁定的變數`（`set -u`）。

**原因：** 在函式內用 `local tmpdir` 設了 `trap EXIT`，函式返回後區域變數失效，但 trap 仍在。

**解法：** 改為腳本層級變數，並在成功結束前 `trap - EXIT` 後手動清理。

---

### 5. 編譯產物在 `~/.local`，fcitx5 找不到 addon

**現象：** `~/.local/lib/fcitx5/array.so` 存在，但輸入法無法載入；`strace` 顯示 fcitx5 只從 `/usr/lib/x86_64-linux-gnu/fcitx5/` 載入 `.so`。

**原因：** Ubuntu 版 fcitx5 的 addon loader 固定搜尋系統路徑（`Library=array` → `libarray.so`），`FCITX_ADDON_DIRS` 對使用者路徑不可靠。

**解法：** 用 `install-built.sh` 複製到系統目錄：

```
/usr/lib/x86_64-linux-gnu/fcitx5/array.so
/usr/lib/x86_64-linux-gnu/fcitx5/libarray.so  → array.so
/usr/share/fcitx5/array/array.db
/usr/share/fcitx5/addon/array.conf
/usr/share/fcitx5/inputmethod/array.conf
```

---

### 6. Profile 被 fcitx5 自動改回 pinyin

**現象：** `~/.config/fcitx5/profile` 設了 `DefaultIM=array`，重啟後變回 `pinyin`。

**原因：** array addon 尚未裝進系統時，fcitx5 啟動會剔除無效輸入法並改寫 profile。

**解法：** 先完成系統安裝，再設定 profile 並重啟：

```bash
bash install-built.sh
# 或確認 diagnose 顯示 fcitx5-array (系統): 已安裝 後
fcitx5-remote -s array
```

---

## COSMIC 桌面注意事項

- 環境變數建議寫入 `~/.pam_environment`（本工具 `install` 會寫入 `/etc/environment`）：

  ```ini
  GTK_IM_MODULE DEFAULT=fcitx5
  QT_IM_MODULE DEFAULT=fcitx5
  XMODIFIERS DEFAULT=@im=fcitx5
  ```

- **原生 COSMIC 應用**（Launcher、檔案管理員等）IME 支援仍有限；請在 **Firefox、Chrome、VS Code、LibreOffice** 等 GTK/Qt 應用中輸入中文。
- 變更 `/etc/environment` 後建議**登出再登入**。

## 成功指標

`bash array30-install.sh diagnose` 應大致顯示：

- `fcitx5-array (系統): 已安裝`
- `【關鍵檔案】` 系統路徑皆 `[OK]`
- `【ABI 相容性】` `[OK]`
- `【字根表統計】` 主表約 117,000 筆
- `【Addon 載入測試】` 可切換至 array

日誌中可見：

```
Loaded addon array
OK: found array.db!!!
```

## 相關腳本

| 腳本 | 用途 |
|------|------|
| `array30-install.sh` | 主程式：install / diagnose / update-table / … |
| `fix-apt-deps.sh` | 修復 Pop!_OS 上 fcitx5 5.1.12 與 libxcb 不相容 |
| `install-built.sh` | 將 `~/.local` 編譯產物安裝到系統（會自動呼叫 fix-apt-deps） |

## 參考

- [gontera/array30](https://github.com/gontera/array30) — 官方字根表
- [ray2501/fcitx5-array](https://github.com/ray2501/fcitx5-array) — 原生引擎