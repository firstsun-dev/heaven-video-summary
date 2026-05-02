# 天界之舟 YouTube 講座逐字稿自動化管道

YouTube 播放清單 → Whisper 逐字稿 → Markdown 歸檔 → Google Drive 的完整自動化管道。

## 快速開始

### 環境設置

```bash
# 安裝 Python 依賴
python3 -m venv .venv
source .venv/bin/activate
pip install mlx-whisper

# 安裝系統依賴
brew install yt-dlp ffmpeg rclone jq
```

### 配置

編輯 `config.env`（必填）：

```env
PLAYLIST_URL=https://www.youtube.com/playlist?list=...
RCLONE_REMOTE=gdrive:NotebookLM_Sources
```

可選設定（有預設值）：
- `WHISPER_MODEL` - 預設：`base`
- `WHISPER_LANGUAGE` - 預設：`zh`
- `ARCHIVE_DIR` - 預設：`youtube-dharma-talk`
- `TEMP_DIR` - 預設：`temp`

## 使用方式

### 方法 1：完整管道（推薦）

```bash
# 標準模式（跳過已歸檔的影片）
bash scripts/run.sh

# 重建模式（重新下載所有音訊，重新歸檔）
bash scripts/run.sh --rebuild-all
```

### 方法 2：逐個階段執行

```bash
# 第 1 階段：下載播放清單和音訊
bash scripts/01_fetch.sh [--rebuild-all]

# 第 2 階段：Whisper 轉錄
bash scripts/02_transcribe.sh

# 第 3 階段：歸檔為 Markdown（含時間戳版本）
python3 scripts/03_archive.py

# 第 4 階段：合併年度檔案並同步到 Google Drive
bash scripts/04_merge.sh
```

### 方法 3：快速生成時間戳版本（從現有字幕）

如果你已有 `.vtt` 字幕檔案，想快速生成 `-timestamps.md` 版本而不重新轉錄：

```bash
python3 scripts/generate_timestamps.py
```

這個腳本會：
- 掃描 `youtube-dharma-talk/` 中所有 `.vtt` 檔案
- 從 VTT 時間戳提取 `[HH:MM:SS.mmm]` 格式
- 配對對應的 `.md` 檔案，生成 `-timestamps.md` 版本
- 只處理尚未生成的檔案

## 管道架構

```
01_fetch.sh
  ├→ temp/{video_id}/meta.json（視訊元資料）
  ├→ temp/{video_id}/incoming.mp3（音訊）
  └→ temp/{video_id}/subtitle.vtt（YouTube 字幕，若有）
       ↓
02_transcribe.sh
  └→ temp/{video_id}/transcript.md（Whisper 轉錄）
       ↓
03_archive.py
  ├→ youtube-dharma-talk/{year}/{YYYY-MM-DD}.md（無時間戳）
  ├→ youtube-dharma-talk/{year}/{YYYY-MM-DD}-timestamps.md（含時間戳）
  ├→ youtube-dharma-talk/{year}/{YYYY-MM-DD}.vtt（原始字幕）
  └→ status.md（更新處理狀態）
       ↓
04_merge.sh
  ├→ youtube-dharma-talk/{year}_Merged.md（年度合輯，無時間戳）
  ├→ youtube-dharma-talk/{year}_Merged-timestamps.md（年度合輯，含時間戳）
  └→ rclone sync 到 Google Drive
```

## 檔案說明

| 檔案 | 用途 |
|:-----|:-----|
| `scripts/01_fetch.sh` | 從 YouTube 下載影片 ID、元資料、音訊 |
| `scripts/02_transcribe.sh` | 使用 Whisper 轉錄音訊為文字 |
| `scripts/03_archive.py` | 轉換為 Markdown，產生含/不含時間戳的版本 |
| `scripts/generate_timestamps.py` | 從 .vtt 快速生成 -timestamps.md（新增）|
| `scripts/04_merge.sh` | 合併年度檔案並同步到 Google Drive |
| `status.md` | 處理狀態追蹤表（日期、標題、狀態、連結） |
| `config.env` | 設定檔（PLAYLIST_URL、RCLONE_REMOTE 等） |

## 狀態追蹤

`status.md` 以日期排序（最新在上）。欄位：

- **日期** — 講座日期（YYYYMMDD 格式，從標題提取，若找不到則用發佈日期）
- **主題** — 影片標題
- **處理狀態** — 🗂️ 已存在 / ⚠️ 等待處理
- **連結** — 歸檔檔案相對路徑

**去重邏輯**：同一日期 + 同一標題 = 同一篇影片（不建立重複條目）

## 特殊情況

### 同日期多篇

如果同一天有多篇講座，會自動加上序號：
- `2024-03-17.md`
- `2024-03-17-2.md`
- `2024-03-17-3.md`

### 時間戳格式

兩個版本的差異：

**無時間戳版本** (`2024-03-17.md`)：
```
---
title: ...
date: 2024-03-17
...
---

講座內容直接列出
每一行是一句話或段落
```

**含時間戳版本** (`2024-03-17-timestamps.md`)：
```
---
title: ...
date: 2024-03-17
...
---

[00:00:15.000] 講座內容
[00:00:20.000] 下一句話
[00:05:30.000] 後面的段落
```

## 依賴項

- **必填**：`python3`, `mlx-whisper`, `ffmpeg`, `rclone`, `jq`
- **推薦**：`yt-dlp`（用於下載）
- **macOS 專用**：`mlx-whisper` 需要 Apple Silicon (M1/M2/M3/M4)
  - Intel Mac：改用 `faster-whisper`

## 故障排除

### yt-dlp 找不到

確保已安裝：
```bash
brew install yt-dlp
```

### mlx-whisper 轉錄太慢

- 檢查 WHISPER_MODEL 設定（改用 `tiny` 或 `small`）
- 確認使用的是 Apple Silicon Mac

### Google Drive 同步失敗

確保 `rclone` 已配置：
```bash
rclone config
# 選擇 Google Drive，授權後設定名稱為 gdrive
```

## 開發

所有腳本都支援自動啟用 `.venv`（如果存在）。

### 新增功能建議

- 支援其他語言轉錄
- 自動上傳到多個雲端服務
- 網頁前端查詢介面

## 授權

內部使用專案
