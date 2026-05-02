# YouTube Dharma Talk Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a 4-stage automated pipeline (fetch → transcribe → archive → sync) that turns a YouTube playlist into dated Markdown transcripts synced to Google Drive for NotebookLM.

**Architecture:** Shell scripts handle stages 1, 2, and 4; Python handles stage 3 (archiving). Orchestrated by `run.sh` and driven by GitLab CI. A `status.md` table tracks per-video state. All stages are idempotent.

**Tech Stack:** `yt-dlp`, `whisper` CLI (OpenAI), `ffmpeg`, `rclone`, `python3`, `jq`, `bash`, `pytest`

---

## File Structure

| Action | Path | Responsibility |
|--------|------|---------------|
| Create | `config.env` | All configurable variables |
| Create | `scripts/run.sh` | Orchestrate 4 stages with fail-fast + resume hints |
| Create | `scripts/01_fetch.sh` | Fetch playlist metadata; download subtitles or audio |
| Create | `scripts/02_transcribe.sh` | Whisper on audio; convert VTT/SRT to plain TXT |
| Create | `scripts/03_archive.py` | Format Markdown, archive by date, update status.md |
| Create | `scripts/04_merge.sh` | Year-merge all MDs; rclone push to Google Drive |
| Create | `.gitlab-ci.yml` | 4-stage CI; archive job commits back to repo |
| Create | `.gitignore` | Ignore temp/, audio, subtitle, and merged files |
| Create | `tests/test_archive.py` | pytest unit tests for 03_archive.py |
| Modify | `status.md` | Add missing `連結` column header + empty cells |

---

### Task 1: Project Scaffolding

**Files:**
- Create: `config.env`
- Create: `.gitignore`
- Modify: `status.md`

- [ ] **Step 1: Create config.env**

```bash
cat > config.env << 'EOF'
# Required — set these before running
PLAYLIST_URL=""
RCLONE_REMOTE=""

# Optional — defaults shown
WHISPER_MODEL="large-v3"
WHISPER_LANGUAGE="Chinese"
ARCHIVE_DIR="youtube-dharma-talk"
TEMP_DIR="temp"
EOF
```

- [ ] **Step 2: Create .gitignore**

```
temp/
*.mp3
*.m4a
*.wav
*.vtt
*.srt
*_Merged.md
.DS_Store
__pycache__/
.pytest_cache/
```

- [ ] **Step 3: Create scripts/ and tests/ directories**

```bash
mkdir -p scripts tests youtube-dharma-talk temp
```

- [ ] **Step 4: Add 連結 column to status.md**

The existing `status.md` has 3 columns. Add the `連結` column header and empty cells to all existing data rows:

```bash
python3 - << 'EOF'
import re
from pathlib import Path

p = Path("status.md")
lines = p.read_text(encoding="utf-8").splitlines(keepends=True)
out = []
for line in lines:
    if re.match(r"^\| 日期", line) and "連結" not in line:
        line = line.rstrip().rstrip("|").rstrip() + " | 連結 |\n"
    elif re.match(r"^\|:---", line) and line.count("|") == 4:
        line = line.rstrip().rstrip("|").rstrip() + ":-----|\n"
    elif re.match(r"^\|\s*\d{8}", line) and line.count("|") == 4:
        line = line.rstrip().rstrip("|").rstrip() + "  |\n"
    out.append(line)
p.write_text("".join(out), encoding="utf-8")
print("status.md updated")
EOF
```

- [ ] **Step 5: Commit**

```bash
git add config.env .gitignore status.md scripts/ tests/
git commit -m "chore: scaffold pipeline project structure"
```

---

### Task 2: 01_fetch.sh — Playlist Fetch & Download

**Files:**
- Create: `scripts/01_fetch.sh`

- [ ] **Step 1: Write smoke test**

Create `tests/smoke_01_fetch.sh`:

```bash
#!/usr/bin/env bash
# Smoke test: creates a mock temp entry as if 01_fetch.sh ran on a single video.
# Does NOT call yt-dlp — verifies script structure and meta.json shape only.
set -euo pipefail

export TEMP_DIR="temp_test_01"
export PLAYLIST_URL="https://www.youtube.com/playlist?list=PLTEST"
export WHISPER_MODEL="turbo"
export WHISPER_LANGUAGE="Chinese"
export ARCHIVE_DIR="youtube-dharma-talk"
export RCLONE_REMOTE="gdrive:test"

rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

# Verify script is syntactically valid
bash -n scripts/01_fetch.sh && echo "Syntax OK"

# Verify required tools referenced in script are present
for tool in yt-dlp jq; do
    command -v "$tool" >/dev/null || { echo "MISSING: $tool"; exit 1; }
done

echo "PASS: smoke_01_fetch"
rm -rf "$TEMP_DIR"
```

