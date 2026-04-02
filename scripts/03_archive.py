#!/usr/bin/env python3
"""Archive transcripts as Markdown with YAML frontmatter and update status.md."""

import json
import os
import re
import shutil
from pathlib import Path


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
        print(f"[03_archive] WARN: no meta.json in {video_dir}, skipping")
        return

    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    date_key = meta["date"]  # YYYYMMDD
    date_str = meta.get("date_fmt") or _raw_to_iso(date_key)

    txt_path = video_dir / "transcript.txt"
    if not txt_path.exists():
        print(f"[03_archive] WARN: no transcript.txt for {meta['title']}, skipping")
        return

    transcript = txt_path.read_text(encoding="utf-8")
    content = format_markdown(meta, transcript)

    dest = get_archive_path(date_str, archive_dir)
    dest.write_text(content, encoding="utf-8")
    print(f"[03_archive] Archived: {meta['title']} → {dest}")

    rel_link = f"./{archive_dir.name}/{date_str[:4]}/{dest.name}"
    update_status_row(status_path, date_key, meta["title"], "🗂️ 已存在", rel_link)

    shutil.rmtree(video_dir)
    print(f"[03_archive] Cleaned: {video_dir.name}")


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

    for video_dir in video_dirs:
        archive_video(video_dir, archive_dir, status_path)

    print("[03_archive] Done.")


if __name__ == "__main__":
    main()
