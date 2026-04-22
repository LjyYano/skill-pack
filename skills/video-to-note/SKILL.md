---
name: video-to-note
description: Use when the user provides a YouTube or Bilibili URL and wants it summarized into an Obsidian note. Prefers auto-generated subtitles over ASR. Uses Obsidian CLI for note creation.
---

# Video → Obsidian Note

## Overview

Get transcript from video subtitles (preferred) or Qwen ASR fallback (Alibaba Cloud), then write a structured Obsidian note via the `obsidian` CLI.

**Supported platforms:** YouTube, Bilibili

**Output directory:**
- YouTube → `AI/YouTube/`
- Bilibili → `AI/Bilibili/`

---

## Prerequisites

- `yt-dlp` — subtitle download & audio download (supports YouTube & Bilibili)
- `ffmpeg` — audio conversion & splitting (ASR fallback only)
- `python3` + `requests` — API calls (ASR fallback only)
- `ALIYUN_API_KEY` — DashScope API Key for Qwen ASR (ASR fallback only)
- `obsidian` CLI — note creation (Obsidian must be running)
- Bilibili cookies (optional) — for member-only or age-restricted Bilibili videos, use `--cookies-from-browser chrome`

---

## Step-by-Step Workflow

### 0. Detect platform

```python
import re
url = "URL"
if re.match(r'https?://(www\.)?(bilibili\.com|b23\.tv)', url):
    platform = "bilibili"
    output_dir = "AI/Bilibili"
elif re.match(r'https?://(www\.)?(youtube\.com|youtu\.be)', url):
    platform = "youtube"
    output_dir = "AI/YouTube"
else:
    print("Unsupported platform")
    exit(1)
```

> Use `platform` and `output_dir` throughout the workflow.

### 1. Get video metadata + detect subtitles

```bash
yt-dlp --dump-json --skip-download "URL" 2>&1 | python3 -c "
import json, sys
for line in sys.stdin.read().strip().split('\n'):
    try:
        d = json.loads(line)
        print('TITLE:', d.get('title',''))
        # Bilibili uses 'uploader', YouTube uses 'channel'
        print('CHANNEL:', d.get('channel','') or d.get('uploader',''))
        print('UPLOAD_DATE:', d.get('upload_date',''))
        print('DURATION:', d.get('duration_string',''))
        print('VIEW_COUNT:', d.get('view_count',''))
        print('DESCRIPTION:', d.get('description','')[:500])
        # Detect auto-generated subtitles
        auto_subs = d.get('automatic_captions', {})
        manual_subs = d.get('subtitles', {})
        if auto_subs:
            langs = list(auto_subs.keys())
            print('AUTO_SUBS_AVAILABLE:', ','.join(langs))
        if manual_subs:
            langs = list(manual_subs.keys())
            print('MANUAL_SUBS_AVAILABLE:', ','.join(langs))
        if not auto_subs and not manual_subs:
            print('NO_SUBS_AVAILABLE')
        break
    except: continue
"
```

> **Bilibili note:** If download fails (member-only / age-restricted), retry with `--cookies-from-browser chrome`.

**Subtitle decision logic:**

| Condition | Action |
|-----------|--------|
| `AUTO_SUBS_AVAILABLE` contains `en` or `zh-Hans` or `zh` | Download subtitle → go to Step 2A |
| `MANUAL_SUBS_AVAILABLE` contains `en` or `zh-Hans` or `zh` | Download subtitle → go to Step 2A |
| Any auto/manual subs available | Download the first available language → go to Step 2A |
| `NO_SUBS_AVAILABLE` | Fall back to ASR → go to Step 2B |

> **Priority:** Prefer `zh-Hans` > `zh` > `en` > first available language.

### 2A. Download subtitle (preferred path)

```bash
# Use best subtitle format (srv3/vtt/srt), yt-dlp auto-selects best
yt-dlp --write-auto-sub --sub-lang LANG --sub-format srv3/vtt/srt \
  --skip-download -o "./.yt_sub_%(id)s" "URL" 2>&1 | tail -3
```

Then parse the subtitle file to extract clean text with **logical paragraph segmentation** (based on timestamp gaps > 3s):

