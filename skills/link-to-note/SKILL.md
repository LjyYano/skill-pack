---
name: link-to-note
description: Use when the user provides a YouTube, Bilibili, Apple Podcasts, Xiaoyuzhou (小宇宙), or any yt-dlp-compatible URL and wants it summarized into a rich Obsidian note. Videos with auto-captions use the subtitle path (free, no ASR call). Audio URLs and videos without subtitles use DashScope paraformer-v2 ASR with sentence-level timestamps. Produces Summary + Takeaways + Mindmap + Chapters + Highlights + Transcript (no speaker labels). Shownotes section rendered only when the source has structured shownotes (typical for podcasts).
---

# Link → Obsidian Note

## Overview

统一的「URL → Obsidian 笔记」工作流，覆盖视频（YouTube / Bilibili）与音频（Apple Podcasts / 小宇宙 / 其他 yt-dlp 可抓取的音频链接）。替代并合并了旧的 `video-to-note` 与 `podcast-to-note`。

**Transcript pipeline — 字幕优先、ASR 兜底：**

| 输入 | 路径 | 转录方式 |
| --- | --- | --- |
| YouTube / Bilibili，有 auto/manual subs | 字幕路径 | yt-dlp 下载字幕 + 本地解析（无 ASR 调用） |
| YouTube / Bilibili，无字幕 | ASR 路径 | paraformer-v2 异步转写（带 sentence 时间戳） |
| Apple Podcasts / 小宇宙 / 其他音频 URL | ASR 路径 | 同上 |

不论哪条路径，最终都归一到 `[{begin_time_ms, text}, ...]` 段落列表，后续组织笔记逻辑完全共用。

**Output directory:**
- YouTube → `AI/YouTube/`
- Bilibili → `AI/Bilibili/`
- Apple Podcasts / 小宇宙 → `AI/Podcasts/`
- 其他 yt-dlp 音频 → `AI/Audio/`

> **不标注说话人。** 过往尝试 ASR diarization 和从 shownotes 推断都不稳定，转录一律只保留 `**[MM:SS]** 文本`。详见 `feedback_podcast_no_speaker` 记忆。

---

## Prerequisites

- `yt-dlp` — YouTube 元数据 + 字幕 / 音频下载；Apple Podcasts URL 通常会被解析到 xiaoyuzhoufm CDN m4a
- `python3` + `requests` — Bilibili REST API（yt-dlp 对 Bilibili 返回 412，不可用）+ DashScope API 调用
- `ALIYUN_API_KEY` — DashScope API key（paraformer-v2 异步转写）
- 不依赖 Obsidian CLI，直接 Write 文件即可（Obsidian 会自动索引）

> **ffmpeg 不再需要。** paraformer-v2 处理整段音频，不需要本地分片。旧版 `qwen3-asr-flash` + chunking 的路径已淘汰。

---

## Workflow

### 0. 平台检测 + 路由

```python
import re, hashlib

url = "URL"
if re.search(r'(youtube\.com|youtu\.be)', url):
    platform, has_video, output_dir = "youtube", True, "AI/YouTube"
elif re.search(r'(bilibili\.com|b23\.tv)', url):
    platform, has_video, output_dir = "bilibili", True, "AI/Bilibili"
elif re.search(r'podcasts\.apple\.com', url):
    platform, has_video, output_dir = "apple-podcasts", False, "AI/Podcasts"
elif re.search(r'xiaoyuzhoufm\.com', url):
    platform, has_video, output_dir = "xiaoyuzhou", False, "AI/Podcasts"
else:
    platform, has_video, output_dir = "generic", False, "AI/Audio"

slug = hashlib.md5(url.encode()).hexdigest()[:10]  # short slug for temp files
```

### 1. 元数据 + 字幕可用性

> **⚠️ Bilibili 不走 yt-dlp。** yt-dlp 对 Bilibili 返回 `HTTP Error 412: Precondition Failed`（截至 2026.03.17 版本，加 cookies / headers / extractor-args 均无效），必须用 Bilibili REST API。YouTube 和其他平台仍用 yt-dlp。

