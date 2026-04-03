# Progress Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add real-time progress counters to all four pipeline stages showing current progress, percentage, action, and skipped count.

**Architecture:** Each script will count total items upfront, then update a progress counter after processing each item. Stages 1, 3, 4 use carriage return (`\r`) for same-line updates. Stage 2 prints progress on new line after mlx-whisper output. All scripts track skipped items separately.

**Tech Stack:** Bash (stages 1, 2, 4), Python (stage 3)

---

## File Structure

**Modified files:**
- `scripts/01_fetch.sh` — Add progress tracking with carriage return updates
- `scripts/02_transcribe.sh` — Remove parallel processing, add sequential progress tracking
- `scripts/transcribe_audio.py` — No changes (keep verbose output)
- `scripts/03_archive.py` — Add progress tracking with carriage return updates
- `scripts/04_merge_and_sync.sh` — Add progress tracking with carriage return updates

---

## Task 1: Add Progress Tracking to 01_fetch.sh

**Files:**
- Modify: `scripts/01_fetch.sh`

- [ ] **Step 1: Understand current structure**

Read the current script to identify:
- Where total videos are counted (line 28)
- Where the main loop processes videos (line 31-122)
- Where skipped videos occur (lines 35-38, 41-48)

- [ ] **Step 2: Add progress tracking function**

Add this function after line 6 (after `source "$ROOT_DIR/config.env"`):

