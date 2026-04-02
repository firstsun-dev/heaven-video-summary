#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/config.env"

ARCHIVE_DIR="${ARCHIVE_DIR:-youtube-dharma-talk}"

echo "=== Stage 4: Merge and Sync ==="

# Merge each year's files into {year}_Merged.md
for year_dir in "$ROOT_DIR/$ARCHIVE_DIR"/*/; do
    [[ -d "$year_dir" ]] || continue
    year=$(basename "$year_dir")
    merged_file="$ROOT_DIR/$ARCHIVE_DIR/${year}_Merged.md"

    echo "📦 Merging $year..."
    {
        echo "# $year 年度逐字稿合輯"
        echo ""
        for md_file in $(ls "$year_dir"*.md 2>/dev/null | sort); do
            cat "$md_file"
            printf '\n\n---\n\n'
        done
    } > "$merged_file"
    echo "  ✅ Created $merged_file ($(wc -l < "$merged_file" | tr -d ' ') lines)"
done

# Sync to Google Drive via rclone
if [[ -z "${RCLONE_REMOTE:-}" ]]; then
    echo "⚠️  RCLONE_REMOTE not set — skipping sync"
    echo "=== Stage 4 complete (no sync) ==="
    exit 0
fi

echo "☁️  Syncing to $RCLONE_REMOTE..."
for merged_file in "$ROOT_DIR/$ARCHIVE_DIR"/*_Merged.md; do
    [[ -f "$merged_file" ]] || continue
    rclone copy "$merged_file" "$RCLONE_REMOTE"
    echo "  ✅ Synced: $(basename "$merged_file")"
done

echo "=== Stage 4 complete ==="