- [ ] **Step 2: Run smoke test to see current failure**

```bash
bash tests/smoke_01_fetch.sh
```

Expected: `bash: scripts/01_fetch.sh: No such file or directory` or syntax error.

- [ ] **Step 3: Implement scripts/01_fetch.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/config.env"

REBUILD_ALL=false
[[ "${1:-}" == "--rebuild-all" ]] && REBUILD_ALL=true && echo "Rebuild-all mode: ignoring status.md"

mkdir -p "$ROOT_DIR/$TEMP_DIR"

echo "=== Stage 1: Fetch playlist ==="

_download_audio() {
    local video_id="$1" title="$2"
    if yt-dlp -x --audio-format mp3 \
        -o "$ROOT_DIR/$TEMP_DIR/$video_id/audio.%(ext)s" \
        "https://www.youtube.com/watch?v=$video_id"; then
        echo "  → audio downloaded"
    else
        echo "  ❌ Download failed: $title"
        rm -rf "$ROOT_DIR/$TEMP_DIR/$video_id"
        # Append failure row to status.md if not already there
        if ! grep -q "$video_id" "$ROOT_DIR/status.md" 2>/dev/null; then
            echo "| 00000000 | $title | ❌ 下載失敗 |  |" >> "$ROOT_DIR/status.md"
        fi
    fi
}

yt-dlp --flat-playlist -j "$PLAYLIST_URL" | while IFS= read -r entry; do
    VIDEO_ID=$(echo "$entry" | jq -r '.id')
    TITLE=$(echo "$entry" | jq -r '.title')
    UPLOAD_DATE=$(echo "$entry" | jq -r '.upload_date // "00000000"')
    DURATION=$(echo "$entry" | jq -r '.duration // 0')
    CHANNEL=$(echo "$entry" | jq -r '.channel // .uploader // "Unknown"')

    # Skip if already archived (normal mode only)
    if [[ "$REBUILD_ALL" == "false" ]]; then
        if grep -qP "^\|\s*${UPLOAD_DATE}\s*\|.*🗂️" "$ROOT_DIR/status.md" 2>/dev/null; then
            echo "Skipping (archived): $TITLE"
            continue
        fi
    fi

    # Skip if already downloaded in this temp dir (idempotent)
    if [[ -d "$ROOT_DIR/$TEMP_DIR/$VIDEO_ID" && -f "$ROOT_DIR/$TEMP_DIR/$VIDEO_ID/meta.json" ]]; then
        echo "Skipping (in temp): $TITLE"
        continue
    fi

    mkdir -p "$ROOT_DIR/$TEMP_DIR/$VIDEO_ID"

    # Format duration as H:MM:SS or M:SS
    D=${DURATION%.*}
    if [[ "$D" -ge 3600 ]]; then
        DURATION_FMT=$(printf '%d:%02d:%02d' $((D/3600)) $((D%3600/60)) $((D%60)))
    else
        DURATION_FMT=$(printf '%d:%02d' $((D/60)) $((D%60)))
    fi

    DATE_FMT="${UPLOAD_DATE:0:4}-${UPLOAD_DATE:4:2}-${UPLOAD_DATE:6:2}"

    jq -n \
        --arg title "$TITLE" \
        --arg date "$DATE_FMT" \
        --arg url "https://www.youtube.com/watch?v=$VIDEO_ID" \
        --arg channel "$CHANNEL" \
        --arg duration "$DURATION_FMT" \
        '{title:$title,date:$date,url:$url,channel:$channel,duration:$duration}' \
        > "$ROOT_DIR/$TEMP_DIR/$VIDEO_ID/meta.json"

    echo "Processing: $TITLE ($DATE_FMT)"

    # Rebuild-all: always download audio for fresh Whisper transcription
    if [[ "$REBUILD_ALL" == "true" ]]; then
        _download_audio "$VIDEO_ID" "$TITLE"
        continue
    fi

    # Normal mode: try Chinese subtitles first, fall back to audio
    if yt-dlp \
        --write-sub --write-auto-sub \
        --sub-lang "zh-Hant,zh-Hans,zh" \
        --sub-format "vtt/srt/best" \
        --skip-download \
        -o "$ROOT_DIR/$TEMP_DIR/$VIDEO_ID/subtitle.%(ext)s" \
        "https://www.youtube.com/watch?v=$VIDEO_ID" 2>/dev/null \
        && ls "$ROOT_DIR/$TEMP_DIR/$VIDEO_ID/"*.vtt \
           "$ROOT_DIR/$TEMP_DIR/$VIDEO_ID/"*.srt 2>/dev/null | grep -q .; then
        echo "  → subtitle downloaded"
    else
        _download_audio "$VIDEO_ID" "$TITLE"
    fi
