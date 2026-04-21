#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/config.env"
source "$SCRIPT_DIR/progress.sh"

# Activate venv if present
if [[ -f "$ROOT_DIR/.venv/bin/activate" ]]; then
    source "$ROOT_DIR/.venv/bin/activate"
fi

TEMP_DIR="${TEMP_DIR:-temp}"
WHISPER_MODEL="${WHISPER_MODEL:-large-v3}"
WHISPER_LANGUAGE="${WHISPER_LANGUAGE:-Chinese}"

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

echo "=== Stage 2: Transcription ==="

# Scan all videos and categorize them
total=0
completed=0
to_process=0

echo "🔍 Scanning videos..."
for video_dir in "$ROOT_DIR/$TEMP_DIR"/*/; do
    [[ -d "$video_dir" ]] || continue
    [[ ! -f "$video_dir/meta.json" ]] && continue
    ((total++))

    if [[ -f "$video_dir/transcript.txt" ]]; then
        ((completed++))
    else
        ((to_process++))
    fi
done

echo "📊 Scan complete:"
echo "   Total videos: $total"
echo "   ✅ Already transcribed: $completed"
echo "   ⏳ Need transcription: $to_process"
printf "\n"

current=0
skipped=0

# Function to transcribe a single video
_transcribe_video() {
    local video_dir="$1"

    video_id=$(basename "$video_dir")
    title=$(jq -r '.title' "$video_dir/meta.json")

    ((current++))

    # Skip if already archived (check if MD file exists)
    video_date=$(jq -r '.date' "$video_dir/meta.json" 2>/dev/null || echo "")
    if [[ -n "$video_date" && "$video_date" =~ ^[0-9]{8}$ ]]; then
        archive_dir="$ROOT_DIR/${ARCHIVE_DIR:-youtube-dharma-talk}"

        # Extract date from title (same logic as 03_archive.py)
        date_fmt=$(_extract_date_from_title "$title" "$video_date")
        year="${date_fmt:0:4}"

        # Check if any MD file exists for this date (including collision variants)
        if ls "$archive_dir/$year/$date_fmt"*.md 1>/dev/null 2>&1; then
            ((skipped++))
            _update_progress "$current" "$total" "$skipped" "⏭️ Already archived" "$title" "newline"
            return 0
        fi
    fi

    # Case 1: Has subtitle file — convert to plain text (without timestamps)
    subtitle_file=$(ls "$video_dir"/subtitle.* 2>/dev/null | head -1 || true)
    if [[ -n "$subtitle_file" ]]; then
        echo "📝 Converting subtitle: $title"

        # Convert to plain text without timestamps
        sed -E \
            -e '/^WEBVTT/d' \
            -e '/^Kind:/d' \
            -e '/^Language:/d' \
            -e '/^[0-9]+$/d' \
            -e '/^[0-9]{2}:[0-9]{2}/d' \
            -e 's/<[^>]*>//g' \
            "$subtitle_file" \
            | grep -v '^\s*$' \
            | awk '!seen[$0]++' \
            > "$video_dir/transcript.txt"

        echo "  ✅ Subtitle converted"
        _update_progress "$current" "$total" "$skipped" "📝 Converted" "$title" "newline"
        return 0
    fi

    # Case 2: Has audio file — run mlx-whisper via Python
    audio_file=$(ls "$video_dir"/incoming.* 2>/dev/null | head -1 || true)
    if [[ -n "$audio_file" ]]; then
        echo "🎙️  Transcribing with mlx-whisper: $title"
        output_txt="$video_dir/transcript.txt"

        start_time=$(date +%s)
        if python3 "$SCRIPT_DIR/transcribe_audio.py" "$audio_file" "$output_txt" "$WHISPER_MODEL" 2>&1; then
            end_time=$(date +%s)
            elapsed=$((end_time - start_time))
            minutes=$((elapsed / 60))
            seconds=$((elapsed % 60))

            if [[ -f "$output_txt" ]]; then
                echo "  ✅ Transcription complete (${minutes}m ${seconds}s)"
                _update_progress "$current" "$total" "$skipped" "🎙️ Transcribed (${minutes}m ${seconds}s)" "$title" "newline"
            else
                echo "  ❌ mlx-whisper produced no output: $title"
                ((skipped++))
                _update_progress "$current" "$total" "$skipped" "❌ No output" "$title" "newline"
            fi
        else
            end_time=$(date +%s)
            elapsed=$((end_time - start_time))
            echo "  ❌ Transcription failed: $title (after ${elapsed}s)"
            ((skipped++))
            _update_progress "$current" "$total" "$skipped" "❌ Failed" "$title" "newline"
            # Leave temp dir intact for inspection; archiver will skip it
        fi
        return 0
    fi

    ((skipped++))
    _update_progress "$current" "$total" "$skipped" "⚠️ No source" "$title" "newline"
}

# Process all videos sequentially
# First pass: show already-transcribed videos
for video_dir in "$ROOT_DIR/$TEMP_DIR"/*/; do
    [[ -d "$video_dir" ]] || continue
    [[ ! -f "$video_dir/meta.json" ]] && continue
    [[ ! -f "$video_dir/transcript.txt" ]] && continue

    ((current++))
    title=$(jq -r '.title' "$video_dir/meta.json")
    _update_progress "$current" "$total" "$skipped" "✅ Already done" "$title" "newline"
done

# Second pass: process videos needing transcription
for video_dir in "$ROOT_DIR/$TEMP_DIR"/*/; do
    [[ -d "$video_dir" ]] || continue
    [[ ! -f "$video_dir/meta.json" ]] && continue
    [[ -f "$video_dir/transcript.txt" ]] && continue

    _transcribe_video "$video_dir"
done

printf "\n"
echo "=== Stage 2 complete ==="
