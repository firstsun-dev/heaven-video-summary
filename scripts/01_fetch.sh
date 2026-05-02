#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

REBUILD_ALL=${1:-}
[[ "$REBUILD_ALL" == "--rebuild-all" ]] && echo "🔄 Rebuild mode enabled" || REBUILD_ALL=false

echo "=== Stage 1: Fetching playlist ==="
[[ -z "${PLAYLIST_URL:-}" ]] && { echo "❌ PLAYLIST_URL missing"; exit 1; }

# Use extractor-args to spoof modern clients and disable problematic ones (like android_sdkless)
# Also explicitly use deno for JS runtime to solve challenges
YTDLP_ARGS=(
    --extractor-args "youtube:player-client=ios,web,default;-android_sdkless"
    --js-runtime deno
    --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:135.0) Gecko/20100101 Firefox/135.0"
)

yt-dlp "${YTDLP_ARGS[@]}" --flat-playlist --print "%(id)s	%(title)s	%(upload_date)s	%(duration_string)s	%(channel)s" \
    "$PLAYLIST_URL" > "$ROOT_DIR/$TEMP_DIR/playlist.tsv"

TOTAL=$(wc -l < "$ROOT_DIR/$TEMP_DIR/playlist.tsv" | xargs)
current=0; skipped=0

while IFS=$'\t' read -r vid title date dur chan; do
    ((current++))
    url="https://www.youtube.com/watch?v=$vid"
    date_fmt=$(extract_date "$title" "$date")
    
    # Priority 1: Check if already archived
    if [[ "$REBUILD_ALL" == "false" ]]; then
        if is_archived "$date_fmt" "$title"; then
             ((skipped++)); update_progress "$current" "$TOTAL" "$skipped" "⏭️ Archived" "$title"
             # Optional: Cleanup temp if it exists but is already archived
             [[ -d "$ROOT_DIR/$TEMP_DIR/$vid" ]] && rm -rf "$ROOT_DIR/$TEMP_DIR/$vid"
             continue
        fi
    fi

    # Priority 2: Check local cache (temp)
    if [[ -f "$ROOT_DIR/$TEMP_DIR/$vid/meta.json" ]]; then
        ((skipped++)); update_progress "$current" "$TOTAL" "$skipped" "⏭️ Cached" "$title"; continue
    fi

    update_progress "$current" "$TOTAL" "$skipped" "📥 Processing" "$title"
    mkdir -p "$ROOT_DIR/$TEMP_DIR/$vid"
    
    source_type="audio"
    if [[ "$REBUILD_ALL" == "false" ]] && yt-dlp "${YTDLP_ARGS[@]}" --write-subs --sub-langs "zh-Hant,zh-TW,zh" --skip-download -o "$ROOT_DIR/$TEMP_DIR/$vid/subtitle.%(ext)s" "$url" &>/dev/null; then
        source_type="subtitle"
    else
        yt-dlp "${YTDLP_ARGS[@]}" -x --audio-format mp3 -f worstaudio --concurrent-fragments 4 -o "$ROOT_DIR/$TEMP_DIR/$vid/incoming.%(ext)s" "$url" || { echo "❌ Failed $title"; continue; }
    fi

    jq -n --arg t "$title" --arg d "$date" --arg df "$date_fmt" --arg u "$url" --arg c "$chan" --arg dur "$dur" --arg s "$source_type" \
        '{title:$t, date:$d, date_fmt:$df, url:$u, channel:$c, duration:$dur, source:$s}' > "$ROOT_DIR/$TEMP_DIR/$vid/meta.json"
done < "$ROOT_DIR/$TEMP_DIR/playlist.tsv"
printf "\n=== Stage 1 complete ===\n"
