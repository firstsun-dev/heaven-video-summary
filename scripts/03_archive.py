#!/usr/bin/env python3
import json, shutil, sys
from pathlib import Path
from common_utils import ROOT_DIR, load_config, extract_date_from_title, vtt_to_markdown, update_progress

def format_md(meta, transcript):
    return f"---\ntitle: {meta['title']}\ndate: {meta.get('date_fmt')}\nurl: {meta['url']}\nchannel: {meta['channel']}\nduration: {meta['duration']}\n---\n\n{transcript.strip()}\n"

def update_status(path, date, title, status, link=""):
    if not path.exists(): path.write_text("# 狀態報告\n| 日期 | 主題 | 狀態 |\n|:---|:---|:---|\n")
    lines = path.read_text().splitlines()
    header = [l for l in lines if l.startswith(("#", "|:", "| 日期")) or not l.strip()]
    data = [l for l in lines if l.startswith("|") and not l.startswith(("|:", "| 日期"))]
    row = f"| {date} | [{title}]({link}) | {status} |" if link else f"| {date} | {title} | {status} |"
    
    found = False
    new_data = []
    for l in data:
        if f"| {date} |" in l and f" {title} " in l:
            new_data.append(row); found = True
        else: new_data.append(l)
    if not found: new_data.append(row)
    new_data.sort(key=lambda x: x.split("|")[1].strip(), reverse=True)
    path.write_text("\n".join(header + new_data) + "\n")

def archive():
    conf = load_config()
    temp, arch = ROOT_DIR / conf.get("TEMP_DIR", "temp"), ROOT_DIR / conf.get("ARCHIVE_DIR", "youtube-dharma-talk")
    status_p = ROOT_DIR / "status.md"
    
    dirs = sorted([d for d in temp.iterdir() if d.is_dir() and not d.name.startswith(".")])
    print(f"[03_archive] Processing {len(dirs)} dirs...")

    for i, d in enumerate(dirs, 1):
        if not (d / "meta.json").exists(): continue
        meta = json.loads((d / "meta.json").read_text())
        if not (d / "transcript.txt").exists():
            update_progress(i, len(dirs), 0, "⚠️ Missing transcript", meta['title']); continue

        date_str = extract_date_from_title(meta['title'], meta['date'])
        year_dir = arch / date_str[:4]
        year_dir.mkdir(parents=True, exist_ok=True)
        
        dest = year_dir / f"{date_str}.md"
        count = 2
        while dest.exists():
            dest = year_dir / f"{date_str}-{count}.md"
            count += 1
        
        dest.write_text(format_md(meta, (d / "transcript.txt").read_text()))
        
        vtt = list(d.glob("subtitle.*"))
        if vtt:
            shutil.copy2(vtt[0], dest.parent / f"{dest.stem}{vtt[0].suffix}")
            ts_content = vtt_to_markdown(vtt[0])
            if ts_content: (dest.parent / f"{dest.stem}-timestamps.md").write_text(format_md(meta, ts_content))

        update_status(status_p, date_str.replace("-", ""), meta['title'], "🗂️ 已存在", f"./{arch.name}/{date_str[:4]}/{dest.name}")
        shutil.rmtree(d)
        update_progress(i, len(dirs), 0, "🗂️ Archived", meta['title'])
    print("\n[03_archive] Done.")

if __name__ == "__main__": archive()
