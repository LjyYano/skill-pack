# skill-pack

为 AI 编程助手精心整理的 skill 合集，兼容 Claude Code、Codex CLI 和 OpenCode。

## Skills

| Skill | 说明 |
|-------|------|
| [video-to-note](skills/video-to-note/SKILL.md) | 通过字幕或 ASR 将 YouTube / Bilibili 视频转为 Obsidian 笔记 |
| [article-to-note](skills/article-to-note/SKILL.md) | 通过 Defuddle 或 web_reader 将网页文章转为 Obsidian 笔记 |

## 示例

### video-to-note

输入 Bilibili 视频链接 → skill 自动提取字幕（ASR）→ 输出结构化 Obsidian 笔记。

![上班、自由与结构](assets/examples/video-to-note.png)

### article-to-note

输入微信公众号等文章链接 → skill 自动提取正文 → 输出结构化 Obsidian 笔记。

![极简主义背后的逻辑](assets/examples/article-to-note.png)

## 安装

### 一键安装（自动检测已安装工具）

```bash
curl -fsSL https://raw.githubusercontent.com/LjyYano/skill-pack/main/install.sh | bash
```

### 指定工具安装

```bash
# Claude Code
curl -fsSL https://raw.githubusercontent.com/LjyYano/skill-pack/main/install.sh | bash -s -- --claude

# Codex CLI
curl -fsSL https://raw.githubusercontent.com/LjyYano/skill-pack/main/install.sh | bash -s -- --codex

# OpenCode
curl -fsSL https://raw.githubusercontent.com/LjyYano/skill-pack/main/install.sh | bash -s -- --opencode

# 全部安装
curl -fsSL https://raw.githubusercontent.com/LjyYano/skill-pack/main/install.sh | bash -s -- --all
```

### 手动安装

```bash
cp -r skills/video-to-note  ~/.claude/skills/
cp -r skills/article-to-note ~/.claude/skills/
```

## Skill 目录

| 工具 | Skills 目录 |
|------|------------|
| Claude Code | `~/.claude/skills/` |
| Codex CLI | `~/.codex/skills/` |
| OpenCode | `~/.opencode/skills/` |
