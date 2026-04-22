---
name: link-to-html
description: Use when the user provides a URL (podcast / video / article) or a path to an existing Obsidian `.md` note file and wants a self-contained HTML viewer generated. Produces a Podwise-inspired single-file HTML with sidebar, episode header, 6 type-adaptive tabs (Summary, Mindmap, Transcript/Full-text, Keywords, Highlights, Info), dark/light theme, and markmap mindmap rendering.
---

# Link → HTML Viewer

## Overview

Read a URL or `.md` 文件（播客 / 视频 / 文章任意类型），产出单文件自包含 HTML：侧栏导航 + 顶部头部 + 6 个 tab 面板（按 `frontmatter.type` 自适应 labels 与内容）+ 深浅主题切换 + 交互式 markmap。

**Input:** URL **或**已有 `.md` 路径。

**Output:** 同目录同名 `.html`。

---

## Prerequisites

- No prerequisites when input is a URL (the skill fetches content independently). When input is a `.md` file, it should be an Obsidian note with standard frontmatter.
- Internet access for CDN scripts (d3, markmap-lib, markmap-view)

---

## Workflow

```
User input
  ├─ URL → detect type → fetch content independently → compose rich data → fill template → write .html
  └─ .md file path → read .md → extract data → fill HTML template → write .html
```

### Step 1: If input is a URL, fetch content + compose rich data

**1a. Detect content type**

```python
import re
url = "URL"
if re.search(r'podcasts\.apple\.com', url) or re.search(r'xiaoyuzhoufm\.com', url):
    kind = "podcast"
elif re.search(r'(youtube\.com|youtu\.be)', url):
    kind = "video"
elif re.search(r'(bilibili\.com|b23\.tv)', url):
    kind = "video"
else:
    kind = "article"
```

**1b. Fetch metadata** (all types)

```bash
yt-dlp --dump-json --skip-download "URL" 2>&1 | python3 -c "
import json, sys
for line in sys.stdin.read().strip().split('\n'):
    try:
        d = json.loads(line)
        print('TITLE:', d.get('title',''))
        print('SERIES:', d.get('series',''))
        print('UPLOADER:', d.get('channel','') or d.get('uploader',''))
        print('UPLOAD_DATE:', d.get('upload_date',''))
        print('DURATION:', d.get('duration_string',''))
        print('DESCRIPTION:', (d.get('description','') or '')[:500])
        auto_subs = d.get('automatic_captions', {})
        manual_subs = d.get('subtitles', {})
        if auto_subs: print('AUTO_SUBS:', ','.join(auto_subs.keys()))
        if manual_subs: print('MANUAL_SUBS:', ','.join(manual_subs.keys()))
        break
    except: continue
"
```

> For article URLs where yt-dlp fails, use defuddle CLI (`defuddle parse URL --md`) or `web_reader` MCP tool as fallback.

**1c. Fetch transcript/content**

| Type | Method |
|------|--------|
| Podcast | `yt-dlp` download audio → DashScope paraformer-v2 async ASR with `sentence_timestamps: true` → get sentences with `begin_time` |
| Video (has subs) | `yt-dlp --write-auto-sub --sub-lang LANG` → parse VTT/SRT, extract cues with timestamps |
| Video (no subs) | Same ASR path as podcast |
| Article | `defuddle parse URL --md` → `web_reader` MCP fallback → extract full text |

> The ASR upload flow uses DashScope's three-step process: `GET /api/v1/uploads?action=getPolicy` → multipart `POST` to OSS → `POST /api/v1/services/audio/asr/transcription` with headers `X-DashScope-Async: enable` and `X-DashScope-OssResourceResolve: enable`, then poll `/api/v1/tasks/<id>` to SUCCEEDED. See `link-to-note` skill for full code.

**1d. Compose rich data for HTML template**

From the transcript/content, compose ALL of the following (this is the "rich" format — the HTML viewer needs all tabs populated):

- **SUMMARY_BODY**: 3–5 sentence summary
- **TAKEAWAYS**: 5–8 key points
- **MINDMAP_MD**: markmap markdown (root + 3–8 level-1 nodes + level-2/3 details covering all key points)
- **OUTLINES**: 3–8 chapters with `MM:SS` timestamps (only for podcast/video; empty array for article)
- **HIGHLIGHTS**: 3–8 best quotes with `MM:SS` timestamps (podcast/video) or without (article)
- **KEYWORDS**: ~25 keywords from tags + high-frequency terms
- **TURNS**: transcript segments with `{ts, sp, text}` for podcast (with speakers), `{ts, text}` for video (no speakers), or `{text}` for article (no timestamps)
- **SHOWNOTES_CONTENT**: podcast shownotes / video info meta card / article info meta card

