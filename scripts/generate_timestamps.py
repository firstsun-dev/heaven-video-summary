#!/usr/bin/env python3
"""Generate -timestamps.md files from existing .vtt subtitle files."""

import re
from pathlib import Path
import sys

# Ensure we're using the venv if present
venv_python = Path(__file__).parent.parent / ".venv" / "bin" / "python3"
if venv_python.exists() and sys.executable != str(venv_python):
    import os
    os.execv(str(venv_python), [str(venv_python)] + sys.argv)


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


def main() -> None:
    archive_dir = Path("youtube-dharma-talk")
    if not archive_dir.exists():
        print(f"❌ {archive_dir} not found")
        return

    # Find all .vtt files
    vtt_files = sorted(archive_dir.rglob("*.vtt"))
    if not vtt_files:
        print(f"⚠️  No .vtt files found in {archive_dir}")
        return

    print(f"📝 Found {len(vtt_files)} .vtt file(s)")
    created = 0
    skipped = 0

    for vtt_file in vtt_files:
        # Check if corresponding .md file exists
        base_path = vtt_file.with_suffix("")
        md_file = Path(str(base_path) + ".md")
        ts_file = Path(str(base_path) + "-timestamps.md")

        if not md_file.exists():
            print(f"⏭️  No .md for {vtt_file.name}")
            skipped += 1
            continue

        # Skip if -timestamps.md already exists
        if ts_file.exists():
            print(f"✓ {ts_file.name} already exists")
            skipped += 1
            continue

        # Read .md to get frontmatter
        md_content = md_file.read_text(encoding="utf-8")
        match = re.match(r"^(---\n.*?\n---)\n\n", md_content, re.DOTALL)
        if not match:
            print(f"⚠️  Cannot extract frontmatter from {md_file.name}")
            skipped += 1
            continue

        frontmatter = match.group(1)

        # Generate timestamps version
        transcript_ts = _vtt_to_markdown(vtt_file)
        if transcript_ts:
            content_ts = f"{frontmatter}\n\n{transcript_ts}\n"
            ts_file.write_text(content_ts, encoding="utf-8")
            print(f"✅ Created {ts_file.name}")
            created += 1
        else:
            print(f"⚠️  No content from {vtt_file.name}")
            skipped += 1

    print(f"\n📊 Summary: {created} created, {skipped} skipped")


if __name__ == "__main__":
    main()
