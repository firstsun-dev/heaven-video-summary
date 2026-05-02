#!/usr/bin/env python3
import re
import json
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent

def load_config():
    config = {}
    config_path = ROOT_DIR / "config.env"
    if config_path.exists():
        for line in config_path.read_text().splitlines():
            if line.strip() and not line.startswith("#") and "=" in line:
                k, _, v = line.partition("=")
                config[k.strip()] = v.strip().strip('"').strip("'")
    return config

def extract_date_from_title(title, fallback_date):
    # Try YYYYMMDD
    match = re.search(r'(\d{8})', title)
    if match:
        d = match.group(1)
        return f"{d[:4]}-{d[4:6]}-{d[6:8]}"
    # Try YYYY-MM-DD
    match = re.search(r'(\d{4})-(\d{2})-(\d{2})', title)
    if match:
        return match.group(0)
    # Fallback YYYYMMDD -> YYYY-MM-DD
    return f"{fallback_date[:4]}-{fallback_date[4:6]}-{fallback_date[6:8]}"

def vtt_to_markdown(vtt_path: Path) -> str:
    if not vtt_path.exists(): return ""
    lines = vtt_path.read_text(encoding="utf-8").splitlines()
    result, ts = [], ""
    for line in lines:
        line = line.strip()
        if not line or line.startswith(("WEBVTT", "NOTE", "Kind:", "Language:")): continue
        if " --> " in line:
            ts = f"[{line.split(' --> ')[0].strip()}]"
        else:
            result.append(f"{ts} {line}" if ts else line)
            ts = ""
    return "\n".join(result)

def update_progress(current, total, skipped, action, title):
    percent = (current * 100) // total if total > 0 else 0
    print(f"\r({current}/{total}) [{percent}%] | {action}: {title} | (skipped: {skipped})", end="", flush=True)
