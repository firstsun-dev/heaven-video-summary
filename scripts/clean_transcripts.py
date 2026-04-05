#!/usr/bin/env python3
"""Clean up LLM-generated ads and noise from transcripts."""

import re
import sys
from pathlib import Path

# Ensure we're using the venv if present
venv_python = Path(__file__).parent.parent / ".venv" / "bin" / "python3"
if venv_python.exists() and sys.executable != str(venv_python):
    import os
    os.execv(str(venv_python), [str(venv_python)] + sys.argv)


# Patterns to remove (垃圾廣告文字)
GARBAGE_PATTERNS = [
    r".*請用繁體中文回答.*",
    r".*请不吝点赞.*订阅.*转发.*打赏.*",
]


def clean_text(content: str) -> str:
    """Remove garbage patterns from content."""
    lines = content.split('\n')
    cleaned = []
    removed = 0

    for line in lines:
        should_remove = False
        for pattern in GARBAGE_PATTERNS:
            if re.search(pattern, line, re.IGNORECASE):
                should_remove = True
                removed += 1
                break

        if not should_remove:
            cleaned.append(line)

    return '\n'.join(cleaned), removed


def main() -> None:
    archive_dir = Path("youtube-dharma-talk")
    if not archive_dir.exists():
        print(f"❌ {archive_dir} not found")
        return

    # Find all .md files (both regular and -timestamps)
    md_files = sorted(archive_dir.rglob("*.md"))
    if not md_files:
        print(f"⚠️  No .md files found in {archive_dir}")
        return

    print(f"🔍 Found {len(md_files)} .md file(s)")
    total_removed = 0
    files_cleaned = 0

    for md_file in md_files:
        content = md_file.read_text(encoding="utf-8")
        cleaned, removed = clean_text(content)

        if removed > 0:
            md_file.write_text(cleaned, encoding="utf-8")
            print(f"✅ {md_file.name}: removed {removed} line(s)")
            total_removed += removed
            files_cleaned += 1

    print(f"\n📊 Summary: {files_cleaned} files cleaned, {total_removed} lines removed")


if __name__ == "__main__":
    main()
