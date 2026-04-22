---
name: link-to-note
description: Use when the user provides a URL — podcast (Apple Podcasts / Xiaoyuzhou), video (YouTube / Bilibili), or article (any web page) — and wants a structured Obsidian note. Auto-detects content type, fetches transcript/content, and produces per-type notes (rich format for podcasts, concise format for video/article).
---

# Link → Obsidian Note

## Overview

Paste any URL → auto-detect type → fetch content → compose an Obsidian note per-type format (rich for podcast, concise for video/article).

**Supported inputs:**

| Type    | Examples                                       | Output dir       |
|---------|------------------------------------------------|------------------|
| podcast | Apple Podcasts, Xiaoyuzhou, Spotify, etc.      | `AI/Podcasts/`   |
| video   | YouTube (`youtube.com`, `youtu.be`)            | `AI/YouTube/`    |
| video   | Bilibili (`bilibili.com`, `b23.tv`)            | `AI/Bilibili/`   |
| article | any web page                                   | `AI/Articles/`   |

**Note formats by type:** Podcast uses a rich format (摘要 + Takeaways + 思维导图 + 章节导读 + 金句 + 详细论点 + 完整转录)；Video 和 Article 使用简洁格式 (核心观点 + 结构化 sections + 转录/原文摘录)。Frontmatter 按 `type` / `platform` 区分。

---

## Prerequisites

| 工具 | 用途 |
|------|------|
| `yt-dlp`           | podcast / video 元信息和下载（字幕 / 音频） |
| `ffmpeg`           | 音频切片（仅 ASR 分片场景） |
| `python3 + requests` | DashScope API 调用 |
| `ALIYUN_API_KEY`   | paraformer-v2 ASR（播客 + 无字幕视频） |
| `defuddle` CLI     | 文章正文提取（`npm install -g defuddle`） |
| `web_reader` MCP   | 文章 defuddle 失败时的兜底 |
| Bilibili cookies (optional) | member-only / age-restricted 视频用 `--cookies-from-browser chrome` |

---

## Step 0: URL 类型判定 + 目录路由

```python
import re, hashlib, urllib.parse
url = "URL"
parsed = urllib.parse.urlparse(url)
host = parsed.netloc.lower().replace('www.', '')

if re.search(r'podcasts\.apple\.com', host):
    kind, platform, output_dir = "podcast", "apple-podcasts", "AI/Podcasts"
elif re.search(r'xiaoyuzhoufm\.com', host):
    kind, platform, output_dir = "podcast", "xiaoyuzhou", "AI/Podcasts"
elif re.search(r'(youtube\.com|youtu\.be)', host):
    kind, platform, output_dir = "video", "youtube", "AI/YouTube"
elif re.search(r'(bilibili\.com|b23\.tv)', host):
    kind, platform, output_dir = "video", "bilibili", "AI/Bilibili"
else:
    # 交给 yt-dlp 探测：能吐元信息 → 按 podcast 处理；否则当 article。
    import subprocess
    probe = subprocess.run(
        ["yt-dlp", "--dump-json", "--skip-download", url],
        capture_output=True, text=True, timeout=30
    )
    if probe.returncode == 0 and probe.stdout.strip():
        kind, platform, output_dir = "podcast", host, "AI/Podcasts"
    else:
        kind, platform, output_dir = "article", host, "AI/Articles"

slug = hashlib.md5(url.encode()).hexdigest()[:10]
print(f"kind={kind} platform={platform} output_dir={output_dir} slug={slug}")
```

> 路由确定后：`kind in (podcast, video)` → Section 1；`kind == article` → Section 2；两路汇合到 Section 3 compose 笔记。

---

## Section 1: podcast / video — 元信息 + 下载 + 转录

### 1.0 元信息抓取（podcast 与 video 共用）

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
        # Detect auto-generated subtitles (video only)
        auto_subs = d.get('automatic_captions', {})
        manual_subs = d.get('subtitles', {})
        if auto_subs:
            print('AUTO_SUBS_AVAILABLE:', ','.join(auto_subs.keys()))
        if manual_subs:
            print('MANUAL_SUBS_AVAILABLE:', ','.join(manual_subs.keys()))
        if not auto_subs and not manual_subs:
            print('NO_SUBS_AVAILABLE')
        break
    except: continue