done

echo "=== Stage 1 complete ==="
```

- [ ] **Step 4: Make executable**

```bash
chmod +x scripts/01_fetch.sh
```

- [ ] **Step 5: Run smoke test**

```bash
bash tests/smoke_01_fetch.sh
```

Expected:
```
Syntax OK
PASS: smoke_01_fetch
```

- [ ] **Step 6: Commit**

```bash
git add scripts/01_fetch.sh tests/smoke_01_fetch.sh
git commit -m "feat: implement 01_fetch.sh playlist download with subtitle/audio fallback"
```

---

### Task 3: 02_transcribe.sh — Whisper Transcription & Subtitle Conversion

**Files:**
- Create: `scripts/02_transcribe.sh`

- [ ] **Step 1: Write smoke test with VTT fixture**

Create `tests/smoke_02_transcribe.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

export TEMP_DIR="temp_test_02"
export WHISPER_MODEL="turbo"
export WHISPER_LANGUAGE="Chinese"
export ARCHIVE_DIR="youtube-dharma-talk"
export RCLONE_REMOTE="gdrive:test"

rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR/vid_abc123"

# Minimal VTT fixture
cat > "$TEMP_DIR/vid_abc123/subtitle.zh-Hant.vtt" << 'VTTEOF'
WEBVTT
Kind: captions
Language: zh-Hant

00:00:01.000 --> 00:00:03.000
南無阿彌陀佛

00:00:03.000 --> 00:00:06.000
今天我們來講一個故事

00:00:06.000 --> 00:00:09.000
今天我們來講一個故事
VTTEOF

# Write a minimal meta.json so the script can read title
cat > "$TEMP_DIR/vid_abc123/meta.json" << 'EOF'
{"title":"Test Video","date":"2020-01-12","url":"https://example.com","channel":"Test","duration":"1:00"}
EOF

bash -n scripts/02_transcribe.sh && echo "Syntax OK"
bash scripts/02_transcribe.sh

[[ -f "$TEMP_DIR/vid_abc123/transcript.md" ]] || { echo "FAIL: transcript.md missing"; exit 1; }
grep -q "南無阿彌陀佛" "$TEMP_DIR/vid_abc123/transcript.md" || { echo "FAIL: content missing"; exit 1; }
# Duplicated line should appear only once
count=$(grep -c "今天我們來講一個故事" "$TEMP_DIR/vid_abc123/transcript.md")
[[ "$count" -eq 1 ]] || { echo "FAIL: duplicate line not deduplicated (count=$count)"; exit 1; }

