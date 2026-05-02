# GEMINI.md - 天界之舟 YouTube 逐字稿自動化管道

## 專案概述
本專案是一個自動化工具鏈，旨在將 YouTube 播放清單中的影片轉錄為 Markdown 格式的逐字稿，並同步至 Google Drive 供 NotebookLM 使用。

### 核心技術棧
- **語言**: Python 3, Bash
- **音訊下載**: `yt-dlp`, `ffmpeg`
- **語音轉文字**: `mlx-whisper` (針對 Apple Silicon 優化)
- **雲端同步**: `rclone` (同步至 Google Drive)
- **CI/CD**: GitLab CI (macOS Runner)

## 核心工作流
管道分為四個主要階段：
1.  **Fetch (01_fetch.sh)**: 擷取影片元資料與音訊檔 (`.mp3`)。
2.  **Transcribe (02_transcribe.sh)**: 使用 Whisper 進行轉錄，支援時間戳輸出。
3.  **Archive (03_archive.py)**: 生成 Markdown 檔案（含 YAML frontmatter）並更新 `status.md`。
4.  **Sync (04_merge_and_sync.sh)**: 合併年度檔案並同步至 Google Drive。

## 運行與開發指令

### 環境設置
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
brew install yt-dlp ffmpeg rclone jq
```

### 執行全流程
```bash
# 執行完整管道
bash scripts/run.sh

# 重建模式（重新下載並轉錄）
bash scripts/run.sh --rebuild-all
```

### 階段性執行
- **抓取**: `bash scripts/01_fetch.sh`
- **轉錄**: `bash scripts/02_transcribe.sh`
- **存檔**: `python3 scripts/03_archive.py`
- **同步**: `bash scripts/04_merge_and_sync.sh`

## 開發規範
- **腳本命名**: 使用 `0X_name.sh` 格式標註階段順序。
- **錯誤處理**: Bash 腳本應包含 `set -euo pipefail`。
- **資料儲存**:
    - 暫存檔存於 `temp/{video_id}/`。
    - 歸檔檔案存於 `youtube-dharma-talk/{year}/`。
- **狀態追蹤**: 每次執行應更新 `status.md` 以避免重複處理。
- **YAML Frontmatter**: Markdown 檔案必須包含 `title`, `date`, `url` 等元資料。

## CI/CD 邏輯
- 專案目前使用 GitLab CI 搭配 macOS Runner。
- 工作流僅在 `schedule` (排程) 或 `web` (手動) 觸發時執行。
- **自動 Commit**: `archive` 階段會自動將產生的 Markdown 提交並推送回儲存庫（使用 `[skip ci]`）。

## 待辦與擴充
- [ ] 支援 GitHub Actions 作為備援或主要轉運站。
- [ ] 增加更多語音轉文字模型的選擇 (如 `faster-whisper`)。
- [ ] 強化 `status.md` 的自動查重與更新邏輯。

---
*此檔案由 Gemini CLI 自動分析產生，作為後續開發與互動的上下文參考。*
