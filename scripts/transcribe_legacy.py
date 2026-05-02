#!/usr/bin/env python3
"""
Transcribe legacy m4a files from Synology Drive and save to legacy-speech/
Directory structure: legacy-speech/{year}/{YYYY-MM-DD}.md
Status tracking: status-legacy.md
"""

import os
import re
import sys
from pathlib import Path
from datetime import datetime

# Import mlx_whisper (assuming it is installed in the environment)
try:
    import mlx_whisper
except ImportError:
    print("❌ mlx-whisper not found. Please install it with 'pip install mlx-whisper'")
    sys.exit(1)

# Config
SOURCE_DIR = "/Users/tianyao/Music/Music/Media/Music/天雲老師"
TARGET_DIR = Path("legacy-speech")
STATUS_FILE = Path("status-legacy.md")
# Use mlx-community/whisper-large-v3-turbo for high accuracy and speed
MODEL = os.getenv("WHISPER_MODEL", "mlx-community/whisper-large-v3-turbo")

def format_timestamp(seconds: float) -> str:
    """Convert seconds to [HH:MM:SS.mmm] format."""
    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    secs = seconds % 60
    return f"{hours:02d}:{minutes:02d}:{secs:06.3f}"

def extract_metadata(file_path: Path):
    """Extract year, date and title from filename or metadata."""
    # Try to find YYYY.MM.DD or YYYY-MM-DD in filename
    date_match = re.search(r"(\d{4})[.\-_]?(\d{2})[.\-_]?(\d{2})", file_path.name)
    if date_match:
        year, month, day = date_match.groups()
        date_str = f"{year}-{month}-{day}"
    else:
        # Fallback to file mtime
        mtime = datetime.fromtimestamp(file_path.stat().st_mtime)
        date_str = mtime.strftime("%Y-%m-%d")
        year = mtime.strftime("%Y")
    
    title = file_path.stem
    return year, date_str, title

def update_status_md(date_str, title, rel_path):
    """Update status-legacy.md with the processing result."""
    header = "# 舊音訊處理狀態報告\n\n| 日期 | 主題 | 處理狀態 |\n|:-----------|:-----------------------------------|:----------|\n"
    # Format date as YYYYMMDD for the status table column
    date_key = date_str.replace('-', '')
    new_entry = f"| {date_key} | [{title}]({rel_path}) | ✅ 已完成 |\n"
    
    if not STATUS_FILE.exists():
        with open(STATUS_FILE, "w", encoding="utf-8") as f:
            f.write(header + new_entry)
        return

    with open(STATUS_FILE, "r", encoding="utf-8") as f:
        lines = f.readlines()

    # Check if entry already exists (by path)
    if any(rel_path in line for line in lines):
        return

    # Insert new entry after header (descending order by date)
    # Header is 4 lines (including title and table alignment)
    header_end = 4
    lines.insert(header_end, new_entry)
    
    # Sort table rows (excluding header)
    table_rows = lines[4:]
    table_rows.sort(reverse=True) # Sort by date descending
    
    final_lines = lines[:4] + table_rows
    
    with open(STATUS_FILE, "w", encoding="utf-8") as f:
        f.writelines(final_lines)

def process_file(file_path: Path):
    """Transcribe a single file and save the output."""
    year, date_str, title = extract_metadata(file_path)
    output_dir = TARGET_DIR / year
    output_dir.mkdir(parents=True, exist_ok=True)
    
    plain_md = output_dir / f"{date_str}.md"
    timestamp_md = output_dir / f"{date_str}-timestamps.md"
    rel_path = f"./{plain_md}"
    
    if plain_md.exists():
        print(f"⏩ Skipping {file_path.name} (already exists)")
        update_status_md(date_str, title, rel_path)
        return

    print(f"🎙️ Transcribing {file_path.name}...")
    
    try:
        # Transcribe using mlx-whisper
        # Setting verbose=True to see progress
        result = mlx_whisper.transcribe(
            str(file_path),
            path_or_hf_repo=MODEL,
            language='zh',
            initial_prompt='請用繁體中文回答，關於佛學與禪宗的講座內容。',
            verbose=True
        )
        
        # Prepare YAML frontmatter
        frontmatter = (
            "---\n"
            f"title: {title}\n"
            f"date: {date_str}\n"
            "channel: SynologyDrive-music\n"
            "---\n\n"
        )
        
        # Save Plain MD
        with open(plain_md, 'w', encoding='utf-8') as f:
            f.write(frontmatter)
            for segment in result['segments']:
                f.write(segment['text'].strip() + '\n')
                
        # Save Timestamps MD
        with open(timestamp_md, 'w', encoding='utf-8') as f:
            f.write(frontmatter)
            for segment in result['segments']:
                start = format_timestamp(segment['start'])
                text = segment['text'].strip()
                f.write(f"[{start}] {text}\n")
        
        update_status_md(date_str, title, rel_path)
        print(f"✅ Finished: {plain_md}")
        
    except Exception as e:
        print(f"❌ Error transcribing {file_path.name}: {e}")

def main():
    source = Path(SOURCE_DIR)
    if not source.exists():
        print(f"❌ Source directory not found: {SOURCE_DIR}")
        return

    # Create target root
    TARGET_DIR.mkdir(exist_ok=True)

    # Find all m4a files recursively
    files = list(source.rglob("*.m4a"))
    if not files:
        print(f"ℹ️ No .m4a files found in {SOURCE_DIR}")
        return

    print(f"🔍 Found {len(files)} files to process.")
    
    # Process files (sorted by name/date)
    for f in sorted(files):
        process_file(f)

if __name__ == "__main__":
    main()
