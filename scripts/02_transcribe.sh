#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/config.env"

# Activate venv if present
if [[ -f "$ROOT_DIR/.venv/bin/activate" ]]; then
    source "$ROOT_DIR/.venv/bin/activate"
fi

TEMP_DIR="${TEMP_DIR:-temp}"
WHISPER_MODEL="${WHISPER_MODEL:-large-v3}"
WHISPER_LANGUAGE="${WHISPER_LANGUAGE:-Chinese}"
PARALLEL_JOBS="${PARALLEL_JOBS:-1}"  # Number of parallel transcription jobs

echo "=== Stage 2: Transcription ==="

# Count total videos to process
total=0
for video_dir in "$ROOT_DIR/$TEMP_DIR"/*/; do
    [[ -d "$video_dir" ]] || continue
    [[ ! -f "$video_dir/meta.json" ]] && continue
    [[ -f "$video_dir/transcript.txt" ]] && continue
    ((total++))
done

echo "📊 Found $total video(s) to transcribe"
echo "⚙️  Using $PARALLEL_JOBS parallel jobs"

# Function to transcribe a single video
_transcribe_video() {
    local video_dir="$1"
    local total="$2"

    [[ -d "$video_dir" ]] || return 0
    [[ ! -f "$video_dir/meta.json" ]] && return 0

    video_id=$(basename "$video_dir")
    title=$(jq -r '.title' "$video_dir/meta.json")

    # Skip if already has transcript (idempotent)
    if [[ -f "$video_dir/transcript.txt" ]]; then
        echo "⏭️  Already transcribed: $title"
        return 0
    fi

    # Skip if already archived in youtube-dharma-talk (check by title in file content)
    video_date=$(jq -r '.date_fmt' "$video_dir/meta.json" 2>/dev/null || echo "")
    if [[ -n "$video_date" ]]; then
        archive_dir="$ROOT_DIR/${ARCHIVE_DIR:-youtube-dharma-talk}"
        year="${video_date:0:4}"
        # Check if title exists in any archive file for this date
        if ls "$archive_dir/$year/${video_date}"*.md 1>/dev/null 2>&1; then
            for archive_file in "$archive_dir/$year/${video_date}"*.md; do
                if grep -q "^# $title$" "$archive_file" 2>/dev/null; then
                    echo "⏭️  Already archived: $title"
                    return 0
                fi
            done
        fi
    fi

    # Case 1: Has subtitle file — convert to plain text
    subtitle_file=$(ls "$video_dir"/subtitle.* 2>/dev/null | head -1 || true)
    if [[ -n "$subtitle_file" ]]; then
        echo "📝 Converting subtitle: $title"
        # Strip VTT/SRT timing lines, sequence numbers, tags, blank lines; deduplicate adjacent identical lines
        sed -E \
            -e '/^WEBVTT/d' \
            -e '/^Kind:/d' \
            -e '/^Language:/d' \
            -e '/^[0-9]+$/d' \
            -e '/^[0-9]{2}:[0-9]{2}/d' \
            -e 's/<[^>]*>//g' \
            "$subtitle_file" \
            | grep -v '^$' \
            | awk '!seen[$0]++' \
            > "$video_dir/transcript.txt"
        echo "  ✅ Subtitle converted"
        return 0
    fi

    # Case 2: Has audio file — run mlx-whisper via Python
    audio_file=$(ls "$video_dir"/incoming.* 2>/dev/null | head -1 || true)
    if [[ -n "$audio_file" ]]; then
        echo "🎙️  Transcribing with mlx-whisper: $title"
        output_txt="$video_dir/transcript.txt"
        if python3 "$SCRIPT_DIR/transcribe_audio.py" "$audio_file" "$output_txt" "$WHISPER_MODEL" 2>&1; then
            if [[ -f "$output_txt" ]]; then
                echo "  ✅ Transcription complete"
            else
                echo "  ❌ mlx-whisper produced no output: $title"
            fi
        else
            echo "  ❌ Transcription failed: $title"
            # Leave temp dir intact for inspection; archiver will skip it
        fi
        return 0
    fi

    echo "⚠️  No subtitle or audio found: $title ($video_id)"
}

export -f _transcribe_video
export ROOT_DIR TEMP_DIR WHISPER_MODEL SCRIPT_DIR

# Find all video directories and process in parallel
find "$ROOT_DIR/$TEMP_DIR" -maxdepth 1 -type d -not -name "$TEMP_DIR" | \
    xargs -P "$PARALLEL_JOBS" -I {} bash -c "_transcribe_video '{}' '$total'"

echo "=== Stage 2 complete ==="
