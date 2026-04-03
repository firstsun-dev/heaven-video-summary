#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/config.env"
source "$SCRIPT_DIR/progress.sh"

ARCHIVE_DIR="${ARCHIVE_DIR:-youtube-dharma-talk}"

echo "=== Stage 4: Merge and Sync ==="

# Count total operations (merge + sync for both versions)
total_merges=$(find "$ROOT_DIR/$ARCHIVE_DIR" -maxdepth 1 -type d ! -name "$ARCHIVE_DIR" | wc -l)
total_syncs=$(($(find "$ROOT_DIR/$ARCHIVE_DIR" -maxdepth 1 -name "*_Merged.md" -type f | wc -l) * 2))
total=$((total_merges + total_syncs))

current=0
skipped=0

# Merge each year's files into {year}_Merged.md (both versions)
for year_dir in "$ROOT_DIR/$ARCHIVE_DIR"/*/; do
    [[ -d "$year_dir" ]] || continue
    year=$(basename "$year_dir")
    merged_file="$ROOT_DIR/$ARCHIVE_DIR/${year}_Merged.md"
    merged_file_ts="$ROOT_DIR/$ARCHIVE_DIR/${year}_Merged-timestamps.md"

    ((current++))
    _update_progress "$current" "$total" "$skipped" "📄 Merging" "$year"

    # Version 1: without timestamps
    {
        echo "# $year 年度逐字稿合輯"
        echo ""
        for md_file in $(ls "$year_dir"*.md 2>/dev/null | grep -v -- "-timestamps.md" | sort); do
            cat "$md_file"
            printf '\n\n---\n\n'
        done
    } > "$merged_file"

    # Version 2: with timestamps
    {
        echo "# $year 年度逐字稿合輯（含時間戳）"
        echo ""
        for md_file in $(ls "$year_dir"*-timestamps.md 2>/dev/null | sort); do
            cat "$md_file"
            printf '\n\n---\n\n'
        done
    } > "$merged_file_ts"
done

# Sync to Google Drive via rclone
if [[ -z "${RCLONE_REMOTE:-}" ]]; then
    echo "⚠️  RCLONE_REMOTE not set — skipping sync"
    printf "\n"
    echo "=== Stage 4 complete (no sync) ==="
    exit 0
fi

# Sync both versions of merged files
for merged_file in "$ROOT_DIR/$ARCHIVE_DIR"/*_Merged.md "$ROOT_DIR/$ARCHIVE_DIR"/*_Merged-timestamps.md; do
    [[ -f "$merged_file" ]] || continue
    ((current++))
    _update_progress "$current" "$total" "$skipped" "📤 Syncing" "$(basename "$merged_file")"
    rclone copy "$merged_file" "$RCLONE_REMOTE"
done

printf "\n"
echo "=== Stage 4 complete ==="
