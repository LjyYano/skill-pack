---
name: link-to-html
description: Use when the user provides a podcast/video/article URL or an existing Obsidian note (.md) and wants a self-contained HTML viewer page generated. Produces a Podwise-inspired single-file HTML with sidebar, episode header, 6 tabs (Summary, Mindmap, Transcript, Keywords, Highlights, Shownotes), dark/light theme, and markmap mindmap rendering.
---

# Podcast Note → HTML Viewer

## Overview

Read an Obsidian podcast note (`.md`) and produce a single self-contained HTML file with a Podwise-inspired UI: sidebar navigation, episode header, 6 tabbed panels, dark/light theme toggle, and interactive markmap mindmap.

**Input:** Podcast URL (will invoke `link-to-note` skill first) **OR** path to an existing `.md` podcast note.

**Output:** Same directory as the `.md`, same filename but `.html` extension.

**Example:** `AI/Podcasts/商业小样37 意想不到的 AI 股 康宁.md` → `AI/Podcasts/商业小样37 意想不到的 AI 股 康宁.html`

---

## Prerequisites

- The `.md` note must follow the `link-to-note` skill's template (frontmatter + 摘要 + Takeaways + 思维导图 + 章节导读 + 金句 + 详细论点 + 完整转录)
- Internet access for CDN scripts (d3, markmap-lib, markmap-view)

---

## Workflow

```
User input
  ├─ Podcast URL → invoke link-to-note skill → get .md path → continue ↓
  └─ .md file path → read .md → extract data → fill HTML template → write .html
```

### Step 1: If input is a URL, generate the note first

Invoke the `link-to-note` skill with the URL. Wait for it to finish and produce the `.md` file. Then continue to Step 2.

### Step 2: Read and parse the `.md` note

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
| `SUMMARY_BODY` | `## 摘要` section, first paragraph | Text between `## 摘要` and `> [!summary]` |
| `TAKEAWAYS[]` | `> [!summary] Takeaways` bullet list | Each `- ` item as a string |
| `MINDMAP_MD` | Content inside ` ```markmap ` code block | Raw markdown text between code fences |
| `OUTLINES[]` | `## 章节导读` table rows | Parse `| MM:SS | title | desc |` → `{ts, text}` |
| `HIGHLIGHTS[]` | `> [!quote] ~ MM:SS` callouts | Parse timestamp and quote text → `{ts, text}` |
| `DETAILS_HTML` | `## 详细论点` through `## 个人思考` | Convert each `###` subsection to HTML `<div class="detail-section">` |
| `THOUGHTS[]` | `## 个人思考` checkbox items | Each `- [ ] text` as a string |
| `TURNS[]` | `> [!note]- 完整转录` content | Parse `**[MM:SS]** Text` → `{ts, text}` (no speaker) |
| `SHOWNOTES_HTML` | `> [!info]- 节目 Shownotes` content | Convert key-value pairs to `<dl class="shownotes-grid">` |
| `COVER_ZH` | First 2 chars of `PODCAST_NAME` | For cover placeholder |
| `COVER_EN` | English equivalent if available, else omit | For cover placeholder |

### Step 3: Generate KEYWORDS array

Combine:
1. All frontmatter `tags` (excluding generic ones like `播客笔记`)
2. Extract top 10-15 high-frequency nouns/terms from the summary body

Deduplicate and limit to ~25 keywords.

### Step 4: Fill the HTML template

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
| `{{TURNS_JSON}}` | JSON array | `[{ts:'00:02',text:'...'}]` (no speaker) |
| `{{HIGHLIGHTS_JSON}}` | JSON array | `[{ts:'01:55',text:'...'}]` |
| `{{KEYWORDS_JSON}}` | JSON array of strings | `['康宁','AI',...]` |
| `{{MINDMAP_MD}}` | Raw markmap markdown (escape backticks) | (multiline string) |
| `{{HIGHLIGHTS_COUNT}}` | Number of highlights | `7` |
| `{{SHOWNOTES_CONTENT}}` | Full shownotes HTML block | (meta info + details + thoughts) |

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

4. **No speaker labels.** Transcript turns render as `ts + text` only; the `.speaker-chip` element is not emitted. Upstream `link-to-note` also omits speaker labels (过往 diarization / shownotes-inference 都不稳定).

5. **The template file** (`template.html`) contains all static CSS, HTML structure, and JS logic — only the `{{PLACEHOLDER}}` tokens change between episodes.

---

## Quick Reference

```
Input: URL or .md path
  → (if URL) invoke link-to-note → get .md
  → Parse .md → extract TITLE, PODCAST_NAME, DATE, DURATION, PLATFORM,
                 SUMMARY, TAKEAWAYS, MINDMAP_MD, OUTLINES, HIGHLIGHTS,
                 TURNS (ts+text, no speaker), KEYWORDS, DETAILS, THOUGHTS, SHOWNOTES
  → Fill HTML template (copy static parts from reference)
  → Write to same-dir .html
```
