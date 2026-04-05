#!/usr/bin/env python3
"""Archive transcripts as Markdown with YAML frontmatter and update status.md."""

import json
import os
import re
import shutil
import sys
from pathlib import Path

# Ensure we're using the venv if present
venv_python = Path(__file__).parent.parent / ".venv" / "bin" / "python3"
if venv_python.exists() and sys.executable != str(venv_python):
    os.execv(str(venv_python), [str(venv_python)] + sys.argv)


def _update_progress(current: int, total: int, skipped: int, action: str, title: str) -> None:
    """Print progress counter on same line using carriage return."""
    percent = (current * 100) // total if total > 0 else 0
    print(
        f"\r({current}/{total}) 影片 [{percent}%] | {action}: {title} | (skipped: {skipped})",
        end="",
        flush=True
    )



def _load_config(root: Path) -> dict:
    config = {}
    config_path = root / "config.env"
    if not config_path.exists():
        return config
    for line in config_path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        config[key.strip()] = val.strip().strip('"').strip("'")
    return config


def format_markdown(meta: dict, transcript: str) -> str:
    date_str = meta.get("date_fmt") or _raw_to_iso(meta["date"])
    return (
        "---\n"
        f"title: {meta['title']}\n"
        f"date: {date_str}\n"
        f"url: {meta['url']}\n"
        f"channel: {meta['channel']}\n"
        f"duration: {meta['duration']}\n"
        "---\n\n"
        f"{transcript.strip()}\n"
    )


def _raw_to_iso(raw: str) -> str:
    """Convert YYYYMMDD to YYYY-MM-DD."""
    return f"{raw[:4]}-{raw[4:6]}-{raw[6:8]}"


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

def get_archive_path(date_str: str, archive_dir: Path) -> Path:
    """Return a free path, bumping to -2, -3 on same-day collision."""
    year = date_str[:4]
    year_dir = archive_dir / year
    year_dir.mkdir(parents=True, exist_ok=True)

    candidate = year_dir / f"{date_str}.md"
    if not candidate.exists():
        return candidate

    i = 2
    while True:
        candidate = year_dir / f"{date_str}-{i}.md"
        if not candidate.exists():
            return candidate
        i += 1


def update_status_row(
    status_path: Path, date_key: str, title: str, status: str, link: str = ""
) -> None:
    """Update the matching row in status.md; append if not found; create file if missing.

    Matches by both date and title: same date + same title = same entry.
    Data rows are sorted by date descending (newest first).
    """
    if not status_path.exists():
        status_path.write_text(
            "# 影片處理狀態報告\n\n"
            "| 日期       | 主題                               | 處理狀態   | 連結 |\n"
            "|:-----------|:-----------------------------------|:-----------|:-----|\n",
            encoding="utf-8",
        )

    lines = status_path.read_text(encoding="utf-8").splitlines(keepends=True)
    new_row = f"| {date_key} | {title} | {status} | {link} |\n"

    # Separate header from data rows
    header_lines = []
    data_lines = []

    for line in lines:
        # Header is title, empty line, and separator line
        if line.startswith("#") or line.strip() == "" or line.startswith("|:"):
            header_lines.append(line)
        # Header row: | 日期
        elif "| 日期" in line:
            header_lines.append(line)
        # Data rows start with | and contain date
        elif line.startswith("|"):
            data_lines.append(line)

    # Update or add the row, matching by both date and title
    found = False
    updated_data_lines = []
    for line in data_lines:
        # Extract date and title from existing row: | date | title | ... |
        match = re.match(rf"^\|\s*(\d+)\s*\|\s*(.+?)\s*\|", line)
        if match:
            existing_date = match.group(1)
            existing_title = match.group(2)
            # Match if both date and title are the same
            if existing_date == date_key and existing_title == title:
                updated_data_lines.append(new_row)
                found = True
            else:
                updated_data_lines.append(line)
        else:
            updated_data_lines.append(line)

    if not found:
        updated_data_lines.append(new_row)

    # Sort data rows by date (first column) descending (newest first)
    # Extract date from row format: | YYYYMMDD | ...
    def extract_date(row: str) -> str:
        match = re.match(r'^\|\s*(\d+)\s*\|', row)
        return match.group(1) if match else "0"

    updated_data_lines.sort(key=extract_date, reverse=True)

    # Reconstruct file
    status_path.write_text("".join(header_lines) + "".join(updated_data_lines), encoding="utf-8")