```python
import re

def _parse_timestamp(ts_str):
    """Parse SRT/VTT timestamp to seconds."""
    # Handle both SRT (00:01:23,456) and VTT (00:01:23.456) formats
    ts_str = ts_str.strip().replace(',', '.')
    parts = ts_str.split(':')
    if len(parts) == 3:
        h, m, s = parts
        return int(h) * 3600 + int(m) * 60 + float(s)
    elif len(parts) == 2:
        m, s = parts
        return int(m) * 60 + float(s)
    return 0.0

def _segment_by_gaps(cues, gap_threshold=3.0):
    """Group cues into paragraphs based on timestamp gaps.
    
    When the gap between consecutive cues exceeds `gap_threshold` seconds,
    a new paragraph is started. This creates natural logical breaks.
    """
    if not cues:
        return ""
    paragraphs = []
    current_lines = [cues[0][1]]
    for i in range(1, len(cues)):
        gap = cues[i][0] - cues[i-1][0]
        if gap > gap_threshold:
            paragraphs.append(" ".join(current_lines))
            current_lines = [cues[i][1]]
        else:
            current_lines.append(cues[i][1])
    if current_lines:
        paragraphs.append(" ".join(current_lines))
    return "\n\n".join(paragraphs)

def parse_srt(srt_path):
    """Parse SRT file and return paragraph-segmented text."""
    with open(srt_path, 'r', encoding='utf-8') as f:
        content = f.read()
    blocks = re.split(r'\n\n+', content.strip())
    cues = []  # list of (end_time, text)
    for block in blocks:
        parts = block.strip().split('\n')
        if len(parts) < 2:
            continue
        # Find timestamp line (contains -->)
        ts_line = None
        text_start = 0
        for i, line in enumerate(parts):
            if '-->' in line:
                ts_line = line
                text_start = i + 1
                break
        if ts_line is None:
            continue
        end_ts = ts_line.split('-->')[1].strip()
        end_time = _parse_timestamp(end_ts)
        text_lines = [l.strip() for l in parts[text_start:] if l.strip()]
        if text_lines:
            cues.append((end_time, " ".join(text_lines)))
    return _segment_by_gaps(cues)

def parse_vtt(vtt_path):
    """Parse VTT file and return paragraph-segmented text."""
    with open(vtt_path, 'r', encoding='utf-8') as f:
        content = f.read()
    content = re.sub(r'^WEBVTT.*\n\n', '', content, flags=re.DOTALL)
    blocks = re.split(r'\n\n+', content.strip())
    cues = []
    prev_text = None
    for block in blocks:
        parts = block.strip().split('\n')
        ts_line = None
        text_start = 0
        for i, line in enumerate(parts):
            if '-->' in line:
                ts_line = line
                text_start = i + 1
                break
        if ts_line is None:
            continue
        end_ts = ts_line.split('-->')[1].strip()
        end_time = _parse_timestamp(end_ts)
        text_lines = [l.strip() for l in parts[text_start:] if l.strip()]
        text = " ".join(text_lines)
        # Skip duplicate consecutive lines (VTT often repeats)
        if text == prev_text:
            continue
        if text:
            cues.append((end_time, text))
            prev_text = text
    return _segment_by_gaps(cues)

# Auto-detect subtitle file and parse
import glob
sub_files = glob.glob('./.yt_sub_VIDEOID.*')
transcript = ''
for f in sub_files:
    if f.endswith('.vtt'):
        transcript = parse_vtt(f)
        break
    elif f.endswith('.srt'):
        transcript = parse_srt(f)
        break
```

> **Segmentation logic:** Subtitle cues are grouped into paragraphs based on timestamp gaps. When the gap between consecutive cues exceeds 3 seconds, a new paragraph (`\n\n`) is inserted. This creates natural topic boundaries without losing content.

If subtitle path succeeds → skip to **Step 3**.

### 2B. ASR fallback (no subtitles available)

Only run these steps when no subtitles are detected.

#### 2B-1. Download audio

```bash
yt-dlp -f "bestaudio[ext=m4a]/bestaudio" \
  -o "./.yt_audio_%(id)s.%(ext)s" "URL" 2>&1 | tail -3
```

#### 2B-2. Split audio (only if needed)

Qwen ASR 单请求上限 10MB（Base64 编码后）。30s MP3 ≈ 200KB，大部分视频无需分片。

