# Archive Date Extraction from Title Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the lecture date from video titles for archive filenames instead of using publication date, with publication date as fallback.

**Architecture:** Add a date extraction function to `03_archive.py` that uses regex to find YYYYMMDD or YYYY-MM-DD patterns in the video title. The function returns the extracted date or falls back to the publication date. Update `get_archive_path()` to use the extracted date.

**Tech Stack:** Python regex, pathlib

---

## File Structure

**Modified files:**
- `scripts/03_archive.py` — Add date extraction function, update archive path logic

---

## Task 1: Add Date Extraction Function

**Files:**
- Modify: `scripts/03_archive.py`

- [ ] **Step 1: Add date extraction function**

Add this function after `_raw_to_iso()` (around line 47):

```python
def _extract_date_from_title(title: str, fallback_date: str) -> str:
    """
    Extract lecture date from video title.
    
    Looks for YYYYMMDD or YYYY-MM-DD patterns in title.
    Returns extracted date in YYYY-MM-DD format, or fallback_date if not found.
    
    Args:
        title: Video title to search
        fallback_date: Date to use if extraction fails (YYYYMMDD format)
    
    Returns:
        Date in YYYY-MM-DD format
    """
    import re
    
    # Try to find YYYYMMDD pattern (e.g., 20220904)
    match = re.search(r'(\d{8})', title)
    if match:
        date_str = match.group(1)
        return f"{date_str[:4]}-{date_str[4:6]}-{date_str[6:8]}"
    
    # Try to find YYYY-MM-DD pattern
    match = re.search(r'(\d{4})-(\d{2})-(\d{2})', title)
    if match:
        return match.group(0)
    
    # Fallback to publication date
    return _raw_to_iso(fallback_date)
```

- [ ] **Step 2: Update archive_video() to use extracted date**

Modify the `archive_video()` function (around line 108) to extract the date from title:

Replace this section:
```python
def archive_video(video_dir: Path, archive_dir: Path, status_path: Path) -> None:
    meta_path = video_dir / "meta.json"
    if not meta_path.exists():
        return

    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    date_key = meta["date"]  # YYYYMMDD
    date_str = meta.get("date_fmt") or _raw_to_iso(date_key)
```

With:
```python
def archive_video(video_dir: Path, archive_dir: Path, status_path: Path) -> None:
    meta_path = video_dir / "meta.json"
    if not meta_path.exists():
        return

    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    date_key = meta["date"]  # YYYYMMDD (publication date)
    title = meta["title"]
    
    # Extract lecture date from title, fallback to publication date
    date_str = _extract_date_from_title(title, date_key)
```

- [ ] **Step 3: Test the changes**

Verify syntax:
```bash
python3 -m py_compile /Users/tianyao/Codes/heaven-video-summary/scripts/03_archive.py
```

Expected: No output (syntax OK)

- [ ] **Step 4: Verify with example**

Check that the existing archive entry uses the correct date:
```bash
grep "20220904\|2022-09-04" /Users/tianyao/Codes/heaven-video-summary/status.md
```

Expected: Should show the entry with 2022-09-04 date

- [ ] **Step 5: Commit**

```bash
git add scripts/03_archive.py
git commit -m "feat: extract lecture date from video title for archive filenames"
```

---

## Self-Review Checklist

✅ **Spec coverage:** 
- Extract date from title ✓
- Fall back to publication date ✓
- Use extracted date for archive filename ✓

✅ **Placeholder scan:** No TBD, TODO, or incomplete steps. All code is complete.

✅ **Type consistency:** Function signatures and variable names are consistent.

✅ **No gaps:** All requirements covered.