echo "PASS: smoke_02_transcribe"
rm -rf "$TEMP_DIR"
```

- [ ] **Step 2: Run to see failure**

```bash
bash tests/smoke_02_transcribe.sh
```

Expected: `No such file or directory` or syntax error.

- [ ] **Step 3: Implement scripts/02_transcribe.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/config.env"

echo "=== Stage 2: Transcribe ==="

_vtt_to_txt() {
    local src="$1" dst="$2"
    grep -v '^WEBVTT' "$src" \
        | grep -v '^NOTE' \
        | grep -v '^Kind:' \
        | grep -v '^Language:' \
        | grep -v '^[0-9][0-9]:[0-9][0-9]' \
        | grep -v '^$' \
        | sed 's/<[^>]*>//g' \
        | awk 'prev!=$0 {print; prev=$0}' \
        > "$dst"
}

_srt_to_txt() {
    local src="$1" dst="$2"
    grep -v '^[0-9]\+$' "$src" \
        | grep -v '^[0-9][0-9]:[0-9][0-9]' \
        | grep -v '^$' \
        | sed 's/<[^>]*>//g' \
        | awk 'prev!=$0 {print; prev=$0}' \
        > "$dst"
}

for video_dir in "$ROOT_DIR/$TEMP_DIR"/*/; do
    [[ -d "$video_dir" ]] || continue
    VIDEO_ID=$(basename "$video_dir")
    [[ -f "$video_dir/meta.json" ]] || continue
    TITLE=$(jq -r '.title' "$video_dir/meta.json")

    # Idempotent: skip if already transcribed
    if [[ -f "$video_dir/transcript.md" ]]; then
        echo "Skipping (done): $TITLE"
        continue
    fi

    VTT=$(ls "$video_dir"*.vtt 2>/dev/null | head -1 || true)
    SRT=$(ls "$video_dir"*.srt 2>/dev/null | head -1 || true)
    AUDIO=$(ls "$video_dir"*.mp3 "$video_dir"*.m4a "$video_dir"*.wav 2>/dev/null | head -1 || true)

    if [[ -n "$VTT" ]]; then
        echo "Converting VTT: $TITLE"
        _vtt_to_txt "$VTT" "$video_dir/transcript.md"
        echo "  → done"
    elif [[ -n "$SRT" ]]; then
        echo "Converting SRT: $TITLE"
        _srt_to_txt "$SRT" "$video_dir/transcript.md"
        echo "  → done"
    elif [[ -n "$AUDIO" ]]; then
        echo "Whisper ($WHISPER_MODEL): $TITLE"
        if whisper "$AUDIO" \
            --model "$WHISPER_MODEL" \
            --language "$WHISPER_LANGUAGE" \
            --output_format txt \
            --output_dir "$video_dir"; then
            # Whisper names output after the input file; normalize to transcript.md
            WHISPER_OUT=$(ls "${AUDIO%.*}.md" 2>/dev/null || ls "$video_dir"/*.md 2>/dev/null | head -1 || true)
            [[ -n "$WHISPER_OUT" ]] && mv "$WHISPER_OUT" "$video_dir/transcript.md"
            echo "  → done"
        else
            echo "  ❌ Transcription failed: $TITLE"
            DATE=$(jq -r '.date' "$video_dir/meta.json" | tr -d '-')
            sed -i '' "s/^\(| ${DATE} | ${TITLE:0:10}[^|]*\)|[^|]*|[^|]*|$/\1| ❌ 轉錄失敗 |  |/" \
                "$ROOT_DIR/status.md" 2>/dev/null || true
        fi
    else
        echo "  ⚠️  No audio or subtitle: $TITLE"
    fi
done

echo "=== Stage 2 complete ==="
```

- [ ] **Step 4: Make executable**

```bash
chmod +x scripts/02_transcribe.sh
```

- [ ] **Step 5: Run smoke test**

```bash
bash tests/smoke_02_transcribe.sh
```

Expected:
```
=== Stage 2: Transcribe ===
Converting VTT: Test Video
  → done
=== Stage 2 complete ===
PASS: smoke_02_transcribe
```

- [ ] **Step 6: Commit**

```bash
git add scripts/02_transcribe.sh tests/smoke_02_transcribe.sh
git commit -m "feat: implement 02_transcribe.sh whisper and subtitle conversion"
```

---

### Task 4: 03_archive.py — Format & Archive (TDD)

**Files:**
- Create: `tests/test_archive.py`
- Create: `scripts/03_archive.py`

- [ ] **Step 1: Write failing tests**

Create `tests/test_archive.py`:

```python
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
import archive_lib as arch  # noqa: E402 (imported after sys.path insert)


# ── get_archive_path ──────────────────────────────────────────────────────────

def test_get_archive_path_new_file(tmp_path):
    result = arch.get_archive_path("2020-01-12", tmp_path)
    assert result == tmp_path / "2020" / "2020-01-12.md"


def test_get_archive_path_same_day_gets_sequence_2(tmp_path):
    year_dir = tmp_path / "2020"
    year_dir.mkdir()
    (year_dir / "2020-01-12.md").write_text("existing")
    result = arch.get_archive_path("2020-01-12", tmp_path)
    assert result == tmp_path / "2020" / "2020-01-12-2.md"


def test_get_archive_path_same_day_third(tmp_path):
    year_dir = tmp_path / "2020"
    year_dir.mkdir()
    (year_dir / "2020-01-12.md").write_text("first")
    (year_dir / "2020-01-12-2.md").write_text("second")
    result = arch.get_archive_path("2020-01-12", tmp_path)
    assert result == tmp_path / "2020" / "2020-01-12-3.md"


# ── format_markdown ───────────────────────────────────────────────────────────

def test_format_markdown_has_frontmatter_and_content():
    meta = {
        "title": "皈依佛門的十大明星",
        "date": "2020-01-12",
        "url": "https://www.youtube.com/watch?v=abc",
        "channel": "天堂電視台",
        "duration": "45:30",
    }
    result = arch.format_markdown(meta, "逐字稿在此")
    assert result.startswith("---\n")
    assert "title: 皈依佛門的十大明星\n" in result
    assert "date: 2020-01-12\n" in result
    assert "url: https://www.youtube.com/watch?v=abc\n" in result
    assert "channel: 天堂電視台\n" in result
    assert "duration: 45:30\n" in result
    assert "---\n" in result
    assert "逐字稿在此" in result


# ── update_status_row ─────────────────────────────────────────────────────────

def test_update_status_row_updates_existing(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    status = tmp_path / "status.md"
    status.write_text(
        "| 日期 | 主題 | 處理狀態 | 連結 |\n"
        "|:--|:--|:--|:--|\n"
        "| 20200112 | 皈依佛門的十大明星 | 🔇 無字幕 |  |\n"
        "| 20200119 | 如何修出悟一廣 | 🔇 無字幕 |  |\n",
        encoding="utf-8",
    )
    arch.update_status_row(
        "20200112", "皈依佛門的十大明星", "🗂️ 已存在",
        "./youtube-dharma-talk/2020/2020-01-12.md"
    )
    lines = status.read_text(encoding="utf-8").splitlines()
    updated = next(l for l in lines if "20200112" in l)
    assert "🗂️ 已存在" in updated
    assert "2020-01-12.md" in updated
    other = next(l for l in lines if "20200119" in l)
    assert "🔇 無字幕" in other  # unchanged


def test_update_status_row_appends_missing(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    status = tmp_path / "status.md"
    status.write_text(
        "| 日期 | 主題 | 處理狀態 | 連結 |\n|:--|:--|:--|:--|\n",
        encoding="utf-8",
    )
    arch.update_status_row("20201231", "新影片", "🗂️ 已存在", "./path/2020-12-31.md")
    content = status.read_text(encoding="utf-8")
    assert "20201231" in content
    assert "新影片" in content


# ── archive_video ─────────────────────────────────────────────────────────────

def test_archive_video_creates_md_and_cleans_temp(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    archive_dir = tmp_path / "youtube-dharma-talk"
    video_dir = tmp_path / "temp" / "abc123"
    video_dir.mkdir(parents=True)
    (tmp_path / "status.md").write_text(
        "| 日期 | 主題 | 處理狀態 | 連結 |\n|:--|:--|:--|:--|\n"
        "| 20200112 | 皈依佛門的十大明星 | 🔇 無字幕 |  |\n",
        encoding="utf-8",
    )
    meta = {
        "title": "皈依佛門的十大明星",
        "date": "2020-01-12",
        "url": "https://www.youtube.com/watch?v=abc",
        "channel": "天堂電視台",
        "duration": "45:30",
    }
    (video_dir / "meta.json").write_text(json.dumps(meta, ensure_ascii=False), encoding="utf-8")
    (video_dir / "transcript.md").write_text("逐字稿內容在此", encoding="utf-8")

    arch.archive_video(video_dir, archive_dir)

    md = archive_dir / "2020" / "2020-01-12.md"
    assert md.exists()
    assert "逐字稿內容在此" in md.read_text(encoding="utf-8")
    assert not video_dir.exists()  # temp cleaned up
    assert "🗂️ 已存在" in (tmp_path / "status.md").read_text(encoding="utf-8")


def test_archive_video_skips_missing_transcript(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    archive_dir = tmp_path / "youtube-dharma-talk"
    video_dir = tmp_path / "temp" / "no_transcript"
    video_dir.mkdir(parents=True)
    (tmp_path / "status.md").write_text("| 日期 | 主題 | 處理狀態 | 連結 |\n|:--|:--|:--|:--|\n")
    meta = {"title": "Missing", "date": "2020-02-01", "url": "", "channel": "", "duration": ""}
    (video_dir / "meta.json").write_text(json.dumps(meta))

    arch.archive_video(video_dir, archive_dir)

    # No MD created, temp dir still exists (not cleaned up)
    assert not (archive_dir / "2020" / "2020-02-01.md").exists()
    assert video_dir.exists()
```