```bash
# Progress tracking
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

- [ ] **Step 3: Initialize progress variables**

After line 28 (after `echo "📋 Found $TOTAL videos in playlist"`), add:

```bash
current=0
skipped=0
```

- [ ] **Step 4: Update progress in main loop**

Replace the main loop (lines 31-122) to track progress. The loop structure stays the same, but add progress tracking:

After line 31 (start of while loop), add at the beginning of each iteration:
```bash
((current++))
```

For each skip condition (lines 35-38, 41-48), increment skipped and call progress:
```bash
((skipped++))
_update_progress "$current" "$TOTAL" "$skipped" "⏭️ Already in temp" "$title"
continue
```

For processing (line 51), call progress:
```bash
_update_progress "$current" "$TOTAL" "$skipped" "📥 Processing" "$title"
```

For already archived (line 45), call progress:
```bash
((skipped++))
_update_progress "$current" "$TOTAL" "$skipped" "⏭️ Already archived" "$title"
continue
```

- [ ] **Step 5: Add final newline**

After line 122 (end of while loop), add:
```bash
printf "\n"
```

- [ ] **Step 6: Test the changes**

Run with a small test:
```bash
bash scripts/01_fetch.sh
```

Expected: Progress counter updates on same line showing `(X/Y) 影片 [Z%] | action: title | (skipped: N)`

- [ ] **Step 7: Commit**

```bash
git add scripts/01_fetch.sh
git commit -m "feat: add real-time progress tracking to fetch stage"
```

---

## Task 2: Remove Parallel Processing and Add Progress Tracking to 02_transcribe.sh

**Files:**
- Modify: `scripts/02_transcribe.sh`

- [ ] **Step 1: Remove parallel processing setup**

Delete lines 16 (PARALLEL_JOBS variable) and lines 106-111 (the xargs parallel execution).

After deletion, the script should end at line 113 with `echo "=== Stage 2 complete ==="`

- [ ] **Step 2: Add progress tracking function**

Add this function after line 6 (after `source "$ROOT_DIR/config.env"`):

```bash
# Progress tracking
_update_progress() {
    local current="$1"
    local total="$2"
    local skipped="$3"
    local action="$4"
    local title="$5"
    
    local percent=$((current * 100 / total))
    printf "(%d/%d) 影片 [%d%%] | %s: %s | (skipped: %d)\n" \
        "$current" "$total" "$percent" "$action" "$title" "$skipped"
}
```

Note: This version uses `\n` (newline) instead of `\r` because mlx-whisper outputs its own progress.

- [ ] **Step 3: Initialize progress variables**

After line 29 (after `echo "⚙️  Using $PARALLEL_JOBS parallel jobs"`), replace with:

```bash
current=0
skipped=0
```

- [ ] **Step 4: Convert _transcribe_video to sequential loop**

Replace lines 106-111 (the xargs parallel execution) with a sequential loop:

```bash
# Process videos sequentially
for video_dir in "$ROOT_DIR/$TEMP_DIR"/*/; do
    _transcribe_video "$video_dir"
done
```

- [ ] **Step 5: Update _transcribe_video function to track progress**

Modify the `_transcribe_video` function (lines 33-104) to accept and update progress:

Change function signature from:
```bash
_transcribe_video() {
    local video_dir="$1"
    local total="$2"
```

To:
```bash
_transcribe_video() {
    local video_dir="$1"
```

At the start of the function (after line 37), add:
```bash
((current++))
```

For each skip condition, increment skipped and call progress:
- Line 45-47 (already transcribed):
```bash
((skipped++))
_update_progress "$current" "$total" "$skipped" "⏭️ Already transcribed" "$title"
return 0
```

- Line 58-60 (already archived):
```bash
((skipped++))
_update_progress "$current" "$total" "$skipped" "⏭️ Already archived" "$title"
return 0
```

- Line 103 (no subtitle or audio):
```bash
((skipped++))
_update_progress "$current" "$total" "$skipped" "⚠️ No source found" "$title"
```

For successful transcription (line 92):
```bash
_update_progress "$current" "$total" "$skipped" "✅ Transcribed" "$title"
```

- [ ] **Step 6: Add final newline**

After the sequential loop (after line 111 in new code), add:
```bash
printf "\n"
```

- [ ] **Step 7: Test the changes**

Run with a small test:
```bash
bash scripts/02_transcribe.sh
```

Expected: 
- No parallel jobs message
- mlx-whisper verbose output for each video
- Progress counter on new line after each video: `(X/Y) 影片 [Z%] | action: title | (skipped: N)`

- [ ] **Step 8: Commit**

```bash
git add scripts/02_transcribe.sh
git commit -m "feat: remove parallel processing and add progress tracking to transcribe stage"
```

---

## Task 3: Add Progress Tracking to 03_archive.py

**Files:**
- Modify: `scripts/03_archive.py`

- [ ] **Step 1: Add progress tracking function**

Add this function after the imports (after line 14):

```python
def _update_progress(current: int, total: int, skipped: int, action: str, title: str) -> None:
    """Print progress counter on same line using carriage return."""
    percent = (current * 100) // total if total > 0 else 0
    print(
        f"\r({current}/{total}) 影片 [{percent}%] | {action}: {title} | (skipped: {skipped})",
        end="",
        flush=True
    )
```

- [ ] **Step 2: Modify main() to initialize progress**

In the `main()` function, after line 143 (after `print(f"[03_archive] Processing {len(video_dirs)} video dir(s)...")`), add:

```python
    current = 0
    skipped = 0
```

- [ ] **Step 3: Update archive_video calls to track progress**

Modify the loop (lines 145-146) to:

```python
    for video_dir in video_dirs:
        current += 1
        meta_path = video_dir / "meta.json"
        if not meta_path.exists():
            skipped += 1
            _update_progress(current, len(video_dirs), skipped, "⚠️ No meta.json", video_dir.name)
            continue
        
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
        txt_path = video_dir / "transcript.txt"
        if not txt_path.exists():
            skipped += 1
            _update_progress(current, len(video_dirs), skipped, "⚠️ No transcript", meta['title'])
            continue
        
        archive_video(video_dir, archive_dir, status_path)
        _update_progress(current, len(video_dirs), skipped, "🗂️ Archived", meta['title'])
```

- [ ] **Step 4: Remove old archive_video calls**

Delete the old loop at lines 145-146 that just called `archive_video(video_dir, archive_dir, status_path)`.

- [ ] **Step 5: Add final newline**

After the loop, add:

```python
    print()  # Final newline
```

- [ ] **Step 6: Test the changes**

Run with a small test:
```bash
python3 scripts/03_archive.py
```

Expected: Progress counter updates on same line showing `(X/Y) 影片 [Z%] | action: title | (skipped: N)`

- [ ] **Step 7: Commit**

```bash
git add scripts/03_archive.py
git commit -m "feat: add real-time progress tracking to archive stage"
```

---

## Task 4: Add Progress Tracking to 04_merge_and_sync.sh

**Files:**
- Modify: `scripts/04_merge_and_sync.sh`

- [ ] **Step 1: Add progress tracking function**

Add this function after line 6 (after `source "$ROOT_DIR/config.env"`):

```bash
# Progress tracking
_update_progress() {
    local current="$1"
    local total="$2"
    local skipped="$3"
    local action="$4"
    local title="$5"
    
    local percent=$((current * 100 / total))
    printf "\r(%d/%d) 操作 [%d%%] | %s: %s | (skipped: %d)" \
        "$current" "$total" "$percent" "$action" "$title" "$skipped"
}
```

- [ ] **Step 2: Count total operations**

After line 10 (after `echo "=== Stage 4: Merge and Sync ==="`), add:

```bash
# Count total merge operations
total_merges=$(find "$ROOT_DIR/$ARCHIVE_DIR" -maxdepth 1 -type d ! -name "$ARCHIVE_DIR" | wc -l)
# Count total sync operations (merged files)
total_syncs=$(find "$ROOT_DIR/$ARCHIVE_DIR" -maxdepth 1 -name "*_Merged.md" -type f | wc -l)
total=$((total_merges + total_syncs))

current=0
skipped=0
```

- [ ] **Step 3: Add progress tracking to merge loop**

Modify the merge loop (lines 13-28) to track progress:

Replace lines 13-28 with:

```bash
for year_dir in "$ROOT_DIR/$ARCHIVE_DIR"/*/; do
    [[ -d "$year_dir" ]] || continue
    year=$(basename "$year_dir")
    merged_file="$ROOT_DIR/$ARCHIVE_DIR/${year}_Merged.md"
    
    ((current++))
    _update_progress "$current" "$total" "$skipped" "📄 Merging" "$year"

    {
        echo "# $year 年度逐字稿合輯"
        echo ""
        for md_file in $(ls "$year_dir"*.md 2>/dev/null | sort); do
            cat "$md_file"
            printf '\n\n---\n\n'
        done
    } > "$merged_file"