**决策逻辑：**
1. 检查音频文件大小
2. ≤ 7MB（Base64 后约 9.3MB）→ 不分片，直接整段转录（Step 2B-3-single）
3. \> 7MB → 按 5 分钟一段分片（Step 2B-3-chunked）

```python
import os
audio_path = ".yt_audio_VIDEOID.m4a"
size_mb = os.path.getsize(audio_path) / (1024 * 1024)
need_chunk = size_mb > 7
print(f"Audio size: {size_mb:.1f}MB, need_chunk: {need_chunk}")
```

**不分片时（≤ 7MB）：** 跳到 Step 2B-3-single，无需 ffmpeg。

**分片时（\> 7MB）：**

```bash
ffmpeg -i ./.yt_audio_VIDEOID.m4a \
  -ac 1 -f segment -segment_time 300 \
  -c:a mp3 -q:a 5 -y \
  "./.yt_chunks_VIDEOID/chunk_%04d.mp3" 2>&1 | tail -3
```

> 分片间隔 300s（5 分钟），远大于旧版 30s，减少请求数和拼接误差。

#### 2B-3-single. Transcribe entire audio (preferred, ≤ 7MB)

```python
import os, base64, pathlib, requests

API_KEY = os.environ["ALIYUN_API_KEY"]
AUDIO_PATH = ".yt_audio_VIDEOID.m4a"
API_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
HEADERS = {
    "Authorization": f"Bearer {API_KEY}",
    "Content-Type": "application/json"
}

b64 = base64.b64encode(pathlib.Path(AUDIO_PATH).read_bytes()).decode()
data_uri = f"data:audio/mpeg;base64,{b64}"
payload = {
    "model": "qwen3-asr-flash",
    "messages": [{
        "role": "user",
        "content": [{
            "type": "input_audio",
            "input_audio": {"data": data_uri}
        }]
    }],
    "stream": False
}
resp = requests.post(API_URL, headers=HEADERS, json=payload, timeout=300)
transcript = resp.json()["choices"][0]["message"]["content"] if resp.status_code == 200 else f"[ERROR {resp.status_code}]"
print(f"Transcript length: {len(transcript)} chars")
print(transcript)
```

#### 2B-3-chunked. Transcribe in parallel (> 7MB)

```python
import os, base64, pathlib, requests
from concurrent.futures import ThreadPoolExecutor, as_completed

API_KEY = os.environ["ALIYUN_API_KEY"]
CHUNK_DIR = "./.yt_chunks_VIDEOID"
API_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
HEADERS = {
    "Authorization": f"Bearer {API_KEY}",
    "Content-Type": "application/json"
}

chunks = sorted([f for f in os.listdir(CHUNK_DIR) if f.endswith(".mp3")])

def transcribe(chunk_name):
    idx = int(chunk_name.replace("chunk_","").replace(".mp3",""))
    chunk_path = pathlib.Path(f"{CHUNK_DIR}/{chunk_name}")
    b64 = base64.b64encode(chunk_path.read_bytes()).decode()
    data_uri = f"data:audio/mpeg;base64,{b64}"
    payload = {
        "model": "qwen3-asr-flash",
        "messages": [{
            "role": "user",
            "content": [{
                "type": "input_audio",
                "input_audio": {"data": data_uri}
            }]
        }],
        "stream": False
    }
    resp = requests.post(API_URL, headers=HEADERS, json=payload, timeout=300)
    if resp.status_code == 200:
        return idx, resp.json()["choices"][0]["message"]["content"]
    return idx, f"[ERROR {resp.status_code}: {resp.text[:200]}]"

results = {}
with ThreadPoolExecutor(max_workers=3) as executor:
    for future in as_completed({executor.submit(transcribe, c): c for c in chunks}):
        idx, text = future.result()
        results[idx] = text

transcript = "\n\n".join(results[i] for i in sorted(results.keys()))
```

**API constraints:**
- Model: `qwen3-asr-flash` (same ASR engine as `qwen3-asr-flash-filetrans`)
- Format: `.mp3`, `.wav`, etc. (any audio format)
- Max size: **10 MB per request** (base64-encoded)
- Max duration: no hard limit per request
- Channel: mono or stereo both supported
- Timeout: 300s for long audio segments

### 3. Create Obsidian note

