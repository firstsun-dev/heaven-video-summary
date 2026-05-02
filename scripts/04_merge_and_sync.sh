#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

echo "=== Stage 4: Merge and Sync ==="
shopt -s nullglob
DIRS=("$ROOT_DIR/$ARCHIVE_DIR"/*/)
echo "Found ${#DIRS[@]} year directories in $ROOT_DIR/$ARCHIVE_DIR"
TOTAL=${#DIRS[@]}
current=0

for dir in "${DIRS[@]}"; do
    [[ -d "$dir" ]] || continue
    year=$(basename "$dir")
    echo "Processing $year..."

    # Regular Merged
    files=("$dir"*.md)
    reg_files=()
    for f in "${files[@]}"; do
        if [[ ! "$f" =~ "-timestamps.md" ]]; then
            reg_files+=("$f")
        fi
    done
    
    if ((${#reg_files[@]} > 0)); then
        echo "Found ${#reg_files[@]} regular files for $year"
        { echo "# $year 年度逐字稿合輯"; printf "\n"; for f in $(printf "%s\n" "${reg_files[@]}" | sort); do cat "$f"; printf "\n---\n\n"; done; } > "$ROOT_DIR/$ARCHIVE_DIR/${year}_Merged.md"
    fi
    
    # Timestamps Merged
    ts_files=("$dir"*-timestamps.md)
    if ((${#ts_files[@]} > 0)); then
        echo "Found ${#ts_files[@]} timestamp files for $year"
        { echo "# $year 年度逐字稿合輯（含時間戳）"; printf "\n"; for f in $(printf "%s\n" "${ts_files[@]}" | sort); do cat "$f"; printf "\n---\n\n"; done; } > "$ROOT_DIR/$ARCHIVE_DIR/${year}_Merged-timestamps.md"
    fi
done

if [[ -n "${RCLONE_REMOTE:-}" ]]; then
    echo "📤 Syncing merged files..."
    # 同步合併後的 Markdown 檔案 (供 NotebookLM 使用)
    rclone copy "$ROOT_DIR/$ARCHIVE_DIR" "$RCLONE_REMOTE" --include "*_Merged*.md"
    
    echo "📤 Syncing subtitle (.vtt) files..."
    # 同步原始字幕檔案 (保留年份路徑)
    rclone copy "$ROOT_DIR/$ARCHIVE_DIR" "$RCLONE_REMOTE" --include "**/*.vtt"
fi
printf "\n=== Stage 4 complete ===\n"