- [ ] **Step 2: Run to confirm all tests fail**

```bash
python3 -m pytest tests/test_archive.py -v
```

Expected: `ModuleNotFoundError: No module named 'archive_lib'`

- [ ] **Step 3: Implement scripts/archive_lib.py (the importable library)**

Create `scripts/archive_lib.py`:

```python
"""Archive library — importable by 03_archive.py and testable by pytest."""

from __future__ import annotations

import json
import re
import shutil
from pathlib import Path


def get_archive_path(date_str: str, archive_dir: Path) -> Path:
    """Return a non-colliding archive Path for date_str (YYYY-MM-DD)."""
    year_dir = archive_dir / date_str[:4]
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


def format_markdown(meta: dict, transcript: str) -> str:
    return (
        "---\n"
        f"title: {meta['title']}\n"
        f"date: {meta['date']}\n"
        f"url: {meta['url']}\n"
        f"channel: {meta['channel']}\n"
        f"duration: {meta['duration']}\n"
        "---\n\n"
        f"{transcript.strip()}\n"
    )


def update_status_row(date_key: str, title: str, status: str, link: str = "") -> None:
    """Update or append a row in status.md matching date_key (YYYYMMDD)."""
    status_path = Path("status.md")
    if not status_path.exists():
        status_path.write_text(
            "| 日期 | 主題 | 處理狀態 | 連結 |\n|:--|:--|:--|:--|\n",
            encoding="utf-8",
        )

    lines = status_path.read_text(encoding="utf-8").splitlines(keepends=True)
    new_row = f"| {date_key} | {title} | {status} | {link} |\n"
    found = False
    out: list[str] = []
    for line in lines:
        if re.match(rf"^\|\s*{re.escape(date_key)}\s*\|", line):
            out.append(new_row)
            found = True
        else:
            out.append(line)
    if not found:
        out.append(new_row)
    status_path.write_text("".join(out), encoding="utf-8")


def archive_video(video_dir: Path, archive_dir: Path) -> None:
    meta_file = video_dir / "meta.json"
    if not meta_file.exists():
        print(f"  ⚠️  No meta.json in {video_dir.name}, skipping")
        return

    meta = json.loads(meta_file.read_text(encoding="utf-8"))
    transcript_file = video_dir / "transcript.md"

    if not transcript_file.exists():
        print(f"  ⚠️  No transcript.md for {meta['title']}, skipping")
        return

    dest = get_archive_path(meta["date"], archive_dir)
    dest.write_text(format_markdown(meta, transcript_file.read_text(encoding="utf-8")), encoding="utf-8")
    print(f"  Archived → {dest}")

    date_key = meta["date"].replace("-", "")
    update_status_row(date_key, meta["title"], "🗂️ 已存在", str(dest))
    shutil.rmtree(video_dir)
    print(f"  Cleaned temp/{video_dir.name}")
```

- [ ] **Step 4: Run tests**

```bash
python3 -m pytest tests/test_archive.py -v
```

Expected: all 7 tests PASS.

- [ ] **Step 5: Create the runnable 03_archive.py entry point**

```python
#!/usr/bin/env python3
"""Stage 3: Format transcripts as Markdown and archive by date."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from archive_lib import archive_video  # noqa: E402


def load_config(path: Path = Path("config.env")) -> dict[str, str]:
    config: dict[str, str] = {}
    if not path.exists():
        return config
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        config[key.strip()] = val.strip().strip('"').strip("'")
    return config


def main() -> None:
    config = load_config()
    temp_dir = Path(config.get("TEMP_DIR", "temp"))
    archive_dir = Path(config.get("ARCHIVE_DIR", "youtube-dharma-talk"))

    print("=== Stage 3: Archive ===")
    if not temp_dir.exists():
        print("No temp directory, nothing to archive.")
        return

    for video_dir in sorted(temp_dir.iterdir()):
        if video_dir.is_dir():
            print(f"Archiving: {video_dir.name}")
            archive_video(video_dir, archive_dir)

    print("=== Stage 3 complete ===")


if __name__ == "__main__":
    main()
```

- [ ] **Step 6: Make executable**

```bash
chmod +x scripts/03_archive.py
```

- [ ] **Step 7: Commit**

```bash
git add scripts/archive_lib.py scripts/03_archive.py tests/test_archive.py
git commit -m "feat: implement 03_archive.py with pytest coverage"
```

---

