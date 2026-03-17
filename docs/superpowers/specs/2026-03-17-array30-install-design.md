# array30-install 設計規格

Ubuntu 24.04 專用的 fcitx5-array（行列30）全自動安裝工具。原生編譯，無需容器。

## 背景

現有的 `steamdeck-array30` 使用容器編譯 fcitx5-array 以解決 SteamOS 的 ABI 相容性問題。在 Ubuntu 上可以直接透過 apt 安裝 build dependencies 後原生編譯，不需要容器，流程大幅簡化。

### 為什麼需要 fcitx5-array

預設的 table-based array30 功能受限。fcitx5-array 原生引擎提供：

- W+數字符號輸入（接近 Windows 行列體驗）
- 一級/二級簡碼
- 萬用字元查詢（? 和 *）
- 詞組輸入
- 聯想字建議
- 反查碼（Ctrl+Alt+E）

## 目標

- **平台：** Ubuntu 24.04+ LTS（x86_64，含 point release 如 24.04.1）
- **定位：** 完全獨立的新專案（獨立 repo）
- **形式：** 單一 Bash 腳本（`array30-install.sh`）
- **發佈：** 支援 `curl | bash` 一行安裝 + clone repo 執行

## 子命令

```
array30-install.sh install        # 全自動安裝
array30-install.sh uninstall      # 解除安裝 + 還原 table-based array30
array30-install.sh update-table   # 更新字表（下載最新 CIN → 重建 array.db）
array30-install.sh diagnose       # 健康檢查
array30-install.sh backup         # 手動備份
array30-install.sh restore        # 從備份還原
```

## 安裝流程

```
環境偵測（Ubuntu 24.04? x86_64?）
    → 語系偵測：zh_TW.UTF-8 已啟用？
        → 若否：自動安裝 language-pack-zh-hant、設定 locale、
          切換桌面語系為繁體中文（提示需重新登入生效）
        → 若是：跳過
    → fcitx5 偵測：已安裝？
        → 若否：apt install fcitx5 + 相關套件、
          設定為預設輸入法框架（im-config）
        → 若是：跳過
    → apt 安裝 build dependencies
    → 從 AUR clone PKGBUILD，解析上游 source URL
    → 下載原始碼 + cmake 編譯
    → 安裝 .so + .db + .conf 到系統目錄
    → 建立 libarray.so → array.so symlink
    → 設定 fcitx5 profile 啟用 array
    → 驗證（載入測試）
    → 清理 build 暫存
```

### 語系切換細節

- 安裝 `language-pack-zh-hant`、`language-pack-gnome-zh-hant`（若 GNOME 桌面）
- 產生 locale：`locale-gen zh_TW.UTF-8`
- 設定 `LANG=zh_TW.UTF-8`（透過 `update-locale`）
- 偵測桌面環境（GNOME/KDE/XFCE）用對應方式設定 UI 語系
- 語系切換需登出再登入生效，提示使用者後繼續安裝
- 設定 fcitx5 為預設輸入法框架：`im-config -n fcitx5`
- 設定環境變數（寫入 `~/.profile` 或 `/etc/environment`）：
  `GTK_IM_MODULE=fcitx`、`QT_IM_MODULE=fcitx`、`XMODIFIERS=@im=fcitx`

### 跟 steamdeck-array30 的關鍵差異

- 沒有容器 — 直接在主機編譯
- 沒有 ABI matching — Ubuntu 原生編譯自然 ABI 一致
- 不需要 Arch Archive downgrade — 直接用 apt 的版本
- 路徑固定為 Ubuntu multiarch（`/usr/lib/x86_64-linux-gnu/fcitx5/`）

## Build Dependencies

```bash
# 編譯工具
build-essential cmake extra-cmake-modules git

# fcitx5 開發套件
fcitx5 libfcitx5core-dev libfcitx5config-dev libfcitx5utils-dev fcitx5-modules-dev

# 其他依賴
libsqlite3-dev libfmt-dev gettext pkg-config zstd
```

> **注意：** 實際需要的 `-dev` 套件以上游 CMakeLists.txt 的 `find_package()` 為準，
> 實作時需在 Ubuntu 24.04 上驗證並補齊遺漏的套件。

## 編譯流程

