#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

echo "=== Stage 4: Merge and Sync ==="
DIRS=("$ROOT_DIR/$ARCHIVE_DIR"/*/)
TOTAL=${#DIRS[@]}
current=0

for dir in "${DIRS[@]}"; do
    [[ -d "$dir" ]] || continue
    year=$(basename "$dir")
    ((current++))
    update_progress "$current" "$TOTAL" 0 "📄 Merging" "$year"

    # Regular Merged
    { echo "# $year 年度逐字稿合輯"; printf "\n"; for f in $(ls "$dir"*.md 2>/dev/null | grep -v -- "-timestamps.md" | sort); do cat "$f"; printf "\n---\n\n"; done; } > "$ROOT_DIR/$ARCHIVE_DIR/${year}_Merged.md"
    
    # Timestamps Merged
    { echo "# $year 年度逐字稿合輯（含時間戳）"; printf "\n"; for f in $(ls "$dir"*-timestamps.md 2>/dev/null | sort); do cat "$f"; printf "\n---\n\n"; done; } > "$ROOT_DIR/$ARCHIVE_DIR/${year}_Merged-timestamps.md"
done

if [[ -n "${RCLONE_REMOTE:-}" ]]; then
    for f in "$ROOT_DIR/$ARCHIVE_DIR"/*_Merged*.md; do
        [[ -f "$f" ]] || continue
        echo "📤 Syncing $(basename "$f")..."
        rclone copy "$f" "$RCLONE_REMOTE"
    done
fi
printf "\n=== Stage 4 complete ===\n"