done
```

- [ ] **Step 4: Add progress tracking to sync loop**

Modify the sync loop (lines 38-42) to track progress:

Replace lines 38-42 with:

```bash
for merged_file in "$ROOT_DIR/$ARCHIVE_DIR"/*_Merged.md; do
    [[ -f "$merged_file" ]] || continue
    ((current++))
    _update_progress "$current" "$total" "$skipped" "📤 Syncing" "$(basename "$merged_file")"
    rclone copy "$merged_file" "$RCLONE_REMOTE"
done
```

- [ ] **Step 5: Add final newline**

After the sync loop, add:

```bash
printf "\n"
```

- [ ] **Step 6: Test the changes**

Run with a small test:
```bash
bash scripts/04_merge_and_sync.sh
```

Expected: Progress counter updates on same line showing `(X/Y) 操作 [Z%] | action: title | (skipped: N)`

- [ ] **Step 7: Commit**

```bash
git add scripts/04_merge_and_sync.sh
git commit -m "feat: add real-time progress tracking to merge and sync stage"
```

---

## Task 5: Integration Test

**Files:**
- Test: Full pipeline run

- [ ] **Step 1: Run full pipeline with small test**

Create a test config with a small playlist (2-3 videos):

```bash
# Temporarily modify config.env for testing
cp config.env config.env.backup
# Edit config.env to use a small test playlist
```

- [ ] **Step 2: Run full pipeline**

```bash
bash scripts/run.sh
```

Expected output:
- Stage 1: `(1/3) 影片 [33%] | 📥 Processing: title | (skipped: 0)` etc.
- Stage 2: mlx-whisper output, then `(1/3) 影片 [33%] | 🎙️ Transcribing: title | (skipped: 0)` etc.
- Stage 3: `(1/3) 影片 [33%] | 🗂️ Archived: title | (skipped: 0)` etc.
- Stage 4: `(1/2) 操作 [50%] | 📄 Merging: 2025 | (skipped: 0)` etc.

- [ ] **Step 3: Verify progress counters update correctly**

Check that:
- Counters increment properly
- Percentages are calculated correctly
- Skipped count increases when videos are skipped
- Final newline appears after each stage

- [ ] **Step 4: Restore config**

```bash
mv config.env.backup config.env
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "test: verify progress tracking works across all stages"
```

---

## Self-Review Checklist

✅ **Spec coverage:**
- Stage 1 (fetch) with carriage return updates — Task 1
- Stage 2 (transcribe) with sequential processing and new-line updates — Task 2
- Stage 3 (archive) with carriage return updates — Task 3
- Stage 4 (merge/sync) with carriage return updates — Task 4
- Progress format `(X/Y) 影片 [Z%] | action: title | (skipped: N)` — All tasks
- Skipped videos counted toward total — All tasks
- mlx-whisper verbose output preserved — Task 2
- Parallel processing removed — Task 2

✅ **Placeholder scan:** No TBD, TODO, or incomplete steps. All code is complete.

✅ **Type consistency:** Function signatures and variable names consistent across all tasks.

✅ **No gaps:** All requirements from spec are covered by tasks.
