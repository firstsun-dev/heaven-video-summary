#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

echo "=== Stage 4: Merge (Local) ==="

merge_year_dirs() {
    local target_dir="$1"
    local archive_name="$2"
    
    echo "Processing directory: $target_dir"
    shopt -s nullglob
    local DIRS=("$ROOT_DIR/$target_dir"/*/)
    
    for dir in "${DIRS[@]}"; do
        [[ -d "$dir" ]] || continue
        local year=$(basename "$dir")
        echo "  Merging $year..."

        # Regular Merged
        local files=("$dir"*.md)
        local reg_files=()
        for f in "${files[@]}"; do
            [[ "$f" == *"-timestamps.md" ]] && continue
            reg_files+=("$f")
        done
        
        if ((${#reg_files[@]} > 0)); then
            { 
                echo "# $year $archive_name 年度逐字稿合輯"; printf "\n"; 
                for f in $(printf "%s\n" "${reg_files[@]}" | sort); do cat "$f"; printf "\n---\n\n"; done; 
            } > "$ROOT_DIR/$target_dir/${year}_Merged.md"
        fi
        
        # Timestamps Merged
        local ts_files=("$dir"*-timestamps.md)
        if ((${#ts_files[@]} > 0)); then
            { 
                echo "# $year $archive_name 年度逐字稿合輯（含時間戳）"; printf "\n"; 
                for f in $(printf "%s\n" "${ts_files[@]}" | sort); do cat "$f"; printf "\n---\n\n"; done; 
            } > "$ROOT_DIR/$target_dir/${year}_Merged-timestamps.md"
        fi
    done
}

merge_year_dirs "$ARCHIVE_DIR" "YouTube 佛學講座"
[[ -d "$ROOT_DIR/$LEGACY_DIR" ]] && merge_year_dirs "$LEGACY_DIR" "舊音訊"

printf "\n=== Merge complete ===\n"