1. `git clone https://aur.archlinux.org/fcitx5-array.git` → 取得 PKGBUILD
2. 解析 PKGBUILD 的 `source=()` 和 `pkgver=` 欄位，拿到上游 tarball URL
   - **Fallback：** 若 PKGBUILD 解析失敗，fallback 到硬編碼的上游 repo
     `https://github.com/ray2501/fcitx5-array`，使用最新 release tag
3. 下載解壓上游原始碼
4. 在 `/tmp/array30-build-XXXX/` 暫存目錄中執行：
   ```bash
   cmake -B build \
     -DCMAKE_INSTALL_PREFIX=/usr \
     -DCMAKE_BUILD_TYPE=Release
   cmake --build build
   ```
5. 用 `cmake --install build --prefix /tmp/array30-staging` 安裝到暫存 staging 目錄，
   再從 staging 中 `sudo cp` 到系統目錄。這樣可以取得 cmake install rules 產生的
   所有檔案（包含 `.conf` 設定檔），同時保持對安裝路徑的精確控制。
   - **產出物清單：** `array.so`、`libassociation.so`、`array.db`、
     `addon/array.conf`、`inputmethod/array.conf`
   - 複製時將 `.so` 檔從 staging 的 `lib/fcitx5/` 搬到
     `/usr/lib/x86_64-linux-gnu/fcitx5/`（Ubuntu multiarch 路徑）
6. 建立 symlink：`libarray.so → array.so`（`array.so` 是真實檔案，
   Ubuntu fcitx5 addon loader 會尋找帶 `lib` 前綴的檔名）
7. 記錄安裝版本（source commit/tag）到 `~/.local/share/array30-backup/installed-version.txt`
8. 清理 build 暫存目錄

## 安裝路徑

| 檔案 | 路徑 |
|------|------|
| `array.so` | `/usr/lib/x86_64-linux-gnu/fcitx5/` |
| `libarray.so` | → symlink 到 `array.so` |
| `array.db` | `/usr/share/fcitx5/array/` |
| `array.conf`（addon） | `/usr/share/fcitx5/addon/` |
| `array.conf`（inputmethod） | `/usr/share/fcitx5/inputmethod/` |
| `libassociation.so` | `/usr/lib/x86_64-linux-gnu/fcitx5/`（聯想字引擎，選用） |

## 字表管理（update-table）

### 資料來源

| 檔案 | 來源 |
|------|------|
| `array30-OpenVanilla-big.cin` | `https://github.com/gontera/array30` |
| `array30_simplecode.cin` | 同上 |
| `array30-phrase.txt` | `https://github.com/ray2501/fcitx5-array` |

### 更新流程

1. 下載最新三個檔案到暫存目錄
2. 自動備份當前 `array.db`
3. 內嵌 Python 腳本重建 `array.db`：
   - `CREATE TABLE IF NOT EXISTS` 確保 schema 存在（防止 db 損壞或首次建立）
   - 解析 CIN 格式，分 11 個 Unicode block region
   - 寫入 `main`（主表）、`simple`（簡碼）、`phrase`（詞組）三張 SQLite table
   - 驗證 main 表至少 10,000 筆以上
4. 顯示更新統計（新舊筆數對比）
5. 確認後覆蓋 `/usr/share/fcitx5/array/array.db`
6. 重啟 fcitx5 載入新字表

Python 只用標準庫（`sqlite3`、`re`、`os`），Ubuntu 24.04 預裝 `python3` 即可。

## 診斷（diagnose）

檢查項目與標記：

```
1. 系統資訊
   - OS 版本（確認 Ubuntu 24.04）
   - 語系設定（LANG、LC_ALL 是否為 zh_TW.UTF-8）
   - 桌面環境

2. 套件狀態
   - fcitx5 版本
   - libfmt 版本
   - 輸入法框架（im-config 是否指向 fcitx5）

3. 檔案完整性
   - array.so 存在 + 檔案大小
   - libarray.so symlink 正確
   - array.db 存在 + 檔案大小
   - addon/inputmethod conf 存在
   - libassociation.so 存在

4. ABI 健康度
   - ldd array.so — 有無缺失的 shared library
   - nm -D 符號檢查（fmt namespace、StandardPath/Paths）

5. 字表統計
   - main 表筆數
   - simple 表筆數
   - phrase 表筆數

6. fcitx5 設定
   - profile 中是否有 array 輸入法
   - fcitx5 程序是否正在執行

7. 備份狀態
   - 備份目錄列表 + 各備份的時間與大小
```

