#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/config.env"

REBUILD_ALL=false
if [[ "${1:-}" == "--rebuild-all" ]]; then
    REBUILD_ALL=true
    echo "🔄 Rebuild all mode: ignoring status.md, re-downloading everything"
fi

TEMP_DIR="${TEMP_DIR:-temp}"
mkdir -p "$ROOT_DIR/$TEMP_DIR"

echo "=== Stage 1: Fetching playlist ==="

if [[ -z "${PLAYLIST_URL:-}" ]]; then
    echo "❌ PLAYLIST_URL is not set in config.env" >&2
    exit 1
fi

# Get playlist entries: id, title, upload_date, duration_string, channel
yt-dlp --flat-playlist --print "%(id)s	%(title)s	%(upload_date)s	%(duration_string)s	%(channel)s" \
    "$PLAYLIST_URL" > "$ROOT_DIR/$TEMP_DIR/playlist.tsv"

TOTAL=$(wc -l < "$ROOT_DIR/$TEMP_DIR/playlist.tsv" | tr -d ' ')
echo "📋 Found $TOTAL videos in playlist"

while IFS=$'\t' read -r video_id title upload_date duration channel; do
    url="https://www.youtube.com/watch?v=$video_id"

    # Skip if already in temp (idempotent)
    if [[ -d "$ROOT_DIR/$TEMP_DIR/$video_id" && -f "$ROOT_DIR/$TEMP_DIR/$video_id/meta.json" ]]; then
        echo "⏭️  Already in temp: $title"
        continue
    fi

    # Skip if already archived (unless --rebuild-all)
    if [[ "$REBUILD_ALL" == "false" ]]; then
        if grep -q "^| $upload_date" "$ROOT_DIR/status.md" 2>/dev/null; then
            status_line=$(grep "^| $upload_date" "$ROOT_DIR/status.md" || true)
            if echo "$status_line" | grep -q "已存在"; then
                echo "⏭️  Already archived: $title"
                continue
            fi
        fi
    fi

    echo "📥 Processing: $title ($video_id)"
    mkdir -p "$ROOT_DIR/$TEMP_DIR/$video_id"

    # Resolve upload_date if flat-playlist returned "NA"
    if [[ "$upload_date" == "NA" || -z "$upload_date" ]]; then
        # Try extracting YYYYMMDD from the title (e.g. "20251116 天界之舟...")
        extracted=$(echo "$title" | grep -oE '^[0-9]{8}' || true)
        if [[ -n "$extracted" ]]; then
            upload_date="$extracted"
            echo "  ℹ️  Date from title: $upload_date"
        else
            # Full metadata fetch as last resort
            echo "  ℹ️  Fetching full metadata for date..."
            upload_date=$(yt-dlp --print "%(upload_date)s" "$url" 2>/dev/null || echo "19700101")
        fi
    fi

    # Write meta.json
    # Reformat upload_date from YYYYMMDD to YYYY-MM-DD
    date_fmt="${upload_date:0:4}-${upload_date:4:2}-${upload_date:6:2}"
    jq -n \
        --arg title "$title" \
        --arg date "$upload_date" \
        --arg date_fmt "$date_fmt" \
        --arg url "$url" \
        --arg channel "$channel" \
        --arg duration "$duration" \
        '{title: $title, date: $date, date_fmt: $date_fmt, url: $url, channel: $channel, duration: $duration}' \
        > "$ROOT_DIR/$TEMP_DIR/$video_id/meta.json"

    if [[ "$REBUILD_ALL" == "true" ]]; then
        # Always download audio for Whisper re-transcription
        echo "  🎵 Downloading audio (rebuild mode)..."
        if yt-dlp -x --audio-format mp3 \
            -o "$ROOT_DIR/$TEMP_DIR/$video_id/incoming.%(ext)s" \
            "$url"; then
            echo "  ✅ Audio downloaded"
        else
            echo "  ❌ Download failed: $title"
            rm -rf "$ROOT_DIR/$TEMP_DIR/$video_id"
            _mark_download_failed "$upload_date" "$title"
        fi
        continue
    fi

    # Try downloading Chinese subtitles first (zh-Hant preferred, then zh-Hans, zh)
    subtitle_downloaded=false
    for lang in zh-Hant zh-Hans zh; do
        if yt-dlp --write-auto-sub --sub-lang "$lang" --skip-download \
            -o "$ROOT_DIR/$TEMP_DIR/$video_id/subtitle.%(ext)s" \
            "$url" 2>/dev/null; then
            if ls "$ROOT_DIR/$TEMP_DIR/$video_id"/subtitle.* 1>/dev/null 2>&1; then
                subtitle_downloaded=true
                echo "  ✅ Subtitle downloaded ($lang)"
                break
            fi
        fi
    done

    # If no subtitle found, download audio for Whisper
    if [[ "$subtitle_downloaded" == "false" ]]; then
        echo "  🎵 No subtitle found, downloading audio..."
        if yt-dlp -x --audio-format mp3 \
            -o "$ROOT_DIR/$TEMP_DIR/$video_id/incoming.%(ext)s" \
            "$url"; then
            echo "  ✅ Audio downloaded"
        else
            echo "  ❌ Download failed: $title"
            rm -rf "$ROOT_DIR/$TEMP_DIR/$video_id"
            _mark_download_failed "$upload_date" "$title"
            continue
        fi
    fi

done < "$ROOT_DIR/$TEMP_DIR/playlist.tsv"

echo "=== Stage 1 complete ==="

# Mark download failure in status.md
_mark_download_failed() {
    local date_key="$1"
    local title="$2"
    if grep -q "^| $date_key" "$ROOT_DIR/status.md" 2>/dev/null; then
        # Update existing row
        sed -i '' "s|^| $date_key\(.*\)|^| $date_key\1 ❌ 下載失敗 |  ||" "$ROOT_DIR/status.md" 2>/dev/null || true
    else
        echo "| $date_key | $title | ❌ 下載失敗 |  |" >> "$ROOT_DIR/status.md"
    fi
}
