# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Does

Automates a YouTube playlist → Whisper transcript → Markdown archive → Google Drive pipeline. Four shell/Python stages run locally or via GitLab CI on a macOS runner.

## Running the Pipeline

```bash
# Full run (normal mode — skips already-archived videos)
bash scripts/run.sh

# First run / rebuild everything (ignores status.md, re-downloads all audio)
bash scripts/run.sh --rebuild-all

# Run a single stage directly
bash scripts/01_fetch.sh [--rebuild-all]
bash scripts/02_transcribe.sh
python3 scripts/03_archive.py
bash scripts/04_merge_and_sync.sh
```

## Configuration

Edit `config.env` before running. Required fields:
- `PLAYLIST_URL` — YouTube playlist URL
- `RCLONE_REMOTE` — rclone remote + path (e.g. `gdrive:NotebookLM_Sources`)

Optional fields (have defaults): `WHISPER_MODEL`, `WHISPER_LANGUAGE`, `ARCHIVE_DIR`, `TEMP_DIR`.

## Architecture

```
01_fetch.sh   → temp/{video_id}/meta.json + subtitle.*.vtt or incoming.mp3
02_transcribe → temp/{video_id}/transcript.txt
03_archive.py → youtube-dharma-talk/{year}/{YYYY-MM-DD}.md + status.md updated
04_merge      → youtube-dharma-talk/{year}_Merged.md → rclone → Google Drive
```

- **temp/** is the scratch space between stages. Each stage is idempotent — safe to re-run.
- **status.md** tracks every video (date, title, status emoji, archive link). Updated by `03_archive.py`.
- Same-day collisions produce `YYYY-MM-DD-2.md`, `-3.md`, etc.
- `--rebuild-all` forces audio download for all videos (skips subtitle attempt) and re-archives everything.

## Key Files

| File | Purpose |
|:-----|:--------|
| `scripts/03_archive.py` | Only Python file. Reads `temp/*/meta.json` + `transcript.txt`, writes Markdown, updates `status.md`. |
| `status.md` | Source of truth for what has been processed. Columns: date (YYYYMMDD), title, status emoji, link. |
| `.gitlab-ci.yml` | 4-stage CI; `archive` stage auto-commits results back to the branch. |

## Dependencies

`yt-dlp`, `whisper` (OpenAI Whisper CLI), `ffmpeg`, `python3`, `rclone`, `jq`
