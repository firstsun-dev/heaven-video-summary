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
current=0

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
        ((current++))
        echo "[$current/$total] 📝 Converting subtitle: $title"
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

    # Case 2: Has audio file — run mlx-whisper via Python
    audio_file=$(ls "$video_dir"incoming.* 2>/dev/null | head -1 || true)
    if [[ -n "$audio_file" ]]; then
        ((current++))
        echo "[$current/$total] 🎙️  Transcribing with mlx-whisper ($WHISPER_MODEL): $title"
        output_txt="$video_dir/transcript.txt"
        if python3 -c "
import mlx_whisper
import sys

result = mlx_whisper.transcribe('$audio_file', path_or_hf_repo='$WHISPER_MODEL', language='zh', initial_prompt='請用繁體中文回答', verbose=True)

with open('$output_txt', 'w', encoding='utf-8') as f:
    for segment in result['segments']:
        f.write(segment['text'].strip() + '\n')
print('Transcription complete', file=sys.stderr)
" 2>&1; then
            if [[ -f "$output_txt" ]]; then
                echo "  ✅ Transcription complete"
            else
                echo "  ❌ mlx-whisper produced no output: $title"
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
