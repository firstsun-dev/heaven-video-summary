#!/bin/bash

# 檢查 yt-dlp 和 jq 是否已安裝
if ! command -v yt-dlp &> /dev/null; then
    echo "錯誤：yt-dlp 未安裝。請先安裝 yt-dlp。" >&2
    echo "安裝說明：https://github.com/yt-dlp/yt-dlp#installation" >&2
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "錯誤：jq 未安裝。請先安裝 jq。" >&2
    echo "安裝說明：https://stedolan.github.io/jq/download/" >&2
    exit 1
fi

# --- 路徑設定 ---
# 取得腳本所在的目錄，並以此為基礎設定所有路徑，確保路徑的絕對性與正確性
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# 設定播放清單 URL 和輸出檔案名稱
PLAYLIST_URL="https://www.youtube.com/playlist?list=PLefw8Oiz6WU-s263yJOCb_dFznzQ2CBV4"
DOWNLOAD_DIR="${SCRIPT_DIR}/downloads"
# 使用一個臨時子目錄來存放初始下載的檔案，避免處理過程中的衝突
TMP_DIR="${DOWNLOAD_DIR}/.tmp"
# Archive file to track downloaded videos
ARCHIVE_FILE="${DOWNLOAD_DIR}/downloaded.txt"

# --- 測試設定 ---
# 如果你只想測試下載播放清單中的前幾個影片，請取消註解並設定此變數。
# 例如：PLAYLIST_ITEMS_LIMIT="1-5" (下載第1到5個影片)
#      PLAYLIST_ITEMS_LIMIT="3" (只下載第3個影片)
# 若要下載所有新影片，請將此變數留空或註解掉。
PLAYLIST_ITEMS_LIMIT="" # 在正常模式下，將此變數設為空字串
# PLAYLIST_ITEMS_LIMIT="1-5" # 測試時，可註解上一行並取消註解此行

# 建立 downloads 和臨時資料夾 (如果不存在)
mkdir -p "$TMP_DIR"

echo "步驟 1/2: 使用臨時檔名下載新的 metadata 和字幕..."
echo "已處理的影片將記錄在 '$ARCHIVE_FILE' 中，避免重複下載。"
echo "---"

# 使用影片 ID 作為臨時檔名進行下載，這最為可靠
yt_dlp_args=(
    "--download-archive" "$ARCHIVE_FILE"
    "--ignore-errors" # 當處理播放清單時，遇到單一影片錯誤（如下載不到字幕）時不要中斷
    "--skip-download"
    "--write-info-json"
    "--write-subs"
    "--sub-langs" "zh-Hant,zh-TW,zh"
    "-o" "${TMP_DIR}/%(id)s.%(ext)s"
)

# 如果設定了測試用的項目限制，就加入到指令中
if [ -n "$PLAYLIST_ITEMS_LIMIT" ]; then
    echo "注意：已啟用測試模式，僅下載播放清單項目: ${PLAYLIST_ITEMS_LIMIT}"
    echo "---"
    yt_dlp_args+=("--playlist-items" "$PLAYLIST_ITEMS_LIMIT")
fi

# 加上播放清單 URL 並執行指令
yt_dlp_args+=("$PLAYLIST_URL")
yt-dlp "${yt_dlp_args[@]}"

echo "---"
echo "步驟 2/2: 根據 metadata 重新命名檔案..."

# 如果臨時資料夾是空的 (沒有新檔案)，則提早結束
if [ -z "$(ls -A "$TMP_DIR" 2>/dev/null)" ]; then
    echo "沒有新的影片需要處理。"
else
    # 遍歷所有新下載的 .info.json 檔案
    for json_file in "${TMP_DIR}"/*.info.json; do
        # 如果臨時資料夾是空的 (例如只有字幕檔)，則跳出迴圈
        [ -f "$json_file" ] || continue

        # 檢查 _type 欄位，如果是播放清單本身的 metadata，就跳過
        # 這是為了增加腳本的穩健性，避免處理非影片的 JSON 檔案
        if [[ $(jq -r '._type' "$json_file") == "playlist" ]]; then
            echo "跳過播放清單本身的 metadata 檔案: $(basename "$json_file")"
            # 刪除這個多餘的檔案，保持臨時資料夾乾淨
            rm -f "$json_file"
            continue
        fi

        # 使用 jq 安全地讀取 title 和 upload_date
        title=$(jq -r '.title' "$json_file")

        upload_date=$(jq -r '.upload_date' "$json_file")

        # 從標題中提取日期 (第一個找到的8位數字)，如果找不到則使用 upload_date 作為備用
        extracted_date=$(echo "$title" | grep -oE '[0-9]{8}')
        if [ -z "$extracted_date" ]; then
            final_date="$upload_date"
            echo "注意：在標題中找不到日期，使用上傳日期 ${final_date} 作為備用。"
        else
            final_date="$extracted_date"
        fi

        # 處理主題：
        # 1. 將各種分隔符號統一為標準'|'，然後取出第一部分作為主題的基礎。
        # 2. 從主題基礎中移除已擷取的日期，避免檔名中日期重複。
        # 3. 清理前後空白及檔名中的非法字元。
        raw_subject=$(echo "$title" | sed 's/[｜│]/|/g' | cut -d'|' -f1)
        subject=$(echo "$raw_subject" | sed "s/${final_date}//" | sed -e 's/^[[:space:]]*//;s/[[:space:]]*$//' -e 's#[/\?%*:|"<>]#_#g')

        video_id=$(basename "$json_file" .info.json)
        # 增加日誌，方便追蹤處理過程
        echo "原始標題: ${title}"
        echo "  -> 擷取日期: ${final_date}"
        echo "  -> 處理後主題: ${subject}"
        echo "  -> 準備重新命名: ${video_id} -> ${final_date}_${subject}"

        new_filename_base="${DOWNLOAD_DIR}/${final_date}_${subject}"
        sub_file=$(find "$TMP_DIR" -maxdepth 1 -name "${video_id}.zh-*.vtt" -print -quit)

        # 使用 -n (no-clobber) 避免意外覆蓋已存在檔案
        mv -n "$json_file" "${new_filename_base}.info.json"
        if [ -n "$sub_file" ] && [ -f "$sub_file" ]; then
            ext="${sub_file#"$TMP_DIR/${video_id}"}"
            mv -n "$sub_file" "${new_filename_base}${ext}"
        fi
    done
fi

# 清理臨時資料夾
rm -rf "$TMP_DIR"

echo "---"
echo "所有任務完成！"