#### 1A. Bilibili 路径（REST API 直取）

```python
import re, requests, json
from datetime import datetime

url = "URL"
bvid_match = re.search(r'(BV[a-zA-Z0-9]+)', url)
bvid = bvid_match.group(1)
headers = {
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    'Referer': 'https://www.bilibili.com'
}

# 1) 元数据
info = requests.get(f'https://api.bilibili.com/x/web-interface/view?bvid={bvid}',
                     headers=headers, timeout=15).json()['data']
TITLE = info['title']
CHANNEL = info['owner']['name']
UPLOAD_DATE = datetime.fromtimestamp(info['pubdate']).strftime('%Y%m%d')
DURATION_SEC = info['duration']
DURATION = f"{DURATION_SEC // 60}:{DURATION_SEC % 60:02d}"
DESCRIPTION = info.get('desc', '')
CID = info['cid']

# 2) 字幕检测
player = requests.get(f'https://api.bilibili.com/x/player/v2?bvid={bvid}&cid={CID}',
                       headers=headers, timeout=15).json()
subtitles = player.get('data', {}).get('subtitle', {}).get('subtitles', [])
# subtitles 非空 → 有字幕（B站字幕通常只有 CC 字幕）
# subtitles 为空 → NO_SUBS，走 ASR
```

**Bilibili 音频下载（Step 2B 需要时）：**

```python
# 获取音频流 URL
playurl = requests.get(
    f'https://api.bilibili.com/x/player/playurl?bvid={bvid}&cid={CID}&qn=64&fnval=16',
    headers=headers, timeout=15
).json()['data']['dash']['audio']
best_audio = max(playurl, key=lambda x: x.get('bandwidth', 0))
audio_url = best_audio['baseUrl']

# 下载 m4s（实际 m4a 兼容，可直接送 paraformer-v2）
audio_resp = requests.get(audio_url, headers=headers, timeout=120, stream=True)
with open(f'./.ltn_audio_{slug}.m4a', 'wb') as f:
    for chunk in audio_resp.iter_content(chunk_size=8192):
        f.write(chunk)
```

**Bilibili 字幕下载（有字幕时）：** 字幕 URL 在 `subtitles[].subtitle_url` 中，需要补 `https:` 前缀，下载后为 JSON 格式（`body` 数组，每项含 `from`, `to`, `content`），直接解析即可，无需 SRT/VTT 解析器。

#### 1B. YouTube / 其他平台路径（yt-dlp）

```bash
yt-dlp --dump-json --skip-download "URL" 2>&1 | python3 -c "
import json, sys
for line in sys.stdin.read().strip().split('\n'):
    try:
        d = json.loads(line)
        print('TITLE:', d.get('title') or d.get('episode',''))
        print('CHANNEL:', d.get('channel','') or d.get('uploader','') or d.get('series',''))
        print('UPLOAD_DATE:', d.get('upload_date',''))
        print('DURATION:', d.get('duration_string',''))
        print('DURATION_SEC:', d.get('duration',''))
        print('VIEW_COUNT:', d.get('view_count',''))
        print('DESCRIPTION:', d.get('description','') or '')
        auto_subs = d.get('automatic_captions', {})
        manual_subs = d.get('subtitles', {})
        if auto_subs:   print('AUTO_SUBS:', ','.join(auto_subs.keys()))
        if manual_subs: print('MANUAL_SUBS:', ','.join(manual_subs.keys()))
        if not auto_subs and not manual_subs and auto_subs is not None:
            print('NO_SUBS')
        break
    except: continue
"
```

**路径选择：**

| 条件 | 动作 |
| --- | --- |
| `has_video = True` 且有 auto/manual subs | → Step 2A 字幕路径 |
| `has_video = True` 且 `NO_SUBS` | → Step 2B ASR 路径 |
| `has_video = False`（音频链接） | → Step 2B ASR 路径 |

字幕语言优先级：`zh-Hans` > `zh` > `en` > 第一个可用。

### 2A. 字幕路径（仅视频）

