#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import json
import re
import subprocess
import time
import sys
from pathlib import Path

try:
    from dotenv import load_dotenv
except ImportError:
    print("錯誤：'python-dotenv' 套件未安裝。", file=sys.stderr)
    print("請執行 'pip install python-dotenv' 來安裝它。", file=sys.stderr)
    sys.exit(1)

try:
    from tqdm import tqdm
except ImportError:
    print("錯誤：'tqdm' 套件未安裝。", file=sys.stderr)
    print("請執行 'pip install tqdm' 來安裝它。", file=sys.stderr)
    sys.exit(1)

# 載入 .env 檔案中的環境變數
load_dotenv()

# --- 設定 ---
# 從環境變數讀取路徑，如果未設定則使用原本的硬編碼路徑作為預設值
DOWNLOADS_DIR = os.getenv('DOWNLOADS_DIR',
                          '/Users/claudia.fang/Code/heaven_vedio/downloads')
SUMMARY_FILE = os.getenv('SUMMARY_FILE',
                         '/Users/claudia.fang/Code/heaven_vedio/影片重點摘要.md')
STATUS_FILE = 'status.md'
PROMPT_TEMPLATE_FILE = 'prompt_template.txt'

# Gemini CLI 的提示模板。從 .env 讀取，如果未設定則使用內建的模板。
DEFAULT_PROMPT_TEMPLATE = """請根據以下影片字幕內容，為這部佛學講座影片寫一份重點摘要。
只需要給我結果，不需要給多餘的回應詞。
摘要請遵循以下格式，並使用繁體中文，內容要精簡扼要，符合檔案中已有的風格：

**核心思想：**
[此處填寫影片的核心思想摘要]

**公案或經典原文：**
[此處填寫影片中提到的公案原文或經典原文]

**關鍵教義與比喻：**
*   [項目符號] [此處填寫第一個關鍵教義或比喻]
*   [項目符號] [此處填寫第二個關鍵教義或比喻]
*   ...

**實用建議：**
1.  [編號列表] [此處填寫第一點實用建議]
2.  [編號列表] [此處填寫第二點實用建議]
3.  ...

**其他重要觀點：**


字幕內容如下：
\"\"\"
{subtitle_text}
\"\"\"
"""

def load_prompt_template() -> str:
    """
    載入提示模板，優先順序如下：
    1. 從專案根目錄的 prompt_template.txt 檔案
    2. 使用腳本內建的 DEFAULT_PROMPT_TEMPLATE 作為備用
    """
    try:
        # 嘗試讀取檔案
        if (prompt_file := Path(PROMPT_TEMPLATE_FILE)).is_file():
            return prompt_file.read_text(encoding='utf-8')
    except IOError as e:
        print(f"警告：讀取提示模板檔案 '{PROMPT_TEMPLATE_FILE}' 失敗: {e}", file=sys.stderr)

    return DEFAULT_PROMPT_TEMPLATE

PROMPT_TEMPLATE = load_prompt_template()


def get_processed_video_dates():
    """讀取摘要檔案，返回已處理影片的日期集合 (YYYYMMDD)"""
    processed = set()
    summary_path = Path(SUMMARY_FILE)
    if not summary_path.is_file():
        # 如果檔案不存在，先建立它並寫入標題
        summary_path.touch()
        with open(summary_path, 'w', encoding='utf-8') as f:
            f.write("# 影片重點摘要\n")
        return processed

    with open(summary_path, 'r', encoding='utf-8') as f:
        content = f.read()
        # 從 Markdown 標題中提取日期 (e.g., ｜20231105)
        found_dates = re.findall(r'｜(\d{8})', content)
        processed.update(found_dates)
    return processed


def get_current_entry_count():
    """計算目前摘要檔案中的條目數量"""
    try:
        with open(SUMMARY_FILE, 'r', encoding='utf-8') as f:
            content = f.read()
            # 計算 H2 標題 (##) 的數量
            return len(re.findall(r'^## ', content, re.MULTILINE))
    except FileNotFoundError:
        return 0


def clean_vtt(vtt_content: str) -> str:
    """清理 VTT 字幕內容，只保留純文字"""
    lines = vtt_content.splitlines()
    text_lines = []
    for line in lines:
        # 忽略時間戳、空行、純數字行和 VTT 特有標頭
        if '-->' in line or not line.strip() or line.strip().isdigit(
        ) or 'WEBVTT' in line or 'Kind:' in line or 'Language:' in line:
            continue
        # 移除 VTT 標籤，例如 <v> 或 <c>
        cleaned_line = re.sub(r'<[^>]+>', '', line)
        text_lines.append(cleaned_line.strip())
    return ' '.join(text_lines)


