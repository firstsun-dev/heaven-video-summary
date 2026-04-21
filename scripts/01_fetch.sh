#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/config.env"
source "$SCRIPT_DIR/progress.sh"

REBUILD_ALL=false
if [[ "${1:-}" == "--rebuild-all" ]]; then
    REBUILD_ALL=true
    echo "🔄 Rebuild all mode: ignoring status.md, re-downloading everything"
fi

TEMP_DIR="${TEMP_DIR:-temp}"
mkdir -p "$ROOT_DIR/$TEMP_DIR"

# Extract date from title (matches Python logic in 03_archive.py)
_extract_date_from_title() {
    local title="$1"
    local fallback_date="$2"

    # Try YYYYMMDD pattern (e.g., 20220904)
    if [[ "$title" =~ ([0-9]{8}) ]]; then
        local date_str="${BASH_REMATCH[1]}"
        echo "${date_str:0:4}-${date_str:4:2}-${date_str:6:2}"
        return 0
    fi

    # Try YYYY-MM-DD pattern
    if [[ "$title" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi

    # Fallback to upload date
    echo "${fallback_date:0:4}-${fallback_date:4:2}-${fallback_date:6:2}"
}

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

current=0
skipped=0

while IFS=$'\t' read -r video_id title upload_date duration channel; do
    url="https://www.youtube.com/watch?v=$video_id"

    ((current++))

    # Skip if already in temp (idempotent)
    if [[ -d "$ROOT_DIR/$TEMP_DIR/$video_id" && -f "$ROOT_DIR/$TEMP_DIR/$video_id/meta.json" ]]; then
        ((skipped++))
        _update_progress "$current" "$TOTAL" "$skipped" "⏭️ Already in temp" "$title"
        continue
    fi

    # Skip if already archived (unless --rebuild-all)
    if [[ "$REBUILD_ALL" == "false" && "$upload_date" =~ ^[0-9]{8}$ ]]; then
        archive_dir="$ROOT_DIR/${ARCHIVE_DIR:-youtube-dharma-talk}"

        # Extract date from title (same logic as 03_archive.py)
        date_fmt=$(_extract_date_from_title "$title" "$upload_date")
        year="${date_fmt:0:4}"

        # Check if any file for this date exists and contains this title
        if [[ -d "$archive_dir/$year" ]]; then
            for archive_file in "$archive_dir/$year/${date_fmt}"*.md; do
                if [[ -f "$archive_file" ]] && grep -q "^title: $title$" "$archive_file" 2>/dev/null; then
                    ((skipped++))
                    _update_progress "$current" "$TOTAL" "$skipped" "⏭️ Already archived" "$title"
                    continue 2
                fi
            done
        fi
    fi

    _update_progress "$current" "$TOTAL" "$skipped" "📥 Processing" "$title"
    echo ""
    mkdir -p "$ROOT_DIR/$TEMP_DIR/$video_id"

    # Resolve upload_date if flat-playlist returned "NA"
    if [[ "$upload_date" == "NA" || -z "$upload_date" ]]; then
        echo "  ℹ️  upload_date missing, fetching full metadata..."
        upload_date=$(yt-dlp --print "%(upload_date)s" "$url" 2>/dev/null || true)
        if [[ -z "$upload_date" || "$upload_date" == "NA" ]]; then
            echo "  ⚠️  Could not resolve date for: $title — using 00000000" >&2
            upload_date="00000000"
        fi
    fi

    # Reformat upload_date from YYYYMMDD to YYYY-MM-DD
    date_fmt="${upload_date:0:4}-${upload_date:4:2}-${upload_date:6:2}"

    source="audio"  # default; updated to "subtitle" if subtitle is found

    if [[ "$REBUILD_ALL" == "true" ]]; then
        # Check if subtitle already exists (skip audio download if it does)
        if ls "$ROOT_DIR/$TEMP_DIR/$video_id"/subtitle.* 1>/dev/null 2>&1; then
            source="subtitle"
            echo "  ✅ Subtitle already exists, skipping audio download"
        else
            # Always download audio for Whisper re-transcription
            echo "  🎵 Downloading audio (rebuild mode)..."
            if ! yt-dlp -x --audio-format mp3 \
                -f worstaudio \
                --concurrent-fragments 4 \
                -o "$ROOT_DIR/$TEMP_DIR/$video_id/incoming.%(ext)s" \
                "$url"; then
                echo "  ❌ Download failed: $title"
                rm -rf "$ROOT_DIR/$TEMP_DIR/$video_id"
                _mark_download_failed "$upload_date" "$title"
                continue
            fi
            echo "  ✅ Audio downloaded"
        fi
    else
        # Try downloading Chinese subtitles (zh-Hant preferred, then zh-TW, zh)
        if yt-dlp --write-subs --sub-langs "zh-Hant,zh-TW,zh" --skip-download \
            -o "$ROOT_DIR/$TEMP_DIR/$video_id/subtitle.%(ext)s" \
            "$url" 2>/dev/null \
           && ls "$ROOT_DIR/$TEMP_DIR/$video_id"/subtitle.* 1>/dev/null 2>&1; then
            source="subtitle"
            echo "  ✅ Subtitle downloaded"
        else
            # No subtitle — download audio for Whisper
            echo "  🎵 No subtitle found, downloading audio..."
            if ! yt-dlp -x --audio-format mp3 \
                -f worstaudio \
                --concurrent-fragments 4 \
                -o "$ROOT_DIR/$TEMP_DIR/$video_id/incoming.%(ext)s" \
                "$url"; then
                echo "  ❌ Download failed: $title"
                rm -rf "$ROOT_DIR/$TEMP_DIR/$video_id"
                _mark_download_failed "$upload_date" "$title"
                continue
            fi
            echo "  ✅ Audio downloaded"
        fi
    fi

    # Write meta.json after download so source field is accurate
    jq -n \
        --arg title "$title" \
        --arg date "$upload_date" \
        --arg date_fmt "$date_fmt" \
        --arg url "$url" \
        --arg channel "$channel" \
        --arg duration "$duration" \
        --arg source "$source" \
        '{title:$title, date:$date, date_fmt:$date_fmt, url:$url, channel:$channel, duration:$duration, source:$source}' \
        > "$ROOT_DIR/$TEMP_DIR/$video_id/meta.json"

done < "$ROOT_DIR/$TEMP_DIR/playlist.tsv"

printf "\n"
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
