# Article → Obsidian Note

## Overview

Extract clean content from web articles using Defuddle CLI (preferred) or `web_reader` MCP tool (fallback), then write a structured Obsidian note.

**Supported platforms:** Any public web article (blog posts, news, technical articles, etc.)

**Output directory:** `AI/Articles/`

---

## Prerequisites

- `defuddle` CLI — preferred method for extracting clean content (`npm install -g defuddle`)
- `web_reader` MCP tool — fallback when defuddle fails
- Obsidian vault at working directory — notes written directly via Write tool

---

## Step-by-Step Workflow

### 0. Parse URL and detect source

```python
import re
from urllib.parse import urlparse

url = "URL"
parsed = urlparse(url)
domain = parsed.netloc.replace('www.', '')

# Categorize source
known_sources = {
    'medium.com': 'Medium',
    'dev.to': 'DEV Community',
    'zhuanlan.zhihu.com': '知乎专栏',
    'www.zhihu.com': '知乎',
    'mp.weixin.qq.com': '微信公众号',
    'juejin.cn': '掘金',
    'segmentfault.com': '思否',
    'sspai.com': '少数派',
    '36kr.com': '36氪',
    'arxiv.org': 'arXiv',
    'blog.csdn.net': 'CSDN',
}

platform = known_sources.get(domain, domain)
output_dir = "AI/Articles"
print(f"Platform: {platform}, Domain: {domain}")
```

> Use `platform` and `output_dir` throughout the workflow.

### 1. Extract article content

**Preferred: Defuddle CLI**

```bash
# Extract full article as markdown
defuddle parse "URL" --md -o ./.article_content.md 2>&1

# Also extract metadata
defuddle parse "URL" -p title 2>&1
defuddle parse "URL" -p description 2>&1
defuddle parse "URL" -p author 2>&1
defuddle parse "URL" -p date 2>&1
```

**Fallback: web_reader MCP tool**

If defuddle fails (not installed, network error, paywalled content, etc.), use the `mcp__web_reader__webReader` tool:

```
URL: <article URL>
return_format: markdown
retain_images: true
```

Then read the extracted content from the tool output.

### 2. Parse content and metadata

After extraction, read the content and identify:

```python
import re

# Read extracted content
with open('./.article_content.md', 'r') as f:
    content = f.read()

# Extract metadata from defuddle JSON if available, or infer from content
# - title: from defuddle -p title or <h1> in content
# - author: from defuddle -p author or byline in content
# - date: from defuddle -p date or date pattern in content
# - description: from defuddle -p description or first paragraph

# Infer publish date from content
date_match = re.search(r'(\d{4}[-/]\d{2}[-/]\d{2})', content[:2000])
publish_date = date_match.group(1).replace('/', '-') if date_match else ''

# Estimate reading time (Chinese: ~400 chars/min, English: ~200 words/min)
char_count = len(content)
if re.search(r'[\u4e00-\u9fff]', content):
    reading_time = max(1, round(char_count / 400))
else:
    word_count = len(content.split())
    reading_time = max(1, round(word_count / 200))

print(f"Content length: {char_count} chars, Estimated reading time: {reading_time} min")
```

### 3. Create Obsidian note

**Note structure template:**

```markdown
---
title: <article title>
tags: [<inferred topics>]
source: <original url>
author: <author name>
date: <YYYY-MM-DD>
reading_time: <N min>
type: 文章笔记
platform: <platform>
---

# <title>

> [!info] 文章信息
> author / reading time / date / [link](URL)

## 核心观点
[1-3 sentence summary of the article's main argument or thesis]

## [Section headers inferred from article content]
[Structured summary with callouts, tables, lists]

## 个人思考
- [ ] Action items

## 原文摘录

> [!note]-
> 摘录内容段落一……
>
> 摘录内容段落二……
>
> 摘录内容段落三……
```

> **Content storage rule:** If original content exceeds **20000 characters**, do NOT save it — just leave a note like `> 原文内容过长（N 字符），未保存。可从 [原文链接](URL) 获取。`. Under 20000 chars, embed in a collapsible callout with **logical paragraph breaks** (each paragraph separated by `>` lines).
>
> **Content segmentation (重要):** 原文摘录必须按照**内容逻辑**分段，而非机械切割。
> - 通读全文，在话题转换处断段（如：新论点提出、举例结束回到主旨、从一种类型切换到另一种类型）
> - 跨段落边界的句子必须合并为完整段落
> - **分段粒度**：一般每 1000-2000 字分成一段。每段应是一个完整的论点、叙述单元或话题。
> - 过长且价值较低的部分（如大段代码、冗长的数据罗列）可以适当省略，用 `[...省略...]` 标注

**Write strategy:**

- **默认直接用 Write tool 写入** `<output_dir>/<title>.md`，Obsidian 会自动检测文件变化
- 文件名中的 `/` 替换为 `_`，避免路径问题

### 4. Cleanup

```python
import os
for f in ['./.article_content.md', './.article_meta.json']:
    if os.path.isfile(f):
        os.remove(f)
```

---

## Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `defuddle: command not found` | Not installed | `npm install -g defuddle` |
| Empty content extracted | Paywall / JS-rendered | Try `web_reader` MCP tool fallback |
| Content is HTML, not markdown | Defuddle parsing failed | Use `web_reader` with `return_format: markdown` |
| Title extraction fails | Unusual page structure | Manually extract from `<h1>` or `<title>` tag |
| Chinese encoding garbled | Wrong encoding | Defuddle handles UTF-8 natively; re-run with `--md` |

---

## Quick Reference

```
URL → detect platform (domain-based categorization)
    → defuddle parse URL --md (preferred)
        ├─ Success → read content + metadata → proceed
        └─ Fail → web_reader MCP tool (fallback)
    → infer reading time + metadata
    → summarize → write to AI/Articles/<title>.md → cleanup
```