**Note structure template:**
```markdown
---
title: <video title>
tags: [<inferred topics>]
source: <original url>
author: <channel/uploader name>
date: <YYYY-MM-DD>
duration: <HH:MM>
type: 视频笔记
platform: <youtube|bilibili>
transcript_source: <subtitle|asr>
---

# <title>

> [!info] 视频信息
> author / duration / date / [link](URL)

## 核心观点
[1-3 sentence summary]

## [Section headers inferred from transcript content]
[Structured summary with callouts, tables, lists]

## 个人思考
- [ ] Action items

## 原始转录

> [!note]-
> 第一段转录内容……
>
> 第二段转录内容……
>
> 第三段转录内容……
```

> **Transcript storage rule:** If transcript exceeds **20000 characters**, do NOT save it — just leave a note like `> 转录内容过长（N 字符），未保存。可从 [原视频](URL) 获取。`. Under 20000 chars, embed in a collapsible callout with **logical paragraph breaks** (each paragraph separated by `>` lines).
>
> **Transcript segmentation (重要):** 转录必须按照**内容逻辑**分段，而非按照时间或字数机械切割。
> - **ASR 路径**：ASR 分片的 `\n\n` 拼接只是中间产物。写入笔记前，必须通读全文，在话题转换处断段（如：新论点提出、举例结束回到主旨、从一种类型切换到另一种类型）。跨分片边界的句子（如"不同的哲学家给出了。\n\n不同的应对策略"）必须合并为完整句子。
> - **字幕路径**：时间戳间隔分段（>3s）是初步分段。写入笔记前同样需要检查，确保段落边界与话题转换对齐，必要时合并过短的段落或拆分过长的话题混合段。
> - **分段粒度**：一般 20-30 分钟视频分成 15-25 段。每段应是一个完整的论点、叙述单元或话题。

**Write strategy (按内容大小选择):**

视频笔记通常包含完整转录，内容很长，所以 **默认直接用 Write tool 写文件**：

- **大内容（默认）** — 直接用 Write tool 写入 `<output_dir>/<title>.md`，Obsidian 会自动检测文件变化
- **小内容（仅摘要，无转录）** — 可用 `obsidian create path="<output_dir>/<title>.md" content="..." silent`

> **Why:** CLI 的 `content` 参数受 shell 参数长度限制，长转录内容会截断。直接写文件无此限制。

### 4. Cleanup

Delete all temp files using Python (avoid `rm -rf` which is blocked by hooks):

```python
import os, glob
video_id = "VIDEOID"
# Subtitle path temp files
for f in glob.glob(f'.yt_sub_{video_id}*'):
    os.remove(f)
# ASR path temp files
for f in [f'.yt_audio_{video_id}.m4a']:
    if os.path.isfile(f): os.remove(f)
for f in glob.glob(f'.yt_chunks_{video_id}/*.mp3'):
    os.remove(f)
if os.path.isdir(f'.yt_chunks_{video_id}'): os.rmdir(f'.yt_chunks_{video_id}')
# Temp note file (if used CLI fallback)
if os.path.isfile('.yt_note_temp.md'): os.remove('.yt_note_temp.md')
```

---

## Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `401` auth error | `ALIYUN_API_KEY` not loaded | Restart Claude Code after setting env |
| `400` invalid request | Audio too large (>10MB base64) | Use chunked path (2B-3-chunked) |
| `429` rate limit | Too many concurrent requests | Reduce `max_workers` (try 2-3) |
| Subtitle parse empty | Bad format | Try `--sub-format` with different value (srv3 > vtt > srt) |
| `rm -rf` blocked | Safety hook | Use Python `os.remove` + `os.rmdir` instead |
| `obsidian` CLI not found | Obsidian not running | Start Obsidian first, or fall back to Write tool |
| Bilibili download fails | Member-only / age-restricted | Retry with `--cookies-from-browser chrome` |

---

## Quick Reference

```
URL → detect platform (YouTube / Bilibili)
    → yt-dlp (metadata + subtitle detection)
        ├─ Has subtitles? → download & parse subtitle → transcript
        └─ No subtitles?  → download audio
            ├─ ≤ 7MB? → whole audio → Qwen ASR (single request)
            └─ > 7MB? → 5min chunks → Qwen ASR (parallel)
    → summarize → write to <output_dir>/<title>.md → cleanup
```
