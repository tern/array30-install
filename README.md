# array30-install

Ubuntu 24.04+ 專用的行列30全自動安裝工具。

支援兩種引擎：原生 **fcitx5-array**（功能完整）與 **ibus-array**（輕量快速）。無需容器，一行指令搞定。

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
| W+數字符號輸入 | ✓ | ✗ |
| 一/二級簡碼 | ✓ | ✓ |
| 萬用字元 (?/*) | ✓ | ✗ |
| 詞組輸入 | ✓ | 有限 |
| 聯想字建議 | ✓ | ✗ |
| 反查碼 Ctrl+Alt+E | ✓ | ✗ |
| GNOME 原生整合 | 需額外設定 | 原生支援 |
| 適合對象 | 進階用戶 | 輕量需求 |

**建議：** 日常使用選 fcitx5-array；如只需基本輸入且在乎啟動速度，選 ibus-array。

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

| 檔案 | 來源 |
|------|------|
| 主字根表（`array30.conf`） | [gontera/array30](https://github.com/gontera/array30) — 官方行列30鍵碼表 |
| 簡碼表（`array30_simplecode.cin`） | 同上倉庫 |
| 詞組表（`array30_phrase.cin`） | [ray2501/fcitx5-array](https://github.com/ray2501/fcitx5-array) 內附 |

## 授權

GPL-2.0-or-later
