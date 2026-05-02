# YouTube 知識內化自動化流程 (Local-First Architecture)

此專案旨在自動化「YouTube 影音 -> 逐字稿 -> 知識庫」的過程，解決手動餵食資料 (Feed data) 的繁瑣感，並透過本地運算節省 Token 成本。

---

## 1. 系統架構 (System Architecture)

* **資料來源：** 指定之 YouTube 播放清單。
* **運算環境：** macOS Runner (GitLab CI)。
* **儲存結構：** 按年份與日期歸檔的 Markdown 檔案。
* **終端應用：** NotebookLM (作為 Blog 素材搜尋與 AI 助手)。

---

## 2. 檔案路徑與結構 (File Organization)

為了兼顧「個人檔案管理」與「NotebookLM 來源限制」，採用**雙軌制**：

### 本地/Git 儲存庫
用於長期備份與 Blog 檢索，保持細粒度。
```text
/repo-root
└── xxxx/
    └── 2025/
        ├── 2025-04-01.md
        ├── 2025-04-02.md
        └── [YYYY]-[MM]-[DD].md
```


### NotebookLM 同步端 (Google Drive)
為了繞過 50 個來源限制，CI 會自動進行年份合併。

```text
/G-Drive/NotebookLM_Sources/
└── 2025_Merged.md  <-- 包含當年所有逐字稿內容
````

Gemini 說了
這是一份完整的系統設計文件（System Design Document），採用 Markdown 格式編寫。你可以直接將其複製到你的專案 README.md 或開發文件中。

Markdown
# YouTube 知識內化自動化流程 (Local-First Architecture)

此專案旨在自動化「YouTube 影音 -> 逐字稿 -> 知識庫」的過程，解決手動餵食資料 (Feed data) 的繁瑣感，並透過本地運算節省 Token 成本。

---

## 1. 系統架構 (System Architecture)

* **資料來源：** 指定之 YouTube 頻道。
* **運算環境：** macOS Runner (GitLab CI)。
* **儲存結構：** 按年份與日期歸檔的 Markdown 檔案。
* **終端應用：** NotebookLM (作為 Blog 素材搜尋與 AI 助手)。

---

## 2. 檔案路徑與結構 (File Organization)

為了兼顧「個人檔案管理」與「NotebookLM 來源限制」，採用**雙軌制**：

### 本地/Git 儲存庫
用於長期備份與 Blog 檢索，保持細粒度。
```text
/repo-root
└── xxxx/
    └── 2025/
        ├── 04-01.md
        ├── 04-02.md
        └── [MM]-[DD].md
```

### NotebookLM 同步端 (Google Drive)
為了繞過 50 個來源限制，CI 會自動進行年份合併。

```text
/G-Drive/NotebookLM_Sources/
└── 2025_Merged.md  <-- 包含當年所有逐字稿內容
```

## GitLab CI 執行邏輯 (.gitlab-ci.yml 概念)
### Step 1: 影音擷取 (yt-dlp)
比對 status.md，如果未處理過的清單影片，開始處理：

1. 嘗試下載字幕，如果沒字幕就下載音檔而非影片，以節省頻寬與硬碟空間。

```bash
yt-dlp -x --audio-format mp3 -o "incoming.%(ext)s" [VIDEO_URL]
```

### Step 2: 本地語音轉文字 (Whisper on macOS)

> 如果已有字幕檔則跳過此步驟

利用 macOS Runner 的硬體加速，完全不消耗 API Token。

```bash
#使用 whisper-turbo 模型兼顧速度與精確度
whisper incoming.mp3 --model turbo --language Chinese --output_format txt --output_dir ./temp/
```

### Step 3: 自動歸檔與合併 (Processing)

1. 將 .md 轉為 .md 並加上 Meta Data (標題、連結)。
2. 存入 xxxx/2025/$(date + %y-%m-%d).md。
3. 執行 cat 指令將當月所有檔案合併至 2025_Merged.md。

### Step 4: 同步至雲端 (Rclone)

```bash
# 將合併後的月份檔案同步至 Google Drive，供 NotebookLM 讀取
rclone copy ./2025-MM_Merged.md gdrive:NotebookLM_Sources/
```

完成後新增 @status.md

| 日期       | 主題                               | 處理狀態   | 連結 |
|:-----------|:-----------------------------------|:-----------|---|
| 20200112 | 皈依佛門的十大明星                    | 🗂️ 已同步至 GDrive   | ./repo-root/xxxx-list/2020/2020-01-12.md |

## 4. 關鍵優勢 (Key Benefits)
Zero Cost (Token Free)： 核心轉譯流程跑在 Local macOS，不產生 API 費用。

* Automated Feeding： 解決手動上傳 NotebookLM 的痛點。
* Searchable History： 檔案結構清晰，適合做為個人 Blog 的 Search Tool。
* Efficiency： 自動「Replace Old」，確保 NotebookLM 內的資訊始終處於當月最新狀態。

## 待辦清單 (To-Do)
[ ] 設定 GitLab macOS Runner 環境 (Homebrew, ffmpeg, Whisper)。
[ ] 設定 Google Drive API 或 Rclone 授權。
[ ] 撰寫 Shell Script 處理影片標題抓取與 MD 格式化。
[ ] 於 NotebookLM 連結 Google Drive 資料夾。