```bash
yt-dlp --write-auto-sub --sub-lang LANG --sub-format srv3/vtt/srt \
  --skip-download -o "./.ltn_sub_SLUG" "URL" 2>&1 | tail -3
```

解析 SRT/VTT，返回段落级时间戳列表（按 cue 间隔 > 3s 断段）：

```python
import re, glob

def _parse_ts(s):
    s = s.strip().replace(',', '.')
    parts = s.split(':')
    if len(parts) == 3:
        h, m, sec = parts
        return int(h)*3600 + int(m)*60 + float(sec)
    if len(parts) == 2:
        m, sec = parts
        return int(m)*60 + float(sec)
    return 0.0

def _segment(cues, gap_threshold=3.0):
    """cues: list of (begin_sec, end_sec, text) → [{begin_time_ms, text}]."""
    if not cues:
        return []
    paras, buf = [], [cues[0][2]]
    cur_begin = cues[0][0]
    for i in range(1, len(cues)):
        gap = cues[i][0] - cues[i-1][1]
        if gap > gap_threshold:
            paras.append({"begin_time_ms": int(cur_begin*1000), "text": " ".join(buf)})
            buf = [cues[i][2]]
            cur_begin = cues[i][0]
        else:
            buf.append(cues[i][2])
    if buf:
        paras.append({"begin_time_ms": int(cur_begin*1000), "text": " ".join(buf)})
    return paras

def parse_sub(path):
    with open(path, encoding='utf-8') as f:
        content = f.read()
    content = re.sub(r'^WEBVTT.*?\n\n', '', content, flags=re.DOTALL)
    blocks = re.split(r'\n\n+', content.strip())
    cues, prev_text = [], None
    for b in blocks:
        lines = b.strip().split('\n')
        ts_line, text_start = None, 0
        for i, line in enumerate(lines):
            if '-->' in line:
                ts_line, text_start = line, i + 1
                break
        if ts_line is None:
            continue
        begin_s, end_s = [_parse_ts(x) for x in ts_line.split('-->')[:2]]
        text_lines = [l.strip() for l in lines[text_start:] if l.strip()]
        text = " ".join(text_lines)
        if not text or text == prev_text:  # VTT 常见重复行
            continue
        cues.append((begin_s, end_s, text))
        prev_text = text
    return _segment(cues)

sub_files = sorted(glob.glob('./.ltn_sub_SLUG.*'))
paragraphs = parse_sub(sub_files[0]) if sub_files else []
```

字幕路径完成 → 跳到 **Step 3**。

### 2B. ASR 路径（paraformer-v2 异步转写）

**下载音频：**

> **Bilibili 不走 yt-dlp。** Bilibili 音频已在 Step 1A 中通过 REST API 下载到 `./.ltn_audio_SLUG.m4a`，跳过此步。以下 yt-dlp 命令仅用于 YouTube / 其他平台。

```bash
yt-dlp -f "bestaudio[ext=m4a]/bestaudio" \
  -o "./.ltn_audio_SLUG.%(ext)s" "URL" 2>&1 | tail -3
```

**上传 + 提交转写任务：**

> ⚠️ **不要直接 POST 到 `/api/v1/uploads`** — 那个 endpoint 只接受 `GET ?action=getPolicy`，直接 POST 会返回 `405 BadRequest.RequestMethodNotAllowed`。必须先 GET 拿 OSS 临时凭证 → multipart POST 到 OSS → 用 `oss://` 引用。
>
> 提交转写任务时必须同时带 `X-DashScope-Async: enable` 和 `X-DashScope-OssResourceResolve: enable` 两个头，否则 `oss://` URL 不会被解析。