每項用 `[OK]` / `[WARN]` / `[FAIL]` 標記，最後給總結建議。

## 備份/還原

### 備份（backup）

- **位置：** `~/.local/share/array30-backup/YYYYMMDD-HHMMSS/`
- **內容：**
  - `array.so`、`libassociation.so`
  - `array.db`
  - `addon/array.conf`、`inputmethod/array.conf`
  - `metadata.txt` — 記錄備份時間、fcitx5 版本、fcitx5-array 原始碼版本、array.db 筆數
- **自動備份時機：** install、update-table、uninstall 執行前自動觸發

### 還原（restore）

- 列出所有備份，顯示時間 + metadata
- 使用者選擇後，確認覆蓋，`sudo cp` 回系統目錄
- 重啟 fcitx5

## 解除安裝（uninstall）

1. 自動備份當前狀態
2. 移除系統檔案（array.so、libarray.so、array.db、confs、libassociation.so）
3. 從 fcitx5 profile 移除 array，還原 table-based array30（若有裝的話）
4. 提示：build dependencies 不自動移除（可能其他程式在用），列出可手動移除的套件清單

## 發佈

### Repo 結構

```
array30-install/
├── array30-install.sh      # 主腳本（所有功能）
├── README.md
├── LICENSE                  # GPL-2.0-or-later
└── docs/
```

### 使用方式

**Clone 模式：**
```bash
git clone https://github.com/<user>/array30-install.git
cd array30-install
bash array30-install.sh install
```

**curl | bash 模式：**
```bash
curl -fsSL https://raw.githubusercontent.com/<user>/array30-install/main/array30-install.sh | bash -s -- install
```

> **注意：** 不要用 `sudo bash` 執行整支腳本。腳本內部會在需要時自行呼叫 `sudo`，
> 這樣備份目錄會正確建立在使用者的 `$HOME` 下，而非 `/root/`。

### 安全考量

- 腳本開頭檢查是否為 pipe 模式（`[ -t 0 ]` 為 false 時），若是 pipe 則跳過互動確認
- 所有 `sudo` 操作在腳本內部按需呼叫，不要求整支腳本用 `sudo` 執行
- 暫存目錄用 `mktemp -d`，腳本結束或中斷時 `trap` 清理

## 錯誤處理

### 環境前置檢查（install 前全部通過才繼續）

- 不是 Ubuntu 24.04+（檢查主版本 >= 24.04，支援 point release） → 報錯退出
- 不是 x86_64 → 報錯退出
- 沒有網路 → 報錯退出
- 磁碟空間不足（< 1.5GB） → 警告（build-essential + 編譯暫存需要較大空間）

### 編譯階段

- PKGBUILD 解析失敗 → 報錯，顯示 PKGBUILD 內容請使用者回報
- cmake 或 make 失敗 → 保留 build log 到 `~/array30-build-error.log`，報錯退出
- 上游 tarball 下載失敗 → 重試一次，仍失敗則報錯退出

### 執行階段保護

- `set -euo pipefail` 全程啟用
- 所有暫存目錄用 `trap cleanup EXIT` 確保清理
- `sudo cp` 前先驗證源檔存在且非空
- 備份目錄寫入失敗 → 警告但不中斷安裝

## 使用者互動

最少互動模式：只在關鍵時刻確認，其餘全自動。

確認點：
- 語系切換前（「系統目前為英文介面，即將切換至繁體中文，繼續？」）
- 安裝 build dependencies 前（「即將安裝以下套件，繼續？」）
- update-table 覆蓋字表前（顯示新舊筆數對比）
- uninstall 前

Pipe 模式（`curl | bash`）自動跳過所有確認。

## 冪等性

重複執行 `install` 是安全的：
- 已安裝的 apt 套件會被跳過
- 已設定的 locale 會被跳過
- fcitx5-array 會重新從原始碼編譯並覆蓋（等同升級）
- 安裝前自動備份確保可回滾

## 與 steamdeck-array30 的共存

本工具與 `steamdeck-array30` 安裝到相同的系統路徑，不應同時使用。
`diagnose` 會檢查是否有 `steamdeck-array30` 的殘留，若有則提示使用者先移除。
