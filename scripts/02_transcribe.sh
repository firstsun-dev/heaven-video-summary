#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/config.env"

TEMP_DIR="${TEMP_DIR:-temp}"
WHISPER_MODEL="${WHISPER_MODEL:-large-v3}"
WHISPER_LANGUAGE="${WHISPER_LANGUAGE:-Chinese}"

echo "=== Stage 2: Transcription ==="

for video_dir in "$ROOT_DIR/$TEMP_DIR"/*/; do
    [[ -d "$video_dir" ]] || continue
    [[ ! -f "$video_dir/meta.json" ]] && continue

    video_id=$(basename "$video_dir")
    title=$(jq -r '.title' "$video_dir/meta.json")

    # Skip if already has transcript (idempotent)
    if [[ -f "$video_dir/transcript.txt" ]]; then
        echo "⏭️  Already transcribed: $title"
        continue
    fi

    # Case 1: Has subtitle file — convert to plain text
    subtitle_file=$(ls "$video_dir"subtitle.* 2>/dev/null | head -1 || true)
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
        continue
    fi

    # Case 2: Has audio file — run faster-whisper
    audio_file=$(ls "$video_dir"incoming.* 2>/dev/null | head -1 || true)
    if [[ -n "$audio_file" ]]; then
        echo "🎙️  Transcribing with faster-whisper ($WHISPER_MODEL): $title"
        if faster-whisper "$audio_file" \
            --model "$WHISPER_MODEL" \
            --language "$WHISPER_LANGUAGE" \
            --output_format txt \
            --output_dir "$video_dir/"; then
            # faster-whisper names output after the input file (e.g. incoming.txt)
            whisper_output=$(ls "$video_dir"incoming*.txt 2>/dev/null | head -1 || true)
            if [[ -n "$whisper_output" ]]; then
                mv "$whisper_output" "$video_dir/transcript.txt"
                echo "  ✅ Transcription complete"
            else
                echo "  ❌ faster-whisper produced no output: $title"
            fi
        else
            echo "  ❌ Transcription failed: $title"
            # Leave temp dir intact for inspection; archiver will skip it
        fi
        continue
    fi

    echo "⚠️  No subtitle or audio found for: $title ($video_id)"
done

echo "=== Stage 2 complete ==="
