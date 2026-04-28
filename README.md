# skill-pack

A curated collection of skills for AI coding assistants, compatible with Claude Code, Codex CLI, OpenCode, and OpenClaw.

[中文文档](README_zh.md)

## What to Use First

Start with [`link-to-note`](skills/link-to-note/SKILL.md). It is the recommended URL-to-note workflow for YouTube, Bilibili, Apple Podcasts, Xiaoyuzhou, and other compatible audio links.

[`video-to-note`](skills/video-to-note/SKILL.md) is kept for backward compatibility with the old video-only workflow. Prefer `link-to-note` for new usage.

## Skills

| Skill | Status | Best for | Output |
|-------|--------|----------|--------|
| [link-to-note](skills/link-to-note/SKILL.md) | Recommended | Convert podcast / video URLs to structured Obsidian notes | `AI/YouTube/`, `AI/Bilibili/`, `AI/Podcasts/`, or `AI/Audio/` |
| [link-to-html](skills/link-to-html/SKILL.md) | Recommended | Convert a `link-to-note` note or URL to a Podwise-inspired standalone HTML viewer | Same directory as the source `.md` |
| [article-to-anki](skills/article-to-anki/SKILL.md) | Recommended | Convert web articles or local articles to Anki-ready Markdown cards | `AI/Anki/` |
| [video-to-note](skills/video-to-note/SKILL.md) | Legacy | Old YouTube / Bilibili-only note workflow | `AI/YouTube/` or `AI/Bilibili/` |

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/LjyYano/skill-pack/main/install.sh | bash
```

Restart your AI coding assistant, then run one of the installed skill commands:

```sh
/link-to-note https://www.youtube.com/watch?v=xxx
/link-to-note https://www.bilibili.com/video/BV1rxqmBhE91/
/link-to-note https://podcasts.apple.com/cn/podcast/.../id1552904790?i=1000755467027
/link-to-html AI/Podcasts/example-note.md
/article-to-anki https://example.com/article
```

For Obsidian notes, run your assistant from the root of your Obsidian vault when possible. The skills write files relative to the current working directory, so running from the vault root lets Obsidian index the generated `AI/...` files automatically.

## Installation

### One-click install

Auto-detect installed tools and install into their skill directories:

```bash
curl -fsSL https://raw.githubusercontent.com/LjyYano/skill-pack/main/install.sh | bash
```

### Install for a specific tool

```bash
curl -fsSL https://raw.githubusercontent.com/LjyYano/skill-pack/main/install.sh | bash -s -- <flag>
```

| Flag | Target |
|------|--------|
| `--claude` | Claude Code (`~/.claude/skills/`) |
| `--codex` | Codex CLI (`~/.codex/skills/`) |
| `--opencode` | OpenCode (`~/.opencode/skills/`) |
| `--openclaw` | OpenClaw (`~/.openclaw/skills/`) |
| `--all` | All of the above |

### Manual install

Clone this repository, then copy the skills you want into your assistant's skills directory:

```bash
SKILLS_DIR="$HOME/.codex/skills"  # Change this for Claude Code, OpenCode, or OpenClaw.
mkdir -p "$SKILLS_DIR"
cp -r skills/link-to-note    "$SKILLS_DIR"/
cp -r skills/link-to-html    "$SKILLS_DIR"/
cp -r skills/article-to-anki "$SKILLS_DIR"/
```

Common skill directories:

| Tool | Skills Directory |
|------|-----------------|
| Claude Code | `~/.claude/skills/` |
| Codex CLI | `~/.codex/skills/` |
| OpenCode | `~/.opencode/skills/` |
| OpenClaw | `~/.openclaw/skills/` |

Copy `skills/video-to-note` too only if you need the legacy workflow.

## Requirements

| Skill | Required | Optional / conditional |
|-------|----------|------------------------|
| `link-to-note` | `python3`, `requests`; `yt-dlp` for YouTube, podcasts, and generic audio URLs | `ALIYUN_API_KEY` for podcasts, audio links, and videos without subtitles |
| `link-to-html` | A `link-to-note` style `.md` note, or a URL that can first be processed by `link-to-note` | Internet access for CDN scripts used by markmap rendering |
| `article-to-anki` | An article URL or local article file | A page extractor available to your assistant |
| `video-to-note` | `yt-dlp`, `ffmpeg`, `python3`, `requests`, Obsidian CLI | `ALIYUN_API_KEY` for ASR fallback |

### ASR configuration

`link-to-note` uses video subtitles whenever they are available. When a video has no subtitles, or when the input is a podcast / audio URL, it uses Alibaba Cloud DashScope `paraformer-v2` for async speech recognition.

Get an API key from the [Alibaba Cloud DashScope Console](https://bailian.console.aliyun.com/), then set:

```bash
# Current session only
export ALIYUN_API_KEY="sk-xxxxxxxxxxxxxxxxxxxx"

