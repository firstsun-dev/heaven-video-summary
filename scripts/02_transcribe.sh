#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

WHISPER_MODEL="${WHISPER_MODEL:-large-v3}"
echo "=== Stage 2: Transcription ($WHISPER_MODEL) ==="

DIRS=("$ROOT_DIR/$TEMP_DIR"/*/)
TOTAL=${#DIRS[@]}
current=0; skipped=0

for dir in "${DIRS[@]}"; do
    [[ -d "$dir" && -f "$dir/meta.json" ]] || continue
    ((current++))
    title=$(jq -r '.title' "$dir/meta.json")
    
    if [[ -f "$dir/transcript.txt" ]]; then
        ((skipped++)); update_progress "$current" "$TOTAL" "$skipped" "✅ Done" "$title"; continue
    fi

    update_progress "$current" "$TOTAL" "$skipped" "🎙️ Transcribing" "$title" "newline"
    
    sub=$(ls "$dir"/subtitle.* 2>/dev/null | head -1 || true)
    if [[ -n "$sub" ]]; then
        sed -E -e '/^WEBVTT|^Kind:|^Language:|^[0-9]+$|^[0-9]{2}:[0-9]{2}|<[^>]*>/d' "$sub" | grep -v '^\s*$' | awk '!seen[$0]++' > "$dir/transcript.txt"
    else
        audio=$(ls "$dir"/incoming.* 2>/dev/null | head -1 || true)
        [[ -n "$audio" ]] && python3 "$SCRIPT_DIR/transcribe_audio.py" "$audio" "$dir/transcript.txt" "$WHISPER_MODEL" || echo "⚠️ No source for $title"
    fi
done
printf "\n=== Stage 2 complete ===\n"
