#!/usr/bin/env bash
# Shared progress tracking utility

# Update progress counter with configurable format
# Usage: _update_progress <current> <total> <skipped> <action> <title> [format]
# format: "carriage" (default) for \r, "newline" for \n
_update_progress() {
    local current="$1"
    local total="$2"
    local skipped="$3"
    local action="$4"
    local title="$5"
    local format="${6:-carriage}"

    local percent=$((current * 100 / total))

    if [[ "$format" == "newline" ]]; then
        printf "(%d/%d) 影片 [%d%%] | %s: %s | (skipped: %d)\n" \
            "$current" "$total" "$percent" "$action" "$title" "$skipped"
    else
        # Default: carriage return for same-line updates
        printf "\r(%d/%d) 影片 [%d%%] | %s: %s | (skipped: %d)" \
            "$current" "$total" "$percent" "$action" "$title" "$skipped"
    fi
}