> **Timestamps:** Use ASR `begin_time` (ms) or subtitle cue start (s), convert to `MM:SS`. Never estimate.

**1e. Set type-adaptive flags**

```python
type_map = {"podcast": "podcast", "video": "video", "article": "article"}
TYPE = type_map.get(kind, "article")
HAS_TIMESTAMPS = kind in ("podcast", "video")
HAS_OUTLINES = kind in ("podcast", "video")
HAS_SPEAKERS = kind == "podcast"  # or check dialogue flag
TAB_3_LABEL = "Transcript" if HAS_TIMESTAMPS else "Full Text"
TAB_6_LABEL = {"podcast": "Shownotes", "video": "Video Info", "article": "Article Info"}[TYPE]
```

### Step 2: If input is a .md file, parse it

Extract the following data from the note:

| Data | Source in .md | How to extract |
|------|--------------|----------------|
| `TITLE` | frontmatter `title` or first `# heading` | Direct read |
| `PODCAST_NAME` | frontmatter `author` | Take part before `·` (e.g. `商业就是这样 · 肖文杰 / 约小亚` → `商业就是这样`) |
| `DATE_DISPLAY` | frontmatter `date` | Format as `DD Mon YYYY` (e.g. `2026-03-30` → `30 Mar 2026`) |
| `DURATION` | frontmatter `duration` | Use as-is (e.g. `"14:36"` → `14m36s` for display) |
| `PLATFORM` | frontmatter `platform` | Use as-is |
| `SOURCE_URL` | frontmatter `source` | For links |
| `TAGS` | frontmatter `tags` | Array of tag strings |
| `IS_DIALOGUE` | frontmatter `dialogue` | `true` if dialogue podcast |
| `SUMMARY_BODY` | `## 摘要` section, first paragraph | Text between `## 摘要` and `> [!summary]` |
| `TAKEAWAYS[]` | `> [!summary] Takeaways` bullet list | Each `- ` item as a string |
| `MINDMAP_MD` | Content inside ` ```markmap ` code block | Raw markdown text between code fences |
| `OUTLINES[]` | `## 章节导读` table rows | Parse `| MM:SS | title | desc |` → `{ts, text}` |
| `HIGHLIGHTS[]` | `> [!quote] ~ MM:SS` callouts | Parse timestamp and quote text → `{ts, text}` |
| `DETAILS_HTML` | `## 详细论点` through `## 个人思考` | Convert each `###` subsection to HTML `<div class="detail-section">` |
| `THOUGHTS[]` | `## 个人思考` checkbox items | Each `- [ ] text` as a string |
| `TURNS[]` | `> [!note]- 完整转录` content | Parse `**[MM:SS]** **Speaker：** Text` → `{ts, sp, text}` |
| `SHOWNOTES_HTML` | `> [!info]- 节目 Shownotes` content | Convert key-value pairs to `<dl class="shownotes-grid">` |
| `COVER_ZH` | First 2 chars of `PODCAST_NAME` | For cover placeholder |
| `COVER_EN` | English equivalent if available, else omit | For cover placeholder |

### Step 2b: Type-specific extraction differences

According to `frontmatter.type`:

| Field | 播客笔记 | 视频笔记 | 文章笔记 |
|-------|---------|---------|---------|
| `TAB_3_LABEL`  | `Transcript` | `Transcript` | `Full Text` |
| `TAB_6_LABEL`  | `Shownotes`  | `Video Info` | `Article Info` |
| `HAS_TIMESTAMPS` | `true`      | `true`       | `false` |
| `HAS_OUTLINES`   | `true`      | `true`       | `false` |
| `HAS_SPEAKERS`   | = `dialogue` | `false`     | `false` |
| `TYPE`           | `podcast`   | `video`      | `article` |
| `TURNS[]` parse | `**[MM:SS]** **Speaker：** Text` | `**[MM:SS]** Text` (no speaker) | paragraphs by `\n\n`, each `{text}` no ts |
| `OUTLINES[]`   | from `## 章节导读` | from `## 章节导读` | empty array |
| `SHOWNOTES_CONTENT` | shownotes callout grid | `{channel, duration, upload_date, view_count, url}` | `{author, reading_time, platform, url}` |
| `COVER_ZH`     | `PODCAST_NAME` first 2 chars | channel name first 2 chars | `platform` first 2 chars |

