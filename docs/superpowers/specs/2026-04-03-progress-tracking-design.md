---
name: Real-time Progress Tracking for Pipeline Stages
description: Add live progress counters to all four pipeline stages (fetch, transcribe, archive, merge)
type: feature
date: 2026-04-03
---

# Real-time Progress Tracking Design

## Overview

Add real-time progress counters to all four pipeline stages (01_fetch, 02_transcribe, 03_archive, 04_merge) to provide visibility into processing status. Each stage will display a live counter showing current progress, percentage, current action, and skipped count.

## Goals

- Provide real-time feedback during long-running pipeline stages
- Show which video is currently being processed
- Track and display skipped videos separately
- Maintain clean, readable output

## Architecture

### Progress Counter Format

```
(X/Y) 影片 [Z%] | action: title | (skipped: N)
```

Where:
- `X/Y` = current video / total videos (skipped videos count toward total)
- `Z%` = percentage complete
- `action` = current operation (📥 Processing, ⏭️ Already archived, 🎙️ Transcribing, etc.)
- `title` = video title
- `skipped: N` = count of skipped videos

### Stage-Specific Behavior

#### Stage 1: 01_fetch.sh
- Count total videos in playlist upfront
- Update progress counter on same line using `\r` (carriage return) as each video is processed
- Display action: 📥 Processing, ⏭️ Already in temp, ⏭️ Already archived
- Example: `(5/130) 影片 [3%] | 📥 Processing: Dharma Talk 5 | (skipped: 2)`

#### Stage 2: 02_transcribe.sh
- Count total videos to transcribe upfront
- Remove `PARALLEL_JOBS` mechanism — process sequentially
- For each video:
  1. Display mlx-whisper verbose output (if applicable)
  2. After completion, print progress counter on new line
- Display action: ⏭️ Already transcribed, 📝 Converting, 🎙️ Transcribing
- Example output:
  ```
  🎙️ Transcribing with mlx-whisper: Dharma Talk 1
  [mlx-whisper verbose output...]
  ✅ Transcription complete
  (1/130) 影片 [0%] | 🎙️ Transcribing: Dharma Talk 1 | (skipped: 0)
  ```

#### Stage 3: 03_archive.py
- Count total video directories upfront
- Update progress counter on same line using `\r` as each video is archived
- Display action: 🗂️ Archived, ⏭️ Skipped (no transcript)
- Example: `(10/130) 影片 [7%] | 🗂️ Archived: Dharma Talk 10 | (skipped: 3)`

#### Stage 4: 04_merge_and_sync.sh
- Count total files/operations upfront
- Update progress counter on same line using `\r`
- Display action: 📄 Merging, 📤 Syncing
- Example: `(2/4) 操作 [50%] | 📤 Syncing: 2025_Merged.md | (skipped: 0)`

## Implementation Details

### Bash Progress Function

Create a reusable bash function in each script:

```bash
_update_progress() {
    local current="$1"
    local total="$2"
    local skipped="$3"
    local action="$4"
    local title="$5"
    
    local percent=$((current * 100 / total))
    printf "\r(%d/%d) 影片 [%d%%] | %s: %s | (skipped: %d)" \
        "$current" "$total" "$percent" "$action" "$title" "$skipped"
}
```

### Changes Required

1. **01_fetch.sh**
   - Count total videos before loop
   - Call `_update_progress` after each video
   - Use `\r` for same-line updates

2. **02_transcribe.sh**
   - Remove `PARALLEL_JOBS` and `xargs -P` logic
   - Convert to sequential loop
   - Call `_update_progress` after each video (on new line)
   - Keep mlx-whisper verbose output intact

3. **03_archive.py**
   - Count total video directories upfront
   - Print progress counter after each video
   - Use `\r` for same-line updates (via `print(..., end='\r', flush=True)`)

4. **04_merge_and_sync.sh**
   - Count total operations upfront
   - Call `_update_progress` after each operation
   - Use `\r` for same-line updates

## Data Flow

```
Stage 1 (Fetch)
├─ Count total videos in playlist
├─ For each video:
│  ├─ Process (download/skip)
│  └─ Update progress counter
└─ Final newline

Stage 2 (Transcribe)
├─ Count total videos to transcribe
├─ For each video:
│  ├─ Show mlx-whisper output (if applicable)
│  └─ Print progress counter on new line
└─ Final newline

Stage 3 (Archive)
├─ Count total video directories
├─ For each video:
│  ├─ Archive (or skip)
│  └─ Update progress counter
└─ Final newline

Stage 4 (Merge & Sync)
├─ Count total operations
├─ For each operation:
│  ├─ Execute (merge/sync)
│  └─ Update progress counter
└─ Final newline
```

## Error Handling

- If a video fails to process, it still counts toward progress
- Skipped videos are tracked separately and displayed in counter
- Progress counter continues even if individual operations fail

## Testing Considerations

- Test with small playlist (5-10 videos) to verify counter updates
- Test with videos that are already archived (verify skipped count)
- Test with videos that fail (verify progress continues)
- Verify output is clean and readable (no garbled text from `\r`)

## Backwards Compatibility

- No breaking changes to existing functionality
- Progress tracking is additive (new output only)
- All existing status messages remain unchanged
- Scripts remain idempotent

## Future Enhancements

- ETA calculation based on average processing time
- Per-stage timing information
- Colored output for different actions
- JSON output mode for CI/CD integration