"
```

> **Bilibili:** 如下载失败（member-only / age-restricted），重试加 `--cookies-from-browser chrome`。

### 1.1 分支选择

| `kind` | 字幕 | 走向 |
|--------|------|------|
| `video`   | 有（auto/manual 任一） | Section 1A 字幕路径 |
| `video`   | 无                     | Section 1B ASR 路径 |
| `podcast` | —                      | Section 1B ASR 路径 |

**字幕优先级：** `zh-Hans` > `zh` > `en` > 首个可用。

---

### Section 1A — 字幕路径（video only）

#### 1A-1. 下载字幕

```bash
yt-dlp --write-auto-sub --sub-lang LANG --sub-format srv3/vtt/srt \
  --skip-download -o "./.link_sub_SLUG" "URL" 2>&1 | tail -3
```

#### 1A-2. 解析 VTT/SRT（按 timestamp gap > 3s 分段）

```python
import re, glob, json

def _parse_timestamp(ts_str):
    """Parse SRT/VTT timestamp to seconds."""
    ts_str = ts_str.strip().replace(',', '.')
    parts = ts_str.split(':')
    if len(parts) == 3:
        h, m, s = parts
        return int(h) * 3600 + int(m) * 60 + float(s)
    elif len(parts) == 2:
        m, s = parts
        return int(m) * 60 + float(s)
    return 0.0

def _collect_cues(content, is_vtt):
    """Return list of (start_sec, text) cues."""
    if is_vtt:
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
        start_ts = ts_line.split('-->')[0].strip()
        start_sec = _parse_timestamp(start_ts)
        text_lines = [l.strip() for l in parts[text_start:] if l.strip()]
        text = " ".join(text_lines)
        if is_vtt and text == prev_text:  # VTT often repeats cues
            continue
        if text:
            cues.append((start_sec, text))
            prev_text = text
    return cues

def _segment_by_gaps(cues, gap_threshold=3.0):
    """Group cues into paragraphs based on timestamp gaps > gap_threshold seconds.
    Output: list of {begin_ms, text}."""
    if not cues:
        return []
    segments = []
    cur_start = cues[0][0]
    cur_lines = [cues[0][1]]
    for i in range(1, len(cues)):
        gap = cues[i][0] - cues[i-1][0]
        if gap > gap_threshold:
            segments.append({"begin_ms": int(cur_start * 1000),
                             "text": " ".join(cur_lines)})
            cur_start = cues[i][0]
            cur_lines = [cues[i][1]]
        else:
            cur_lines.append(cues[i][1])
    if cur_lines:
        segments.append({"begin_ms": int(cur_start * 1000),
                         "text": " ".join(cur_lines)})
    return segments

# Auto-detect subtitle file
sub_files = glob.glob('./.link_sub_SLUG.*')
segments = []
for f in sub_files:
    with open(f, 'r', encoding='utf-8') as fh:
        content = fh.read()
    if f.endswith('.vtt'):
        segments = _segment_by_gaps(_collect_cues(content, is_vtt=True))
        break
    elif f.endswith('.srt'):
        segments = _segment_by_gaps(_collect_cues(content, is_vtt=False))
        break

with open('.link_segments_SLUG.json', 'w', encoding='utf-8') as fh:
    json.dump(segments, fh, ensure_ascii=False)
```

> **字幕分段逻辑：** 相邻 cue 时间间隔 > 3 秒即开新段，形成自然话题边界。输出 schema：`[{begin_ms, text}]`，与 ASR 路径统一。

字幕路径成功后跳到 **Section 3**。

---

### Section 1B — ASR 路径（podcast 或无字幕 video）

#### 1B-1. 下载音频

```bash
yt-dlp -f "bestaudio[ext=m4a]/bestaudio" \
  -o "./.link_audio_SLUG.%(ext)s" "URL" 2>&1 | tail -3
```

#### 1B-2. paraformer-v2 异步三步上传

> ⚠️ **重要警告（踩过的坑）：**
> - **不要** 直接 `POST https://dashscope.aliyuncs.com/api/v1/uploads` —— 该端点只接受 `GET`，`POST` 会返回 `405 Method Not Allowed`。
> - 提交转录任务时 **必须** 同时带上两个异步头：
>   - `X-DashScope-Async: enable`
>   - `X-DashScope-OssResourceResolve: enable`
> - 否则任务不会入队，或无法解析 `oss://` 资源。