def summarize_with_gemini(text: str) -> (str, bool):
    """使用 Gemini CLI 進行摘要，並在失敗時自動切換模型重試。返回 (摘要內容, 是否成功)"""
    prompt = PROMPT_TEMPLATE.format(subtitle_text=text)

    # 定義要依序嘗試的模型列表。
    # (模型參數, 模型名稱) - 模型參數為 None 代表使用 gemini-cli 的預設模型。
    models_to_try = [
        (None, "預設模型 (gemini-1.5-pro)"),
        ('gemini-2.5-flash', "備用模型 (gemini-2.5-flash)")
    ]

    initial_delay = 5  # seconds
    last_error = ""

    for i, (model, model_name) in enumerate(models_to_try):
        # 動態建立指令，更清晰
        command = ['gemini']
        if model:
            command.extend(['-m', model])
        command.extend(['-p', prompt])

        tqdm.write(f"正在使用 {model_name} 進行摘要 (嘗試 {i + 1}/{len(models_to_try)})...")

        try:
            result = subprocess.run(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                encoding='utf-8',
                check=True)
            summary = result.stdout.strip()
            if summary.startswith("Loaded cached credentials."):
                summary = summary.replace("Loaded cached credentials.", "",
                                          1).strip()
            summary = re.sub(r'\[此處填寫.*?\]', '', summary)
            return summary, True
        except FileNotFoundError:
            return "錯誤：找不到 Gemini CLI。請確保它已安裝並在您的 PATH 中。", False
        except (subprocess.CalledProcessError, Exception) as e:
            error_details = e.stderr.strip() if isinstance(
                e, subprocess.CalledProcessError) else str(e)
            last_error = f"使用 {model_name} 失敗: {error_details}"
            tqdm.write(f"警告: {last_error}")

            # 檢查是否還有下一個模型可以嘗試
            if i < len(models_to_try) - 1:
                next_model_name = models_to_try[i + 1][1]
                # 第一次失敗 (i=0) 時，立即嘗試下一個模型
                if i == 0:
                    tqdm.write(f"立即嘗試下一個模型 ({next_model_name})...")
                else:
                    # 後續失敗則等待一段時間再重試
                    delay = initial_delay * (2**(i - 1))
                    tqdm.write(f"將在 {delay} 秒後嘗試下一個模型 ({next_model_name})...")
                    time.sleep(delay)

    final_error_message = f"錯誤：所有模型均摘要失敗。\n最後錯誤: {last_error}"
    tqdm.write("已達最大重試次數，放棄處理此影片。")
    return final_error_message, False


def write_status_report(processing_log: list):
    """
    將本次執行的處理狀態寫入 status.md 檔案。
    """
    if not processing_log:
        print("本次執行沒有處理任何新檔案，無需更新狀態報告。")
        return

    # 根據日期排序日誌
    sorted_log = sorted(processing_log, key=lambda x: x['date'])

    status_icons = {
        '已存在': '🗂️',
        '已總結': '✨',
        '無字幕': '🔇',
        '其他問題': '❌',
        'AI處理失敗': '🤖'
    }

    try:
        with open(STATUS_FILE, 'w', encoding='utf-8') as f:
            f.write("# 影片處理狀態報告\n\n")
            f.write("此報告總結了最近一次執行 `summarize.py` 腳本時處理的影片狀態。\n\n")
            f.write("| 日期       | 主題                               | 處理狀態   |\n")
            f.write("|:-----------|:-----------------------------------|:-----------|\n")
            for entry in sorted_log:
                title = entry['title'][:30]
                f.write(f"| {entry['date']} | {title:<30} | {entry['status']}     |\n")
        print(f"狀態報告已成功寫入 '{STATUS_FILE}'")
    except IOError as e:
        print(f"錯誤：寫入狀態報告 '{STATUS_FILE}' 失敗: {e}", file=sys.stderr)


