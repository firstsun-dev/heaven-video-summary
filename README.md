# Heaven Vedio Summarizer

本專案旨在自動化一個完整的工作流程：從指定的 YouTube 播放清單下載影片字幕，利用 Google Gemini AI 產生結構化摘要，最後將彙整後的內容同步發佈到本專案的 **GitLab Wiki**。

整個流程可以手動在本地端執行，也可以透過 GitLab CI/CD 進行排程全自動化。

## ✨ 功能特性

-   **自動下載**：從指定的 YouTube 播放清單下載新的影片 metadata 和字幕，並透過紀錄檔避免重複處理。
-   **AI 摘要**：使用 `gemini-cli`，根據可自訂的提示 (Prompt)，從影片字幕產生結構化的重點摘要。
-   **Markdown 彙整**：將所有影片的摘要彙整至單一、格式優美的 Markdown 檔案中，並自動包含原始影片連結。
-   **Wiki 發佈**：自動將最新的摘要內容推送到專案的 GitLab Wiki 首頁。
-   **CI/CD 自動化**：內建 `.gitlab-ci.yml` 設定檔，可在 GitLab 上設定排程，實現無人值守的全自動化執行。

## ⚙️ 環境準備

在開始之前，請確保你的系統已安裝以下工具：

-   **Poetry**：用於管理 Python 虛擬環境與依賴套件。
-   **yt-dlp**：用於下載 YouTube 影片資訊與字幕。
-   **jq**：一個命令列 JSON 處理工具，供下載腳本使用。
-   **gemini-cli**：Google Gemini API 的命令列工具。安裝後需先執行 `gemini auth` 進行認證。

## 🚀 安裝與設定

1.  **複製專案庫：**
    ```bash
    git clone <your-repository-url>
    cd heaven_vedio
    ```

2.  **安裝 Python 依賴：**
    使用 Poetry 會自動建立虛擬環境並安裝所有必要的 Python 套件。
    ```bash
    poetry install
    ```

3.  **設定環境變數與提示模板：**
    -   **提示模板**: 編輯專案根目錄下的 `prompt_template.txt` 檔案。你可以在此調整 AI 產生摘要的風格與格式，而無需更動任何程式碼。
    -   **環境變數**: 在專案根目錄下建立一個名為 `.env` 的檔案。此檔案用於存放你的本地設定與密鑰，**請勿將此檔案加入版控**。

    你可以複製以下模板來建立你的 `.env` 檔案：

    ```dotenv
    # .env - 本地端環境變數設定檔

    # --- 檔案路徑設定 ---
    # 下載檔案存放的絕對路徑
    DOWNLOADS_DIR=/Users/claudia.fang/Code/heaven_vedio/downloads
    # 最終彙整的 Markdown 檔案絕對路徑
    SUMMARY_FILE=/Users/claudia.fang/Code/heaven_vedio/影片重點摘要.md

    # --- Gemini AI 設定 ---
    # 你的 Google AI Studio API Key。請保密。
    # 取得位置: https://aistudio.google.com/app/apikey
    GEMINI_API_KEY="your_gemini_api_key_here"
    ```

## 🏃‍♂️ 如何執行

所有指令都應透過 `poetry run` 執行，以確保在正確的虛擬環境中運行。

1.  **第一步：抓取新影片資料**
    ```bash
    poetry run ./get_playlist.sh
    ```

2.  **第二步：產生摘要**
    ```bash
    poetry run summarize
    ```

## 🦊 GitLab CI/CD 自動化

本專案已包含 `.gitlab-ci.yml` 設定檔，可直接在 GitLab 上實現自動化。

-   **觸發條件**：Pipeline 只會在「排程」或「手動觸發」時執行，避免推播程式碼時觸發。
-   **執行階段**：流程分為 `fetch`、`summarize`、`publish`、`commit` 四個階段。`publish` 階段會將摘要發佈到 GitLab Wiki，且此階段的失敗不會中斷後續的 `commit` 階段。
-   **CI/CD 變數設定**：要啟用自動化，你必須在 GitLab 專案的 **Settings > CI/CD > Variables** 中設定以下變數。這些變數的作用與 `.env` 檔案相同，但用於 CI/CD 環境。
    -   `GEMINI_API_KEY`
    -   `GL_TOKEN`：用於將變更 commit 回主倉庫與 Wiki 倉庫的 GitLab Project Access Token。**此 Token 必須具備 `write_repository` 權限**。
    -   `GITLAB_USER_NAME`：CI commit 時顯示的機器人名稱 (例如 "GitLab CI Bot")。
    -   `GITLAB_USER_EMAIL`：CI commit 時顯示的機器人 Email。
