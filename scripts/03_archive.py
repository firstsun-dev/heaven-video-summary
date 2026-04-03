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
    """Update the matching row in status.md; append if not found; create file if missing."""
    if not status_path.exists():
        status_path.write_text(
            "# 影片處理狀態報告\n\n"
            "| 日期       | 主題                               | 處理狀態   | 連結 |\n"
            "|:-----------|:-----------------------------------|:-----------|:-----|\n",
            encoding="utf-8",
        )

    lines = status_path.read_text(encoding="utf-8").splitlines(keepends=True)
    new_row = f"| {date_key} | {title} | {status} | {link} |\n"

    found = False
    new_lines = []
    for line in lines:
        if re.match(rf"^\|\s*{re.escape(date_key)}\s*\|", line):
            new_lines.append(new_row)
            found = True
        else:
            new_lines.append(line)

    if not found:
        new_lines.append(new_row)

    status_path.write_text("".join(new_lines), encoding="utf-8")


def archive_video(video_dir: Path, archive_dir: Path, status_path: Path) -> None:
    meta_path = video_dir / "meta.json"
    if not meta_path.exists():
        return

    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    date_key = meta["date"]  # YYYYMMDD (publication date)
    title = meta["title"]

    # Extract lecture date from title, fallback to publication date
    date_str = _extract_date_from_title(title, date_key)

    txt_path = video_dir / "transcript.txt"
    if not txt_path.exists():
        return

    transcript = txt_path.read_text(encoding="utf-8")
    content = format_markdown(meta, transcript)

    dest = get_archive_path(date_str, archive_dir)
    dest.write_text(content, encoding="utf-8")

    rel_link = f"./{archive_dir.name}/{date_str[:4]}/{dest.name}"
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
        if d.is_dir() and not d.name.startswith("_")
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
