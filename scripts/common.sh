#!/usr/bin/env bash
# Common utilities for the pipeline

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load configuration
if [[ -f "$ROOT_DIR/config.env" ]]; then
    source "$ROOT_DIR/config.env"
fi

# Activate venv if present
if [[ -f "$ROOT_DIR/.venv/bin/activate" ]]; then
    source "$ROOT_DIR/.venv/bin/activate"
fi

# Directory settings
TEMP_DIR="${TEMP_DIR:-temp}"
ARCHIVE_DIR="${ARCHIVE_DIR:-youtube-dharma-talk}"
STATUS_FILE="$ROOT_DIR/status.md"

mkdir -p "$ROOT_DIR/$TEMP_DIR"

# Progress reporting
# Usage: update_progress <current> <total> <skipped> <action> <title> [format]
update_progress() {
    local current="$1" total="$2" skipped="$3" action="$4" title="$5" format="${6:-carriage}"
    local percent=$((total > 0 ? current * 100 / total : 0))
    local msg="(%d/%d) [%d%%] | %s: %s | (skipped: %d)"
    
    if [[ "$format" == "newline" ]]; then
        printf "$msg\n" "$current" "$total" "$percent" "$action" "$title" "$skipped"
    else
        printf "\r$msg" "$current" "$total" "$percent" "$action" "$title" "$skipped"
    fi
}

# Date extraction from title (YYYYMMDD or YYYY-MM-DD)
extract_date() {
    local title="$1" fallback="$2"
    if [[ "$title" =~ ([0-9]{8}) ]]; then
        local d="${BASH_REMATCH[1]}"
        echo "${d:0:4}-${d:4:2}-${d:6:2}"
    elif [[ "$title" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "${fallback:0:4}-${fallback:4:2}-${fallback:6:2}"
    fi
}

# Check if video is already archived in status.md or filesystem
is_archived() {
    local date_fmt="$1" title="$2"
    local date_key="${date_fmt//-/}"
    local year="${date_fmt:0:4}"
    
    # Check filesystem
    if ls "$ROOT_DIR/$ARCHIVE_DIR/$year/$date_fmt"*.md &>/dev/null; then
        return 0
    fi
    
    # Check status.md
    if [[ -f "$STATUS_FILE" ]] && grep -q "| $date_key |.*$title" "$STATUS_FILE"; then
        return 0
    fi
    
    return 1
}