```python
import os, json, time, mimetypes, pathlib, requests

API_KEY = os.environ["ALIYUN_API_KEY"]
AUDIO = pathlib.Path(".link_audio_SLUG.m4a")  # 按实际后缀替换
BASE = "https://dashscope.aliyuncs.com"
HEADERS_JSON = {"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"}

# Step A: GET policy (uploads endpoint is GET-only)
r = requests.get(
    f"{BASE}/api/v1/uploads",
    params={"action": "getPolicy", "model": "paraformer-v2"},
    headers={"Authorization": f"Bearer {API_KEY}"},
    timeout=30,
)
r.raise_for_status()
pol = r.json()["data"]
upload_host = pol["upload_host"]           # e.g. https://dashscope-file-mgr.oss-cn-beijing.aliyuncs.com
upload_dir = pol["upload_dir"]             # OSS key prefix
key = f"{upload_dir}/{AUDIO.name}"

# Step B: POST multipart to OSS upload_host
mime = mimetypes.guess_type(AUDIO.name)[0] or "audio/mpeg"
files = {
    "OSSAccessKeyId":         (None, pol["oss_access_key_id"]),
    "Signature":              (None, pol["signature"]),
    "policy":                 (None, pol["policy"]),
    "x-oss-object-acl":       (None, pol["x_oss_object_acl"]),
    "x-oss-forbid-overwrite": (None, pol["x_oss_forbid_overwrite"]),
    "key":                    (None, key),
    "success_action_status":  (None, "200"),
    "file":                   (AUDIO.name, AUDIO.read_bytes(), mime),
}
up = requests.post(upload_host, files=files, timeout=600)
assert up.status_code == 200, f"OSS upload failed: {up.status_code} {up.text[:300]}"
file_url = f"oss://{key}"
print("Uploaded:", file_url)

# Step C: POST transcription task (BOTH async headers REQUIRED)
headers_task = {
    **HEADERS_JSON,
    "X-DashScope-Async": "enable",
    "X-DashScope-OssResourceResolve": "enable",
}
body = {
    "model": "paraformer-v2",
    "input": {"file_urls": [file_url]},
    "parameters": {
        "sentence_timestamps": True,
        "language_hints": ["zh", "en"],
    },
}
tr = requests.post(
    f"{BASE}/api/v1/services/audio/asr/transcription",
    headers=headers_task, json=body, timeout=60,
)
tr.raise_for_status()
task_id = tr.json()["output"]["task_id"]
print("task_id:", task_id)

# Step D: Poll until SUCCEEDED
while True:
    q = requests.get(f"{BASE}/api/v1/tasks/{task_id}",
                     headers={"Authorization": f"Bearer {API_KEY}"}, timeout=30)
    q.raise_for_status()
    status = q.json()["output"]["task_status"]
    print("status:", status)
    if status in ("SUCCEEDED", "FAILED", "CANCELED"):
        break
    time.sleep(5)

assert status == "SUCCEEDED", f"ASR task ended with {status}"
# Result JSON is hosted; fetch and parse transcripts[0].sentences
result_url = q.json()["output"]["results"][0]["transcription_url"]
result = requests.get(result_url, timeout=60).json()
sentences = result["transcripts"][0]["sentences"]

# Step E: Convert to unified schema [{begin_ms, text}]
segments = [{"begin_ms": s["begin_time"], "text": s["text"]} for s in sentences]
with open(".link_segments_SLUG.json", "w", encoding="utf-8") as fh:
    json.dump(segments, fh, ensure_ascii=False)
```

> **长音频分片（可选）：** 单个音频过大时先用 `ffmpeg -i .link_audio_SLUG.m4a -ac 1 -f segment -segment_time 300 -c:a mp3 -q:a 5 -y ".link_chunks_SLUG/chunk_%04d.mp3"` 按 5 分钟切段，然后逐段走上面三步（或并发，`max_workers ≤ 3`），最后按 `begin_ms` 偏移合并。

---

## Section 2: article — 正文提取

### 2.1 抽取正文（首选 defuddle CLI）

```bash
defuddle parse "URL" --md -o ./.link_article_SLUG.md 2>&1
defuddle parse "URL" -p title 2>&1
defuddle parse "URL" -p description 2>&1
defuddle parse "URL" -p author 2>&1
defuddle parse "URL" -p date 2>&1
```

**兜底：** defuddle 失败（未安装 / 网络错误 / 付费墙 / 动态渲染）→ 用 `mcp__web_reader__webReader`：

```
URL: <article URL>
return_format: markdown
retain_images: true
```

从工具返回读取 markdown 内容。

### 2.2 解析 metadata + 计算 reading_time