```python
import os, json, pathlib, requests, time, uuid, glob

API_KEY = os.environ["ALIYUN_API_KEY"]
AUDIO_FILE = glob.glob("./.ltn_audio_SLUG.*")[0]
HEADERS = {"Authorization": f"Bearer {API_KEY}"}
POLICY_URL = "https://dashscope.aliyuncs.com/api/v1/uploads"
TRANSCRIBE_URL = "https://dashscope.aliyuncs.com/api/v1/services/audio/asr/transcription"
TASK_URL_PREFIX = "https://dashscope.aliyuncs.com/api/v1/tasks/"

# 1) GET upload policy
pol = requests.get(POLICY_URL, headers=HEADERS,
    params={"action": "getPolicy", "model": "paraformer-v2"}, timeout=30
).json()["data"]

# 2) multipart POST 到 OSS
ext = pathlib.Path(AUDIO_FILE).suffix.lstrip('.') or 'm4a'
key = f"{pol['upload_dir']}/{uuid.uuid4().hex}.{ext}"
with open(AUDIO_FILE, "rb") as f:
    oss_resp = requests.post(pol["upload_host"],
        data={
            "key": key,
            "policy": pol["policy"],
            "OSSAccessKeyId": pol["oss_access_key_id"],
            "signature": pol["signature"],
            "x-oss-object-acl": pol["x_oss_object_acl"],
            "x-oss-forbid-overwrite": pol["x_oss_forbid_overwrite"],
            "success_action_status": "200",
        },
        files={"file": ("audio." + ext, f, "audio/mp4" if ext == "m4a" else "application/octet-stream")},
        timeout=600,
    )
assert oss_resp.status_code in (200, 204), f"OSS upload failed: {oss_resp.status_code} {oss_resp.text[:200]}"
file_url = f"oss://{key}"

# 3) 提交转写任务
trans = requests.post(TRANSCRIBE_URL,
    headers={**HEADERS, "Content-Type": "application/json",
             "X-DashScope-Async": "enable",
             "X-DashScope-OssResourceResolve": "enable"},
    json={
        "model": "paraformer-v2",
        "input": {"file_urls": [file_url]},
        "parameters": {"sentence_timestamps": True, "language_hints": ["zh", "en"]},
    },
    timeout=60,
).json()
task_id = trans["output"]["task_id"]

# 4) 轮询（每 3s 一次；长音频可调大次数）
for poll in range(200):
    time.sleep(3)
    task = requests.get(f"{TASK_URL_PREFIX}{task_id}", headers=HEADERS, timeout=30).json()
    status = task["output"]["task_status"]
    if poll % 5 == 0:
        print(f"Poll {poll}: {status}")
    if status == "SUCCEEDED":
        result_url = task["output"]["results"][0]["transcription_url"]
        result = requests.get(result_url, timeout=60).json()
        # result["transcripts"][0]["sentences"]:
        # [{"sentence_id":1,"begin_time":0,"end_time":2840,"text":"..."}, ...]
        sentences = result["transcripts"][0]["sentences"]
        pathlib.Path(".ltn_asr_SLUG.json").write_text(json.dumps(result, ensure_ascii=False, indent=2))
        break
    elif status in ("FAILED", "CANCELED"):
        raise RuntimeError(f"ASR {status}: {json.dumps(task, ensure_ascii=False)[:500]}")
```

**合并 sentence 为话题段落**（paraformer-v2 的 `sentences` 粒度偏短，合并成长段便于阅读）：

```python
def merge_sentences(sentences, gap_threshold_ms=1500, max_chars=400):
    """合并短句为段落：遇到 sentence gap > 1.5s 或当前段 > 400 字就断段。"""
    paras, buf, cur_begin, cur_end = [], [], None, None
    for s in sentences:
        if cur_begin is None:
            cur_begin, cur_end = s["begin_time"], s["end_time"]
            buf.append(s["text"])
            continue
        gap = s["begin_time"] - cur_end
        cur_len = sum(len(x) for x in buf)
        if gap > gap_threshold_ms or cur_len > max_chars:
            paras.append({"begin_time_ms": cur_begin, "text": "".join(buf)})
            buf, cur_begin = [s["text"]], s["begin_time"]
        else:
            buf.append(s["text"])
        cur_end = s["end_time"]
    if buf:
        paras.append({"begin_time_ms": cur_begin, "text": "".join(buf)})
    return paras

paragraphs = merge_sentences(sentences)
```

> **为什么用 paraformer-v2 而不是 qwen3-asr-flash：** `qwen3-asr-flash`（chat completions API）不返回时间戳，且 ≤10MB 要分片。`paraformer-v2`（异步转写 API）支持 `sentence_timestamps`，一次处理完整音频，返回每句真实 begin/end（毫秒）。