# Persistent, for zsh
echo 'export ALIYUN_API_KEY="sk-xxxxxxxxxxxxxxxxxxxx"' >> ~/.zshrc
source ~/.zshrc
```

Restart your AI coding assistant after setting the environment variable.

Install `yt-dlp` on macOS for YouTube, podcasts, and generic audio URLs:

```bash
brew install yt-dlp
yt-dlp --version
```

Install the Python dependency if it is missing:

```bash
python3 -m pip install requests
```

`link-to-note` does not require `ffmpeg`; `paraformer-v2` processes the full audio file directly.

## Examples

### link-to-note

```sh
/link-to-note https://podcasts.apple.com/cn/podcast/.../id1552904790?i=1000755467027
/link-to-note https://www.xiaoyuzhoufm.com/episode/xxx
/link-to-note https://www.youtube.com/watch?v=xxx
/link-to-note https://www.bilibili.com/video/BV1rxqmBhE91/
```

`link-to-note` detects the platform, fetches transcript data from subtitles when possible, falls back to ASR when needed, and writes a structured Obsidian note with summary, takeaways, mindmap, chapters, highlights, detailed points, personal thoughts, and full transcript.

<details>
<summary>Screenshot</summary>

![link-to-note example](assets/examples/video-to-note.png)

</details>

### link-to-html

```sh
/link-to-html https://podcasts.apple.com/cn/podcast/%E5%95%86%E4%B8%9A%E5%B0%8F%E6%A0%B735-%E9%9C%8D%E5%B0%94%E6%9C%A8%E5%85%B9%E6%B5%B7%E5%B3%A1%E4%B8%8A%E7%9A%84%E7%89%B9%E6%AE%8A%E4%BF%9D%E9%99%A9/id1552904790?i=1000755467027
/link-to-html AI/Podcasts/example-note.md
```

Paste a podcast / video URL, or pass an existing `.md` note generated by `link-to-note`. The skill creates a standalone HTML viewer with sidebar navigation, 6 tabs, dark/light theme, transcript search, highlights, shownotes, and an interactive markmap mindmap.

<video src="https://github.com/LjyYano/skill-pack/raw/main/assets/examples/podcast-to-html.mp4" controls width="100%"></video>

### article-to-anki

```sh
/article-to-anki https://mp.weixin.qq.com/s/Ld_NbZZaYd2z9qpfMxP_aQ
```

Paste an article URL or local article path. The skill extracts the content, splits it into independent knowledge cards, and writes import-ready Markdown Anki cards.

<details>
<summary>Screenshot</summary>

![article-to-anki example](assets/examples/article-to-note.png)

</details>

## Notes

- Generated files are written under the current working directory.
- `link-to-note` does not add speaker labels; transcript lines use timestamp plus text only.
- `link-to-note` uses Bilibili REST APIs instead of `yt-dlp`, because current `yt-dlp` Bilibili extraction may return HTTP 412.
- `link-to-html` outputs an `.html` file next to the source `.md` file.