```python
import re

with open('./.link_article_SLUG.md', 'r', encoding='utf-8') as f:
    content = f.read()

# 如果 defuddle -p 没给到，从正文推断：
# - title: 优先 defuddle -p title；否则 content 首个 <h1>
# - author: 优先 defuddle -p author；否则 byline
# - description: 优先 defuddle -p description；否则首段
date_match = re.search(r'(\d{4}[-/]\d{2}[-/]\d{2})', content[:2000])
publish_date = date_match.group(1).replace('/', '-') if date_match else ''

# Reading time: 中文 400 字/分钟；英文 200 词/分钟
char_count = len(content)
if re.search(r'[一-鿿]', content):
    reading_time = max(1, round(char_count / 400))
else:
    reading_time = max(1, round(len(content.split()) / 200))
print(f"Content: {char_count} chars, reading_time: {reading_time} min")
```

已知域名可映射为更友好的 `platform` 值（`medium.com`→`Medium`，`mp.weixin.qq.com`→`微信公众号`，`zhuanlan.zhihu.com`→`知乎专栏`，`juejin.cn`→`掘金`，`sspai.com`→`少数派`，`36kr.com`→`36氪`，`arxiv.org`→`arXiv`，`blog.csdn.net`→`CSDN` 等）；未知则用 host。

---

## Section 3: Compose 笔记（按类型分格式）

根据 `kind` 变量（`podcast` / `video` / `article`），选择不同的笔记模板。

### 3A. Podcast 笔记（富格式）

**Frontmatter：**

```yaml
---
title: <title>
tags: [<inferred topic tags>]
source: <url>
author: <series or host>
date: <YYYY-MM-DD>
type: 播客笔记
platform: <apple-podcasts | xiaoyuzhou | ...>
duration: "HH:MM"
transcript_source: asr
dialogue: true                             # 多人对话时才加
markmap:
  initialExpandLevel: 3
---
```

**章节骨架（完整富格式）：**

| 章节 | 说明 |
|------|------|
| `> [!info] 播客信息` | 节目·时长·发布日期·链接，1 句简介 |
| `## Shownotes` | 从 description 提取（主播/延伸资料/后期制作等），`> [!info]- 节目 Shownotes` 折叠 callout。若 description 无结构信息则省略 |
| `## 摘要` + Takeaways | 3–5 句整体摘要 + `> [!summary] Takeaways` 5–8 条要点 |
| `## 思维导图` | ````markmap` 代码块，根 1，一级 3–8，二三级覆盖细节不遗漏 |
| `## 章节导读` | 表格 `| MM:SS | 章节 | 概述 |`，3–8 行 |
| `## 金句 Highlights` | `> [!quote] ~ MM:SS` callout，3–8 条 |
| `## 详细论点` | 按 `###` 展开核心论证 |
| `## 个人思考` | checkbox 列表 |
| `## 完整转录` | `> [!note]- 完整转录` 折叠，`**[MM:SS]** **说话人：** <text>`（dialogue 时加说话人），不同段落空行分隔。> 20000 字符写占位 |

**时间戳来源：** ASR paraformer-v2 返回的 `sentence_timestamps` 中 `begin_time`（毫秒 → `MM:SS`），禁止按语速估算。

### 3B. Video 笔记（简洁格式）

**Frontmatter：**

```yaml
---
title: <title>
tags: [<inferred topic tags>]
source: <url>
author: <channel or uploader>
date: <YYYY-MM-DD>
type: 视频笔记
platform: <youtube | bilibili>
duration: "HH:MM"
transcript_source: <subtitle | asr>
---
```

**章节骨架（简洁格式）：**

```markdown
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
```

**Transcript storage rule:** If transcript exceeds **20000 characters**, do NOT save it — write `> 转录内容过长（N 字符），未保存。可从 [原视频](URL) 获取。`. Under 20000 chars, embed in collapsible callout with logical paragraph breaks.

**Transcript segmentation:** 转录按**内容逻辑**分段，而非时间或字数机械切割。ASR 分片的 `\n\n` 拼接只是中间产物，写入前必须通读全文在话题转换处断段。一般 20-30 分钟视频分成 15-25 段。

### 3C. Article 笔记（简洁格式）

**Frontmatter：**

```yaml
---
title: <title>
tags: [<inferred topic tags>]
source: <url>
author: <author>
date: <YYYY-MM-DD>
type: 文章笔记
platform: <domain>
reading_time: <N> min
---
```

