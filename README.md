# array30-install

Ubuntu 24.04+ 專用的行列30（fcitx5-array）全自動安裝工具。

原生編譯，無需容器。一行指令搞定。

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

> **注意：** 不要用 `sudo bash` 執行。腳本內部會在需要時自行呼叫 `sudo`。

## 功能

| 指令 | 說明 |
|------|------|
| `install` | 全自動安裝（環境偵測 → 中文語系 → fcitx5 → 編譯安裝） |
| `uninstall` | 移除 fcitx5-array，切回 table-based array30 |
| `update-table` | 線上更新字根表（主表 + 簡碼 + 詞組） |
| `diagnose` | 完整健康檢查（系統/套件/ABI/字表/Profile） |
| `backup` | 手動備份 |
| `restore` | 從備份還原 |

## 為什麼需要 fcitx5-array？

預設的 table-based array30 功能受限。原生 fcitx5-array 引擎支援：

- W+數字鍵符號輸入（接近 Windows 行列體驗）
- 一級/二級簡碼
- 萬用字元查詢（`?` 和 `*`）
- 詞組輸入
- 聯想字建議
- 反查碼（Ctrl+Alt+E）

## 系統需求

- Ubuntu 24.04+ LTS（x86_64）
- 網路連線（下載套件和原始碼）
- 約 1.5GB 磁碟空間（編譯暫存）

## 安裝流程

腳本會自動完成以下步驟：

1. 偵測 Ubuntu 版本和硬體架構
2. 安裝繁體中文語系（如需要）
3. 安裝 fcitx5 輸入法框架（如需要）
4. 安裝編譯依賴
5. 從 AUR 取得上游原始碼
6. 原生編譯 fcitx5-array
7. 安裝到系統目錄
8. 設定 fcitx5 profile
9. 驗證安裝結果

## 字根表來源

| 檔案 | 來源 |
|------|------|
| 主字根表（`array30.conf`） | [gontera/array30](https://github.com/gontera/array30) — 官方行列30鍵碼表 |
| 簡碼表（`array30_simplecode.cin`） | 同上倉庫 |
| 詞組表（`array30_phrase.cin`） | [ray2501/fcitx5-array](https://github.com/ray2501/fcitx5-array) 內附 |

## 授權

GPL-2.0-or-later