> **隐私与保留策略：** 上传到 DashScope 托管 OSS（private bucket），`oss://` 对外无法访问；文件本体 **48 小时后自动清理**，上传凭证 ~1 小时后失效。机密音频请改用本地 FunASR / Whisper。

### 3. 组织笔记

拿到 `paragraphs = [{begin_time_ms, text}, ...]` 后：
- 提取 **chapters**（3–8 行逻辑分段，章节时间取对应段的 begin_time_ms）
- 提取 **highlights**（3–8 条金句，时间锚定到对应段）
- 生成 **思维导图**（markmap 代码块，覆盖所有要点不遗漏）
- 组装 **完整转录**（每段前加 `**[MM:SS]**`，段间空行）

**Template:**

```markdown
---
title: <episode/video title>
tags:
  - <视频笔记 | 播客笔记>
  - <topic tags>
source: <original url>
author: <channel/series/uploader>
date: <YYYY-MM-DD from upload_date>
duration: "HH:MM" or "MM:SS"
type: <视频笔记 | 播客笔记>
platform: <youtube|bilibili|apple-podcasts|xiaoyuzhou|generic>
transcript_source: <subtitle|asr>
markmap:
  initialExpandLevel: 3
---

# <title>

> [!info] <视频信息|播客信息>
> <节目/频道名> · 时长 <duration> · 发布 <date> · [原始链接](<url>)
>
> <1–2 句话简介，基于 description 字段>

## Shownotes  <!-- 仅当 description 中有结构化 shownotes 时渲染；视频类通常省略 -->

> [!info]- 节目 Shownotes
> **主播：** <host names>
>
> **延伸资料**
> - [<reference title>](<url>)
>
> **后期制作：** <name> · **声音设计：** <name>
>
> **收听平台：** <小宇宙、苹果播客、Spotify、…>

## 摘要

<一段 3–5 句的整体摘要。>

> [!summary] Takeaways
> - 要点 1
> - 要点 2
> - 要点 3
> - 要点 4
> - 要点 5（5–8 条为宜）

## 思维导图

```markmap
# <核心主题>
## <章节 1>
### <子节点>
#### <细节>
## <章节 2>
### <子节点>
## <章节 3>
### <子节点>
```

## 章节导读

| 时间 | 章节 | 概述 |
| --- | --- | --- |
| 00:00 | <标题> | <一句话> |
| MM:SS | <标题> | <一句话> |

## 金句 Highlights

> [!quote] ~ MM:SS
> <金句原文>

> [!quote] ~ MM:SS
> <金句原文>

<3–8 条>

## 详细论点

### <论点 1 标题>

<展开，可以用 callout / 表格 / 列表。>

### <论点 2 标题>

...

## 个人思考

- [ ] <行动项或延伸思考>
- [ ] <延伸阅读建议>

## 完整转录

> [!note]- 完整转录
> **[00:00]** <第一段文本（合并若干连续句子，自然段）>
>
> **[00:20]** <下一段，按话题自然断段>
>
> **[01:00]** <又一段>
>
> ...
```

**Composition rules:**

- **Shownotes** 节可选：`has_video = False` 且 description 中能提取出结构化信息（主播 / 延伸资料 / 收听平台等）才渲染；视频平台通常省略此节。
- **frontmatter**：`type` 和第一个 `tag` 根据 `has_video` 设为「视频笔记」或「播客笔记」；`transcript_source` 设为 `subtitle` 或 `asr`。
- **思维导图** 用 `markmap` 代码块（不是 Mermaid），用 markdown 标题层级表示节点层级。根 `#` 为核心主题，一级 `##` 为 3–8 个章节，二级/三级为细节。要覆盖视频/播客中每个要点不遗漏。
- **initialExpandLevel** 在 frontmatter 里设为 `3`。
- **时间戳来源**：段落 `begin_time_ms` 毫秒转 `MM:SS`，不要根据语速估算。章节时间 / 金句时间均锚定到对应段的 begin_time_ms。
- **金句** 3–8 条，选观点最凝练、最有传播力的句子，尽量保留原文措辞。
- **章节导读** 3–8 行。
- **转录格式**：
  - callout 标题只用「完整转录」，不加模型名 / 段时长 / 括号。
  - 每段前加 `**[MM:SS]** `，段间用 `>` 空行 `>` 隔开。
  - **不加说话人标签**。多人对话播客也不猜、不标。
  - **按话题自然断段**。ASR 路径的 sentence 已在 Step 2B 合并；字幕路径的 cue 已按 >3s 间隔分段。写入前仍可检查是否有跨段语句需要合并或过长段需要拆分。