**章节骨架（简洁格式）：**

```markdown
# <title>

> [!info] 文章信息
> author / reading time / date / [link](URL)

## 核心观点
[1-3 sentence summary of the article's main argument]

## [Section headers inferred from article content]
[Structured summary with callouts, tables, lists]

## 个人思考
- [ ] Action items

## 原文摘录

> [!note]-
> 摘录内容段落一……
>
> 摘录内容段落二……
```

**Content storage rule:** If original content exceeds **20000 characters**, write `> 原文内容过长（N 字符），未保存。可从 [原文链接](URL) 获取。`. Under 20000 chars, embed in collapsible callout with logical paragraph breaks.

**Content segmentation:** 原文摘录按**内容逻辑**分段，每 1000–2000 字一段，每段应是一个完整的论点或话题。过长且价值较低的部分可省略用 `[...省略...]` 标注。

**Write 文件：**

```python
import pathlib, re
safe_title = re.sub(r'[\\/:*?"<>|]', '_', title)  # 去掉 Windows 不合法字符
pathlib.Path(f"{output_dir}/{safe_title}.md").write_text(note_md, encoding="utf-8")
```

> **Why direct Write:** Obsidian CLI 的 `content` 参数受 shell 长度限制，长转录会截断；直接写文件无此限制，Obsidian 会自动检测变化。

---

## Cleanup

清理临时文件（`rm -rf` 被 hook 阻止，必须用 Python）：

```python
import os, glob
slug = "SLUG"

# audio/video 临时文件
for pat in (f'.link_sub_{slug}*', f'.link_audio_{slug}*', f'.link_segments_{slug}*'):
    for f in glob.glob(pat):
        if os.path.isfile(f):
            os.remove(f)

chunk_dir = f'.link_chunks_{slug}'
if os.path.isdir(chunk_dir):
    for f in glob.glob(f'{chunk_dir}/*'):
        os.remove(f)
    os.rmdir(chunk_dir)

# article 临时文件
for f in glob.glob(f'.link_article_{slug}*'):
    if os.path.isfile(f):
        os.remove(f)
```

---

## Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `401 Unauthorized` (DashScope) | `ALIYUN_API_KEY` 未加载到 shell | 设置 env 后重启 Claude Code |
| `405 Method Not Allowed` on `/api/v1/uploads` | 用了 `POST` | 该端点只接受 `GET`（`action=getPolicy&model=paraformer-v2`） |
| ASR 任务不入队 / 资源解析失败 | 缺少异步头 | 同时带 `X-DashScope-Async: enable` 和 `X-DashScope-OssResourceResolve: enable` |
| OSS 上传失败（403 / signature mismatch） | policy 字段没按原样回传 | multipart 里照抄 `getPolicy` 返回的 `policy/signature/OSSAccessKeyId/x-oss-*/key/success_action_status` |
| `400 invalid request`（ASR 分片） | 单段过大 | 用 ffmpeg 切 5 分钟一段 |
| `429` rate limit | 并发过高 | 降到 2–3 并发（`max_workers ≤ 3`） |
| 字幕解析为空 | 格式不合预期 | `--sub-format` 换 `srv3` / `vtt` / `srt` 挨个试 |
| `defuddle: command not found` | 未装 | `npm install -g defuddle` |
| 文章抽取是 HTML 不是 markdown | defuddle 失败 | 切 `web_reader` MCP，`return_format: markdown` |
| Bilibili 下载失败 | 会员 / 年龄限制 | 重试加 `--cookies-from-browser chrome` |
| `rm -rf` 被拦 | 安全 hook | 用 Python `os.remove` + `os.rmdir` |
| 标题含特殊字符 / 过长中文 | 文件系统不容 | `safe_title = re.sub(r'[\\/:*?"<>\|]', '_', title)` |

---

## Quick Reference

```
URL → detect kind (podcast / video / article)
    → podcast : yt-dlp audio → paraformer-v2 ASR (sentence_timestamps)
    → video   : yt-dlp → subtitle preferred → ASR fallback
    → article : defuddle → web_reader fallback
    → compose note per-type format:
        • podcast → rich (摘要 + Takeaways + 思维导图 + 章节导读 + 金句 + 详细论点 + 转录)
        • video   → concise (核心观点 + sections + 转录)
        • article → concise (核心观点 + sections + 原文摘录)
    → write AI/<type-dir>/<title>.md
    → cleanup temp files
```