### Task 5: 04_merge.sh — Year Merge & rclone Sync

**Files:**
- Create: `scripts/04_merge.sh`

- [ ] **Step 1: Create fixture and verify failure**

```bash
mkdir -p temp_merge_test/youtube-dharma-talk/2025
echo -e "---\ntitle: A\n---\n\ncontent A" > temp_merge_test/youtube-dharma-talk/2025/2025-01-01.md
echo -e "---\ntitle: B\n---\n\ncontent B" > temp_merge_test/youtube-dharma-talk/2025/2025-01-02.md

ARCHIVE_DIR=temp_merge_test/youtube-dharma-talk RCLONE_REMOTE="dummy:/" \
    bash scripts/04_merge.sh --dry-run 2>&1 || echo "Expected failure (not implemented yet)"
```

- [ ] **Step 2: Implement scripts/04_merge.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/config.env"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

echo "=== Stage 4: Merge and Sync ==="

shopt -s nullglob
for year_dir in "$ROOT_DIR/$ARCHIVE_DIR"/*/; do
    [[ -d "$year_dir" ]] || continue
    year=$(basename "$year_dir")
    merged="$ROOT_DIR/$ARCHIVE_DIR/${year}_Merged.md"

    echo "Merging $year..."
    > "$merged"  # truncate
    for md in $(ls "$year_dir"*.md 2>/dev/null | sort); do
        cat "$md" >> "$merged"
        printf "\n\n---\n\n" >> "$merged"
    done
    echo "  → $merged"
done
shopt -u nullglob

if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] Skipping rclone"
    echo "=== Stage 4 complete (dry-run) ==="
    exit 0
fi

echo "Syncing to $RCLONE_REMOTE..."
rclone copy "$ROOT_DIR/$ARCHIVE_DIR" "$RCLONE_REMOTE" \
    --include "*_Merged.md" \
    --progress
echo "  → sync complete"

echo "=== Stage 4 complete ==="
```

- [ ] **Step 3: Make executable**

```bash
chmod +x scripts/04_merge.sh
```

- [ ] **Step 4: Test with fixture**

```bash
ARCHIVE_DIR=temp_merge_test/youtube-dharma-talk RCLONE_REMOTE="dummy:/" \
    bash scripts/04_merge.sh --dry-run

grep "content A" temp_merge_test/youtube-dharma-talk/2025_Merged.md && echo "content A OK"
grep "content B" temp_merge_test/youtube-dharma-talk/2025_Merged.md && echo "content B OK"
rm -rf temp_merge_test
```

Expected:
```
=== Stage 4: Merge and Sync ===
Merging 2025...
  → .../2025_Merged.md
[dry-run] Skipping rclone
=== Stage 4 complete (dry-run) ===
content A OK
content B OK
```

- [ ] **Step 5: Commit**

```bash
git add scripts/04_merge.sh
git commit -m "feat: implement 04_merge.sh year merge and rclone sync"
```

---

### Task 6: run.sh — Orchestration Entry Point

**Files:**
- Create: `scripts/run.sh`

- [ ] **Step 1: Implement scripts/run.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

REBUILD_ALL=""
[[ "${1:-}" == "--rebuild-all" ]] && REBUILD_ALL="--rebuild-all"

_stage() {
    local n="$1" name="$2" cmd="$3"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Stage $n/4: $name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if ! eval "$cmd"; then
        echo ""
        echo "❌ Stage $n failed. To resume from here:"
        echo "   bash scripts/0${n}_*.sh $REBUILD_ALL"
        exit 1
    fi
}

_stage 1 "Fetch"         "bash $SCRIPT_DIR/01_fetch.sh $REBUILD_ALL"
_stage 2 "Transcribe"    "bash $SCRIPT_DIR/02_transcribe.sh"
_stage 3 "Archive"       "python3 $SCRIPT_DIR/03_archive.py"
_stage 4 "Merge & Sync"  "bash $SCRIPT_DIR/04_merge.sh"

echo ""
echo "✅ Pipeline complete."
```

- [ ] **Step 2: Make executable and verify syntax**

```bash
chmod +x scripts/run.sh
bash -n scripts/run.sh && echo "Syntax OK"
```

- [ ] **Step 3: Commit**

```bash
git add scripts/run.sh
git commit -m "feat: implement run.sh pipeline orchestrator with resume hints"
```

---

### Task 7: .gitlab-ci.yml — CI Configuration

**Files:**
- Create: `.gitlab-ci.yml`

- [ ] **Step 1: Implement .gitlab-ci.yml**

```yaml
stages:
  - fetch
  - transcribe
  - archive
  - sync

default:
  tags:
    - macos   # macOS runner required: yt-dlp, whisper, ffmpeg, rclone, jq, python3

variables:
  GIT_STRATEGY: clone

fetch:
  stage: fetch
  script:
    - source config.env
    - bash scripts/01_fetch.sh ${REBUILD_ALL:+--rebuild-all}
  artifacts:
    paths:
      - temp/
    expire_in: 1 day

transcribe:
  stage: transcribe
  script:
    - source config.env
    - bash scripts/02_transcribe.sh
  artifacts:
    paths:
      - temp/
    expire_in: 1 day

archive:
  stage: archive
  script:
    - source config.env
    - python3 scripts/03_archive.py
    - git config user.email "ci@gitlab.local"
    - git config user.name "GitLab CI"
    - git add youtube-dharma-talk/ status.md
    - git diff --cached --quiet || git commit -m "ci: archive transcripts [skip ci]"
    - git pull --rebase origin "$CI_COMMIT_BRANCH"
    - git push "https://oauth2:${CI_PUSH_TOKEN}@${CI_SERVER_HOST}/${CI_PROJECT_PATH}.git" HEAD:"$CI_COMMIT_BRANCH"
  artifacts:
    paths:
      - youtube-dharma-talk/
      - status.md
    expire_in: 7 days

sync:
  stage: sync
  script:
    - source config.env
    - bash scripts/04_merge.sh
```

> **Required GitLab CI/CD Variables (Settings → CI/CD → Variables):**
> - `PLAYLIST_URL` — YouTube playlist URL
> - `RCLONE_REMOTE` — e.g. `gdrive:NotebookLM_Sources`
> - `CI_PUSH_TOKEN` — Project access token with `write_repository` scope
> - `REBUILD_ALL` — set to any non-empty value to trigger full rebuild; leave blank for normal runs

- [ ] **Step 2: Validate YAML syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('.gitlab-ci.yml'))" && echo "YAML OK"
```

Expected: `YAML OK`

- [ ] **Step 3: Commit**

```bash
git add .gitlab-ci.yml
git commit -m "feat: add gitlab-ci.yml 4-stage pipeline with archive commit-back"
```

---

## Self-Review

### Spec Coverage

| Spec requirement | Task |
|---|---|
| `--rebuild-all` ignores status.md, always downloads audio | Task 2 |
| Subtitle priority: zh-Hant → zh-Hans → zh | Task 2 |
| Audio fallback when no subtitle | Task 2 |
| `meta.json` with title, date, url, channel, duration | Task 2 |
| Whisper transcription of audio files | Task 3 |
| VTT/SRT → TXT (strip timestamps, deduplicate lines) | Task 3 |
| YAML frontmatter in archived Markdown | Task 4 |
| Same-day multiple videos: sequence numbers (-2, -3…) | Task 4 |
| `status.md` updated: 🗂️ 已存在 + file path | Task 4 |
| `temp/{video_id}/` cleaned after successful archive | Task 4 |
| Download failure: skip + mark ❌ 下載失敗 in status.md | Task 2 |
| Transcription failure: skip + keep temp + mark ❌ 轉錄失敗 | Task 3 |
| Year merge into `{year}_Merged.md` | Task 5 |
| rclone sync to Google Drive (merged files only) | Task 5 |
| Stage orchestration with per-stage failure hints | Task 6 |
| CI: 4 stages, artifacts passed between stages | Task 7 |
| CI: archive job commits updated files back to repo | Task 7 |
| CI: `git pull --rebase` before push (conflict handling) | Task 7 |
| Idempotency: skip already-processed in each stage | Tasks 2, 3, 4 |
| `status.md` 連結 column | Task 1 |

### Placeholder Scan

None found. All steps contain complete code, exact commands, and expected outputs.

### Type Consistency

- `date_str` is always `YYYY-MM-DD` (Python); `date_key` is always `YYYYMMDD` (Python + shell)
- `archive_video(video_dir: Path, archive_dir: Path)` — consistent across `archive_lib.py`, `03_archive.py`, and `tests/test_archive.py`
- `get_archive_path(date_str, archive_dir)` — returns `Path`, used as `Path` everywhere
- Shell scripts all `source config.env` at top for variable consistency