- **字符上限**：转录 ≤ 20000 字符直接嵌入折叠 callout；> 20000 字符写 `> 转录过长（N 字符），未保存。从 [原链接](URL) 回听。`

### 4. 清理临时文件

```python
import os, glob
slug = "SLUG"
for pat in [f'.ltn_sub_{slug}*', f'.ltn_audio_{slug}*', f'.ltn_asr_{slug}*']:
    for f in glob.glob(pat):
        os.remove(f)
```

---

## Common Errors

| Error | Cause | Fix |
| --- | --- | --- |
| `401` | `ALIYUN_API_KEY` not loaded | Restart Claude Code after setting env |
| `405 BadRequest.RequestMethodNotAllowed` on `/api/v1/uploads` | 直接 POST 到 uploads endpoint | 按 Step 2B 流程：先 `GET ?action=getPolicy`，再 multipart POST 到 `upload_host`，最后用 `oss://` 引用 |
| Submit 200 但 task FAILED with `InvalidFile` | 缺 `X-DashScope-OssResourceResolve: enable` 头 | 补上请求头 |
| Upload fails | 文件过大或格式不支持 | 检查文件（<500MB）和格式（m4a / mp3 / wav） |
| Task FAILED | 音频质量差或语言不支持 | 加 `language_hints`；或本地预处理 |
| Task 轮询超时 | 长音频处理慢 | 增大 poll 次数（200 次 ~ 10 分钟） |
| Subtitle parse 空 | 字幕格式异常 | 换 `--sub-format`（srv3 > vtt > srt） |
| Bilibili yt-dlp 返回 `HTTP Error 412` | Bilibili 反爬策略，yt-dlp extractor 失效 | **不用 yt-dlp**，改用 Bilibili REST API（见 Step 1A）：`/x/web-interface/view` 取元数据，`/x/player/playurl` 取音频流 |
| 长中文文件名在 shell 中报错 | 临时文件命名 | 所有临时文件用 `slug`（MD5 前 10 位），只有最终 `.md` 用真实标题 |
| `rm -rf` 被 hook 拦截 | 安全 | 用 Python `os.remove` |

---

## Quick Reference

```
URL → platform detect (YouTube / Bilibili / Apple Podcasts / 小宇宙 / generic)
    → metadata + subtitle check:
        ├─ Bilibili  → REST API（/x/web-interface/view + /x/player/v2）❌ 不用 yt-dlp（412）
        └─ YouTube等 → yt-dlp --dump-json
    → transcript pipeline:
        ├─ 视频 + 有字幕  → yt-dlp --write-auto-sub（YouTube）/ REST API subtitle（Bilibili）→ parse → [{begin_time_ms, text}]
        └─ 视频无字幕 或 音频 → yt-dlp audio（YouTube）/ REST API audio（Bilibili）→ paraformer-v2 async → merge_sentences → [{begin_time_ms, text}]
    → compose note (shownotes[optional] + summary + takeaways + mindmap
                    + chapters + highlights + details + thoughts + transcript)
    → Write AI/{YouTube|Bilibili|Podcasts|Audio}/<title>.md
    → cleanup temp files
```

---

## When Not to Use

- URL 是普通文章 / 博客 → 用 `article-to-note`
- URL 是纯文本 PDF / 网页文档 → 用 `defuddle` + 手动整理
- 需要 HTML 可视化播客页 → 先用此 skill 生成 `.md`，再调用 `podcast-to-html`