### Step 3: Build SPEAKER_CLASS map

If `IS_DIALOGUE` is true, scan all `TURNS` for unique speaker names. Assign CSS class names:
- First speaker → `sp1`
- Second speaker → `sp2`
- "合" or similar → `both`

Generate corresponding CSS classes with distinct colors from palette:
```
#7c5cfc (purple), #0ea5e9 (blue), #f59e0b (amber), #22c55e (green), #ef4444 (red), #8b5cf6 (violet)
```

Each speaker gets a light-mode and dark-mode style:
```css
.speaker-sp1{background:#ede8ff;color:#7c5cfc}
[data-theme="dark"] .speaker-sp1{background:rgba(124,92,252,0.20);color:#b49aff}
```

If not dialogue, use a single speaker class.

### Step 4: Generate KEYWORDS array

Combine:
1. All frontmatter `tags` (excluding generic ones like `播客笔记`)
2. Extract top 10-15 high-frequency nouns/terms from the summary body

Deduplicate and limit to ~25 keywords.

### Step 5: Fill the HTML template

Read `template.html` from the skill directory. Replace all `{{PLACEHOLDER}}` tokens with extracted data. Write the result to the output `.html` file.

---

## Template Placeholders

The template file is `template.html` (same directory as this SKILL.md). All `{{TOKEN}}` strings are replaced with episode-specific data:

| Placeholder | Source | Example value |
|-------------|--------|---------------|
| `{{TITLE}}` | frontmatter `title` | `商业小样37 \| "意想不到的 AI 股"：康宁` |
| `{{PODCAST_NAME}}` | frontmatter `author`, before `·` | `商业就是这样` |
| `{{COVER_ZH}}` | First 2 chars of `PODCAST_NAME` | `商业` |
| `{{COVER_ZH_FIRST_CHAR}}` | First char of `PODCAST_NAME` | `商` |
| `{{COVER_EN}}` | English equivalent or empty string | `JUST BUSINESS` |
| `{{COVER_GRADIENT_START}}` | From gradient palette | `#ff7a4e` |
| `{{COVER_GRADIENT_END}}` | From gradient palette | `#ee4f3a` |
| `{{DATE_DISPLAY}}` | Formatted from frontmatter `date` | `30 Mar 2026` |
| `{{DURATION_DISPLAY}}` | From frontmatter `duration` | `14m36s` |
| `{{PLATFORM}}` | From frontmatter `platform` | `Apple Podcasts` |
| `{{SUMMARY_BODY}}` | `## 摘要` first paragraph | (full text) |
| `{{TAKEAWAYS_HTML}}` | `<li class="takeaway">...</li>` items | (HTML string) |
| `{{OUTLINES_JSON}}` | JSON array | `[{ts:'00:00',text:'...'}]` |
| `{{TURNS_JSON}}` | JSON array | `[{ts:'00:02',sp:'肖文杰',text:'...'}]` |
| `{{HIGHLIGHTS_JSON}}` | JSON array | `[{ts:'01:55',text:'...'}]` |
| `{{KEYWORDS_JSON}}` | JSON array of strings | `['康宁','AI',...]` |
| `{{MINDMAP_MD}}` | Raw markmap markdown (escape backticks) | (multiline string) |
| `{{SPEAKER_CLASS_JSON}}` | JSON object | `{'肖文杰':'xiao','约小亚':'yue','合':'both'}` |
| `{{SPEAKER_CSS}}` | Generated speaker chip CSS | (see below) |
| `{{TURN_ACTIVE_CSS}}` | Generated turn active border CSS | (see below) |
| `{{HIGHLIGHTS_COUNT}}` | Number of highlights | `7` |
| `{{SHOWNOTES_CONTENT}}` | Full shownotes HTML block | (meta info + details + thoughts) |

### New type-adaptive placeholders

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `{{TAB_3_LABEL}}` | Tab 3 display text | `Transcript` / `Full Text` |
| `{{TAB_6_LABEL}}` | Tab 6 display text | `Shownotes` / `Video Info` / `Article Info` |
| `{{HAS_TIMESTAMPS}}` | JS flag for timestamp controls | `true` / `false` |
| `{{HAS_OUTLINES}}`   | Whether to show outlines block | `true` / `false` |
| `{{HAS_SPEAKERS}}`   | Whether to show speaker chips | `true` / `false` |
| `{{TYPE}}`           | `podcast` / `video` / `article` | `video` |

