# array30-install

Ubuntu 24.04+ 專用的行列30全自動安裝工具。

支援兩種引擎：**fcitx5-array** 與 **ibus-array**。無需容器，一行指令搞定。

## 快速安裝

```bash
curl -fsSL https://raw.githubusercontent.com/tern/array30-install/main/array30-install.sh | bash -s -- install
```

或 clone 後執行：

```bash
git clone https://github.com/tern/array30-install.git
cd array30-install
bash array30-install.sh install
```

執行後會出現引擎選擇選單，依需求選擇即可。

> **注意：** 不要用 `sudo bash` 執行。腳本內部會在需要時自行呼叫 `sudo`。

## 引擎比較

| 功能 | fcitx5-array | ibus-array |
|------|:---:|:---:|
| 安裝方式 | 從源碼編譯 | apt + cin 轉換 |
| 安裝時間 | 約 5 分鐘 | 約 1 分鐘 |
| 鍵碼表版本 | — | v2023-1.0（ibus-array 0.2.3） |
| W+數字符號輸入 | ✓ | ✓ |
| 一/二級簡碼 | ✓ | ✓ |
| 萬用字元 | ✓ (?/\*) | ✓ (? 僅) |
| 詞組輸入 | ✓ | ✓（官版六萬詞） |
| 聯想字建議 | ✓ | ✗ |
| 反查碼 Ctrl+Alt+E | ✓ | ✗ |
| GNOME 原生整合 | 需額外設定 | 原生支援 |

**建議：** 兩種引擎功能差異不大；GNOME 桌面環境選 ibus-array 最省事，有進階需求（聯想字、反查碼）則選 fcitx5-array。

## 指令

| 指令 | 說明 |
|------|------|
| `install` | 全自動安裝（選擇引擎 → 環境偵測 → 編譯/安裝） |
| `uninstall` | 移除已安裝的引擎 |
| `update-table` | 線上更新字根表（主表 + 簡碼 + 詞組） |
| `diagnose` | 完整健康檢查（系統/套件/ABI/字表/Profile） |
| `backup` | 手動備份 |
| `restore` | 從備份還原 |

## 系統需求

- Ubuntu 24.04+ LTS（x86_64）
- 網路連線（下載套件和原始碼）
- fcitx5-array：約 1.5GB 磁碟空間（編譯暫存）
- ibus-array：約 100MB 磁碟空間

## 字根表來源

兩種引擎的輸入法資料均來自 [gontera/array30](https://github.com/gontera/array30)：

| 資料 | 檔案 |
|------|------|
| 主鍵碼表（v2023-1.0） | `OpenVanilla/array30-OpenVanilla-big-v2023-1.0-20230211.cin` |
| 簡碼表 | `OpenVanilla/array-shortcode-20210725.cin` |
| 詞組表（官版六萬詞） | `array30-phrase-20210725.txt` |

兩種引擎皆以上述原始資料各自建立 SQLite 資料庫（`array.db`）。
fcitx5-array 的架構與 SQLite 格式移植自 [lexical/ibus-array](https://github.com/lexical/ibus-array)。

## 授權

GPL-2.0-or-later