def _vtt_to_markdown(vtt_path: Path) -> str:
    """Convert VTT subtitle file to markdown with timestamps."""
    if not vtt_path.exists():
        return ""

    vtt_content = vtt_path.read_text(encoding="utf-8")
    lines = vtt_content.splitlines()

    result = []
    current_timestamp = ""

    for line in lines:
        line = line.rstrip()

        # Skip WEBVTT header and NOTE lines
        if line.startswith("WEBVTT") or line.startswith("NOTE"):
            continue

        # Detect timestamp lines (format: HH:MM:SS.mmm --> HH:MM:SS.mmm)
        if " --> " in line:
            # Extract start time (before -->)
            start_time = line.split(" --> ")[0].strip()
            current_timestamp = f"[{start_time}]"
            continue

        # Skip blank lines
        if line.strip() == "":
            continue

        # Add content with timestamp if we have one, otherwise just the text
        if current_timestamp:
            result.append(f"{current_timestamp} {line}")
            current_timestamp = ""
        elif line.strip():
            result.append(line)

    return "\n".join(result)


def archive_video(video_dir: Path, archive_dir: Path, status_path: Path) -> None:
    meta_path = video_dir / "meta.json"
    if not meta_path.exists():
        return

    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    pub_date = meta["date"]  # YYYYMMDD (publication date, used as fallback)
    title = meta["title"]

    # Extract lecture date from title, fallback to publication date
    date_str = _extract_date_from_title(title, pub_date)
    # Convert YYYY-MM-DD back to YYYYMMDD for status.md consistency
    date_key = date_str.replace("-", "")

    txt_path = video_dir / "transcript.txt"
    if not txt_path.exists():
        return

    # Archive transcript without timestamps
    transcript = txt_path.read_text(encoding="utf-8")
    content = format_markdown(meta, transcript)
    dest = get_archive_path(date_str, archive_dir)
    dest.write_text(content, encoding="utf-8")

    # Archive transcript with timestamps (from VTT file)
    vtt_files = list(video_dir.glob("subtitle.*"))
    if vtt_files:
        vtt_src = vtt_files[0]
        # Copy original VTT file
        vtt_dest = dest.parent / f"{dest.stem}{vtt_src.suffix}"
        shutil.copy2(vtt_src, vtt_dest)

        # Generate markdown with timestamps
        transcript_ts = _vtt_to_markdown(vtt_src)
        if transcript_ts:
            content_ts = format_markdown(meta, transcript_ts)
            ts_dest = dest.parent / f"{dest.stem}-timestamps.md"
            ts_dest.write_text(content_ts, encoding="utf-8")

    rel_link = f"./{archive_dir.name}/{date_str[:4]}/{dest.name}"
    # Use extracted date (from title) and title for matching duplicates
    update_status_row(status_path, date_key, meta["title"], "🗂️ 已存在", rel_link)

    shutil.rmtree(video_dir)


def main() -> None:
    root = Path(__file__).resolve().parent.parent
    config = _load_config(root)

    temp_dir = root / config.get("TEMP_DIR", "temp")
    archive_dir = root / config.get("ARCHIVE_DIR", "youtube-dharma-talk")
    status_path = root / "status.md"

    if not temp_dir.exists():
        print("[03_archive] No temp directory — nothing to archive.")
        return

    video_dirs = sorted(
        d for d in temp_dir.iterdir()
        if d.is_dir() and not d.name.startswith("._")
    )
    print(f"[03_archive] Processing {len(video_dirs)} video dir(s)...")

    current = 0
    skipped = 0

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

    print()  # Final newline
    print("[03_archive] Done.")


if __name__ == "__main__":
    main()
