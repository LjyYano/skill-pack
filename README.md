# skill-pack

A curated collection of skills for AI coding assistants, compatible with Claude Code, Codex CLI, OpenCode, and OpenClaw.

[中文文档](README_zh.md)

## Skills

| Skill | Description |
|-------|-------------|
| [link-to-note](skills/link-to-note/SKILL.md) | Convert any URL (podcast / video / article) to a structured Obsidian note |
| [link-to-html](skills/link-to-html/SKILL.md) | Convert any URL or Obsidian note to a Podwise-inspired standalone HTML viewer |
| [article-to-anki](skills/article-to-anki/SKILL.md) | Convert web articles to Anki cards (Markdown format, import-ready) |

## Installation

### One-click install (auto-detect installed tools)

```bash
curl -fsSL https://raw.githubusercontent.com/LjyYano/skill-pack/main/install.sh | bash
```

### Install for a specific tool

```bash
# Claude Code
curl -fsSL https://raw.githubusercontent.com/LjyYano/skill-pack/main/install.sh | bash -s -- --claude

# Codex CLI
curl -fsSL https://raw.githubusercontent.com/LjyYano/skill-pack/main/install.sh | bash -s -- --codex

# OpenCode
curl -fsSL https://raw.githubusercontent.com/LjyYano/skill-pack/main/install.sh | bash -s -- --opencode

# OpenClaw
curl -fsSL https://raw.githubusercontent.com/LjyYano/skill-pack/main/install.sh | bash -s -- --openclaw

# Install all
curl -fsSL https://raw.githubusercontent.com/LjyYano/skill-pack/main/install.sh | bash -s -- --all
```

### Manual install

```bash
cp -r skills/link-to-note   ~/.claude/skills/
cp -r skills/link-to-html    ~/.claude/skills/
cp -r skills/article-to-anki ~/.claude/skills/
```

## Examples

### link-to-note

```sh
/link-to-note https://mp.weixin.qq.com/s/Ld_NbZZaYd2z9qpfMxP_aQ
/link-to-note https://podcasts.apple.com/cn/podcast/.../id1552904790?i=1000755467027
/link-to-note https://www.bilibili.com/video/BV1rxqmBhE91/
```

> Paste any URL (article / podcast / video) → the skill auto-detects content type → fetches content → outputs a structured Obsidian note with summary, takeaways, mindmap, highlights, and transcript/full-text.

<details>
<summary>Screenshot</summary>

![article-to-note example](assets/examples/article-to-note.png)

</details>

#### ASR Configuration (required when video has no subtitles)

When a video has no subtitles, the skill uses Alibaba Cloud DashScope's `qwen3-asr-flash` model for speech recognition. An API Key is required.

**1. Get your API Key**

Go to [Alibaba Cloud DashScope Console](https://bailian.console.aliyun.com/) → Avatar (top-right) → **API-KEY** → Create and copy.

**2. Set the environment variable**

```bash
# Current session only
export ALIYUN_API_KEY="sk-xxxxxxxxxxxxxxxxxxxx"

# Persistent (add to shell config)
echo 'export ALIYUN_API_KEY="sk-xxxxxxxxxxxxxxxxxxxx"' >> ~/.zshrc
source ~/.zshrc
```

> **Note:** After setting environment variables in Claude Code, you need to restart Claude Code for them to take effect.

**3. Verify the configuration**

```bash
echo $ALIYUN_API_KEY
```

Non-empty output means the configuration is successful.

**Other dependencies (required for ASR path)**

```bash
# macOS
brew install yt-dlp ffmpeg

# Verify
yt-dlp --version
ffmpeg -version
```

### link-to-html

```sh
/link-to-html https://podcasts.apple.com/cn/podcast/%E5%95%86%E4%B8%9A%E5%B0%8F%E6%A0%B735-%E9%9C%8D%E5%B0%94%E6%9C%A8%E5%85%B9%E6%B5%B7%E5%B3%A1%E4%B8%8A%E7%9A%84%E7%89%B9%E6%AE%8A%E4%BF%9D%E9%99%A9/id1552904790?i=1000755467027
```

> Paste any URL or path to an existing Obsidian note → the skill generates a Podwise-inspired standalone HTML with sidebar, 6 tabs (Summary, Mindmap, Transcript/Full-text, Keywords, Highlights, Info), dark/light theme, and interactive markmap.

<video src="https://github.com/LjyYano/skill-pack/raw/main/assets/examples/podcast-to-html.mp4" controls width="100%"></video>

### article-to-anki

```sh
/article-to-anki https://mp.weixin.qq.com/s/Ld_NbZZaYd2z9qpfMxP_aQ
```

> Paste an article URL → the skill extracts the content → splits into independent knowledge cards → outputs Markdown Anki card files.

## Skill Directories

| Tool | Skills Directory |
|------|-----------------|
| Claude Code | `~/.claude/skills/` |
| Codex CLI | `~/.codex/skills/` |
| OpenCode | `~/.opencode/skills/` |
| OpenClaw | `~/.openclaw/skills/` |
