#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Pass through arguments (e.g. --rebuild-all) to 01_fetch.sh
FETCH_ARGS="${*}"

echo "🚀 YouTube Dharma Talk Pipeline"
echo "================================"

run_stage() {
    local num="$1"
    local name="$2"
    shift 2
    echo ""
    echo "▶ Stage $num/4: $name"
    if ! "$@"; then
        echo ""
        echo "❌ Stage $num ($name) failed." >&2
        echo "   Re-run from this stage with:" >&2
        echo "   $*" >&2
        exit 1
    fi
}

run_stage 1 "Fetch"      bash "$SCRIPT_DIR/01_fetch.sh" $FETCH_ARGS
run_stage 2 "Transcribe" bash "$SCRIPT_DIR/02_transcribe.sh"
run_stage 3 "Archive"    python3 "$SCRIPT_DIR/03_archive.py"
run_stage 4 "Sync"       bash "$SCRIPT_DIR/04_merge_and_sync.sh"

echo ""
echo "================================"
echo "✅ Pipeline complete!"
