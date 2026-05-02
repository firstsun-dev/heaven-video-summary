# YouTube 知識內化自動化流程 — 設計規格

## 概述

自動化「YouTube 播放清單 → 逐字稿 → 知識庫」流程。從指定播放清單擷取影片，透過本地 Whisper 轉錄，歸檔為 Markdown，同步至 Google Drive 供 NotebookLM 使用。

## 執行環境

- **GitLab CI**：macOS Runner，排程或手動觸發，跑完整流程
- **本地**：手動執行全部或單一步驟

## 專案結構

```
/repo-root
├── scripts/
│   ├── run.sh               # 主入口：串接所有步驟
│   ├── 01_fetch.sh          # 抓播放清單、下載字幕或音檔
│   ├── 02_transcribe.sh     # Whisper 本地轉錄
│   ├── 03_archive.py        # 格式化 Markdown、寫入 meta data、歸檔
│   └── 04_merge.sh # 年度合併 + rclone 同步至 Google Drive
├── config.env               # 設定檔
├── youtube-dharma-talk/      # 逐字稿歸檔目錄
│   └── {year}/
│       └── {YYYY-MM-DD}.md
├── temp/                     # 暫存區（處理完清除）
├── status.md                 # 影片處理狀態追蹤
├── .gitlab-ci.yml            # CI 定義
└── req.md                    # 需求文件
```

## 設定檔 `config.env`

| 變數 | 預設值 | 說明 |
|:-----|:------|:-----|
| `PLAYLIST_URL` | （必填） | YouTube 播放清單網址 |
| `WHISPER_MODEL` | `large-v3` | Whisper 模型，可切換 `turbo` 等 |
| `WHISPER_LANGUAGE` | `Chinese` | 轉錄語言 |
| `ARCHIVE_DIR` | `youtube-dharma-talk` | 歸檔目錄名稱 |
| `RCLONE_REMOTE` | （必填） | rclone 遠端名稱與目標路徑 |
| `TEMP_DIR` | `temp` | 暫存目錄 |

## 流程各階段

### Stage 1: `01_fetch.sh` — 影片擷取

1. `yt-dlp --flat-list` 取得播放清單所有影片的 ID、標題、上傳日期、影片長度
2. 比對 `status.md`，篩出未處理的影片
3. 對每部未處理影片：
   - 嘗試下載中文字幕（優先 `zh-Hant`, `zh-Hans`, `zh`）
   - 無中文字幕則下載音檔（`yt-dlp -x --audio-format mp3`）
4. 存入 `temp/{video_id}/`，包含 `meta.json`（標題、日期、連結、頻道名稱、影片長度）+ 字幕檔或音檔

### Stage 2: `02_transcribe.sh` — 語音轉文字

1. 掃描 `temp/` 下所有資料夾
2. 有音檔且無 `.md` → 執行 Whisper 轉錄
3. 有字幕檔（`.vtt`/`.srt`）→ 轉為 `.md`（去除時間碼）
4. 輸出：每個 `temp/{video_id}/` 下都有 `.md`

### Stage 3: `03_archive.py` — 格式化與歸檔

1. 掃描 `temp/` 下所有資料夾
2. 讀取 `meta.json` + `.md`，組裝 Markdown（含 YAML frontmatter）：
   ```markdown
   ---
   title: 影片標題
   date: 2020-01-12
   url: https://www.youtube.com/watch?v=xxxxx
   channel: 頻道名稱
   duration: 45:30
   ---

   （逐字稿內容）
   ```
3. 存入 `youtube-dharma-talk/{year}/{YYYY-MM-DD}.md`
4. 同一天多部影片：加序號 `{YYYY-MM-DD}-2.md`
5. 更新 `status.md`：`🔇 無字幕` / 新增 → `🗂️ 已存在` + 檔案路徑
6. 清除該影片的 `temp/{video_id}/`

### Stage 4: `04_merge.sh` — 合併與同步

1. 將 `youtube-dharma-talk/{year}/` 下所有 `.md` 按日期排序合併為 `{year}_Merged.md`
2. `rclone copy` 同步至 Google Drive

### `run.sh` — 主入口

依序執行 4 個 stage，每步印出階段名稱，失敗時中斷並提示從哪一步繼續。

## GitLab CI

```yaml
stages:
  - fetch
  - transcribe
  - archive
  - sync

fetch:
  stage: fetch
  script: ./scripts/01_fetch.sh
  artifacts:
    paths: [temp/]

transcribe:
  stage: transcribe
  script: ./scripts/02_transcribe.sh
  artifacts:
    paths: [temp/]

archive:
  stage: archive
  script: python3 scripts/03_archive.py
  artifacts:
    paths: [youtube-dharma-talk/, status.md]

sync:
  stage: sync
  script: ./scripts/04_merge.sh
```

- `archive` 結束後 CI 將更新的檔案 commit + push 回 repo
- 觸發方式：排程（例如每週）或手動

## `status.md` 格式

```markdown
| 日期       | 主題                    | 處理狀態       | 連結 |
|:-----------|:------------------------|:---------------|:-----|
| 20200112   | 皈依佛門的十大明星       | 🗂️ 已存在      | ./youtube-dharma-talk/2020/2020-01-12.md |
| 20200426   | 陰間大審判鑒察良心       | 🔇 無字幕      |  |
```

## 錯誤處理

- **下載失敗：** 跳過該影片，`status.md` 標記 `❌ 下載失敗`，繼續處理其他
- **轉錄失敗：** 跳過該影片，標記 `❌ 轉錄失敗`，保留 `temp/{video_id}/` 便於排查
- **CI push 衝突：** `git pull --rebase` 再 push

## 冪等性

每個步驟可安全重複執行：
- `01_fetch.sh`：已在 `temp/` 的不重複下載
- `02_transcribe.sh`：已有 `.md` 的不重複轉錄
- `03_archive.py`：已歸檔的不重複處理
- `04_merge.sh`：每次重新合併覆蓋

## 歷史補齊

現有 `status.md` 所有影片（約 120 部）全部重新處理。即使先前標記為 `🗂️ 已存在` 的影片，因舊字幕不完整，也一律重新透過 Whisper 轉錄取代。首次執行時需提供 `--rebuild-all` 旗標，讓 `01_fetch.sh` 忽略 `status.md` 狀態，重新下載音檔並走完整流程。

## 依賴

- `yt-dlp`：影片/字幕下載
- `whisper`（OpenAI Whisper CLI）：語音轉文字
- `ffmpeg`：Whisper 依賴
- `python3`：歸檔腳本
- `rclone`：Google Drive 同步
- `jq`：JSON 處理（meta.json）