def main():
    """主執行函數"""
    # 啟動時檢查 DOWNLOADS_DIR 是否存在，提供更友善的錯誤提示
    if not Path(DOWNLOADS_DIR).is_dir():
        print(f"錯誤：設定的下載目錄 '{DOWNLOADS_DIR}' 不存在或不是一個目錄。", file=sys.stderr)
        print("請檢查您的 .env 檔案或環境變數設定是否正確。", file=sys.stderr)
        sys.exit(1)

    processed_dates = get_processed_video_dates()
    print(f"已處理的影片日期: {processed_dates or '無'}")

    downloads_path = Path(DOWNLOADS_DIR)
    files_to_process = []
    processing_log = []

    # 依檔名排序，確保按時間順序處理
    for filepath in sorted(downloads_path.glob('*.info.json')):
        # .stem 對於 'name.info.json' 這類檔名會回傳 'name.info'，是錯誤的。
        # 我們需要手動移除 '.info.json' 來取得正確的基礎檔名。
        filename_stem = filepath.name.replace('.info.json', '')

        # 從檔名解析日期和標題 (格式: YYYYMMDD_標題)
        match = re.match(r'(\d{8})_(.+)', filename_stem)
        if not match:
            # 忽略不符合格式的檔案，例如播放清單本身的 info.json
            if '天界之舟' not in filepath.name:
                print(f"警告：檔名格式不符，跳過檔案: {filepath.name}")
            continue

        video_date = match.group(1)
        clean_title = match.group(2).strip()

        if video_date in processed_dates:
            # 如果影片已處理過，直接記錄狀態並跳過
            processing_log.append({'date': video_date, 'title': clean_title, 'status': '已存在'})
            continue

        # 準備處理新的影片
        video_url = None
        try:
            with open(filepath, 'r', encoding='utf-8') as f_json:
                info_data = json.load(f_json)
                video_url = info_data.get('webpage_url')
        except (IOError, json.JSONDecodeError) as e:
            print(f"警告：讀取或解析 info.json 檔案失敗 '{filepath.name}': {e}")

        video_data = {'video_date': video_date, 'clean_title': clean_title, 'info_filepath': filepath, 'video_url': video_url}
        files_to_process.append(video_data)

    if not files_to_process:
        print("沒有新的影片需要處理。")
        write_status_report(processing_log)
        return  # Exit after writing the status report

    current_entries = get_current_entry_count()

    with open(SUMMARY_FILE, 'a', encoding='utf-8') as f_out:
        # 使用 tqdm 顯示進度條
        progress_bar = tqdm(enumerate(files_to_process),
                            total=len(files_to_process),
                            desc="摘要進度",
                            unit="部")
        for i, data in progress_bar:
            clean_title = data.get('clean_title')
            video_date = data.get('video_date')
            info_filepath = data.get('info_filepath')
            video_url = data.get('video_url')

            # 更新進度條的描述，顯示目前正在處理的影片
            # 更新進度條的後綴，顯示目前正在處理的主題，讓主描述保持乾淨
            progress_bar.set_postfix_str(f"當前主題: {clean_title[:30]}...")
            # 從 info.json 路徑推斷 VTT 字幕檔的路徑
            # e.g., '20250316_... .info.json' -> '20250316_... .zh-TW.vtt'
            base_name = info_filepath.name.replace('.info.json', '')
            vtt_filename = f"{base_name}.zh-TW.vtt"
            vtt_filepath = info_filepath.with_name(vtt_filename)

            if not vtt_filepath.is_file():
                tqdm.write(f"警告：找不到對應的本地字幕檔 '{vtt_filepath.name}'。跳過。")
                processing_log.append({
                    'date': video_date, 'title': clean_title, 'status': '無字幕'
                })
                continue

            try:
                vtt_content = vtt_filepath.read_text(encoding='utf-8')
                subtitle_text = clean_vtt(vtt_content)
            except IOError as e:
                tqdm.write(f"錯誤：讀取字幕檔失敗 '{vtt_filepath.name}': {e}")
                processing_log.append({
                    'date': video_date, 'title': clean_title, 'status': '其他問題'
                })
                continue

            if not subtitle_text:
                tqdm.write(f"警告：'{clean_title}' 的字幕內容為空。跳過。")
                processing_log.append({
                    'date': video_date, 'title': clean_title, 'status': '無字幕'
                })
                continue

            summary, success = summarize_with_gemini(subtitle_text)

            if not success:
                tqdm.write(summary)  # 輸出錯誤訊息
                processing_log.append({
                    'date': video_date, 'title': clean_title, 'status': 'AI處理失敗'
                })
                continue

            entry_index = current_entries + i + 1

            markdown_entry = f"\n## {entry_index}. {clean_title}｜{video_date}\n\n"
            if video_url:
                markdown_entry += f"[影片連結]({video_url})\n\n"
            markdown_entry += f"{summary}\n\n"

            f_out.write(markdown_entry)
            # 強制將緩衝區的內容寫入磁碟，確保即時更新
            f_out.flush()
            processing_log.append({
                'date': video_date, 'title': clean_title, 'status': '已總結'
            })

    print(f"\n處理完成！共處理 {len(files_to_process)} 個新檔案。")
    write_status_report(processing_log)


if __name__ == '__main__':
    main()