### Generating SPEAKER_CSS

For each unique speaker in TURNS, assign a class name (`sp1`, `sp2`, `sp3`...) and color from the palette `['#7c5cfc','#0ea5e9','#f59e0b','#22c55e','#ef4444','#8b5cf6']`. Generate:

```css
.speaker-sp1{background:#ede8ff;color:#7c5cfc}
.speaker-sp2{background:#e0f4ff;color:#0ea5e9}
[data-theme="dark"] .speaker-sp1{background:rgba(124,92,252,0.20);color:#b49aff}
[data-theme="dark"] .speaker-sp2{background:rgba(14,165,233,0.20);color:#7dd3fc}
```

Light background = `color` at 10% opacity mixed with white. Dark text = lighter version of `color`.

### Generating TURN_ACTIVE_CSS

For each speaker class, generate the active border highlight:

```css
.turn.active.sp1 .turn-body{border-left-color:#7c5cfc}
.turn.active.sp2 .turn-body{border-left-color:#0ea5e9}
```

### Generating SHOWNOTES_CONTENT

Build the HTML from three parts:
1. **Meta info card**: `<div class="meta-info">...</div>` + `<h2>{{TITLE}}</h2>` + `<p>{{description}}</p>` + `<dl class="shownotes-grid">...</dl>` (from shownotes callout key-value pairs)
2. **Detail sections**: Each `###` subsection under `## 详细论点` → `<div class="detail-section"><h3>...</h3><p>...</p><ul>...</ul><div class="tip-box">...</div></div>`
3. **Personal thoughts**: `## 个人思考` checkboxes → `<div class="personal-thoughts">...</div>`

---

## Cover Placeholder Rules

- Use the podcast name's first 2 Chinese characters for `cover-zh`
- Use an uppercase English translation/abbreviation for `cover-en` if available
- Background gradient: pick from these palettes based on podcast name hash:
  ```
  ['#ff7a4e','#ee4f3a'], ['#3b82f6','#1d4ed8'], ['#10b981','#059669'],
  ['#f59e0b','#d97706'], ['#8b5cf6','#6d28d9'], ['#ec4899','#be185d']
  ```
- Apply to `.episode-cover` background, `.mini-cover` background, and `.mini-play-btn` is not affected

---

## Critical Implementation Notes

1. **markmap dark mode text**: Must use CSS variable override `--markmap-text-color:#ffffff` on `.mindmap-wrap .markmap` in dark theme. Do NOT use `fill` on SVG `text` or inline `<style>` injection — markmap uses `foreignObject` with HTML divs, not SVG text.

2. **CDN load order**: d3 → markmap-lib → markmap-view. All three are required.

3. **Transcript search**: Use `<mark>` with inline style for highlighting. Escape regex special chars in search term.

4. **Speaker styles**: Generate dynamically based on unique speakers found in TURNS. Each gets a color from the 6-color palette.

5. **The template file** (`template.html`) contains all static CSS, HTML structure, and JS logic — only the `{{PLACEHOLDER}}` tokens change between episodes.

6. **Type-adaptive labels**: Replace tab 3 and tab 6 hard-coded text with `{{TAB_3_LABEL}}` and `{{TAB_6_LABEL}}` placeholders.

7. **Article hides timestamp controls**: When `HAS_TIMESTAMPS === false`, hide highlight `~MM:SS` buttons, hide Outlines panel, render transcript as plain paragraphs.

8. **Article Shownotes tab**: Render simplified meta card with `{ author, reading_time, platform, url }`, tab label is `Article Info`.

---

## Quick Reference

```
Input: URL or .md path
  → URL path:
      detect type → fetch metadata + content (yt-dlp / ASR / subtitles / defuddle)
      → compose rich data (Summary + Takeaways + Mindmap + Outlines + Highlights + Keywords + Turns + Shownotes)
      → set type flags (TYPE, HAS_TIMESTAMPS, HAS_OUTLINES, HAS_SPEAKERS, TAB_*_LABEL)
      → fill template.html → write .html
  → .md path:
      read .md → extract data from frontmatter + sections
      → set type flags from frontmatter.type
      → fill template.html → write .html
```
