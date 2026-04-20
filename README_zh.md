# skill-pack

为 AI 编程助手精心整理的 skill 合集，兼容 Claude Code、Codex CLI、OpenCode 和 OpenClaw。

[English](README.md)

## Skills

| Skill | 说明 |
|-------|------|
| [article-to-note](skills/article-to-note/SKILL.md) | 通过 Defuddle 或 web_reader 将网页文章转为 Obsidian 笔记 |
| [article-to-anki](skills/article-to-anki/SKILL.md) | 将网页文章转为 Anki 卡片（Markdown 格式，可导入 Anki） |
| [video-to-note](skills/video-to-note/SKILL.md) | 通过字幕或 ASR 将 YouTube / Bilibili 视频转为 Obsidian 笔记 |

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

# OpenClaw
curl -fsSL https://raw.githubusercontent.com/LjyYano/skill-pack/main/install.sh | bash -s -- --openclaw

# 全部安装
curl -fsSL https://raw.githubusercontent.com/LjyYano/skill-pack/main/install.sh | bash -s -- --all
```

### 手动安装

```bash
cp -r skills/video-to-note  ~/.claude/skills/
cp -r skills/article-to-note ~/.claude/skills/
cp -r skills/article-to-anki ~/.claude/skills/
```

## 示例

### article-to-note 示例

```sh
/article-to-note https://mp.weixin.qq.com/s/Ld_NbZZaYd2z9qpfMxP_aQ
```

> 输入微信公众号等文章链接 → skill 自动提取正文 → 输出结构化 Obsidian 笔记。

<details>
<summary>查看截图</summary>

![极简主义背后的逻辑](assets/examples/article-to-note.png)

</details>

### article-to-anki 示例

```sh
/article-to-anki https://mp.weixin.qq.com/s/Ld_NbZZaYd2z9qpfMxP_aQ
```

> 输入文章链接 → skill 自动提取正文 → 按逻辑拆分为独立知识卡片 → 输出 Markdown 格式的 Anki 卡片文件。

### video-to-note 示例

```sh
/video-to-note https://www.bilibili.com/video/BV1rxqmBhE91/
```

> 输入 Bilibili 视频链接 → skill 优先使用视频自带字幕；若无字幕，则下载音频并调用阿里云 ASR 转录 → 输出结构化 Obsidian 笔记。

<details>
<summary>查看截图</summary>

![上班、自由与结构](assets/examples/video-to-note.png)

</details>

#### ASR 配置（无字幕时需要）

当视频没有字幕时，skill 会使用阿里云 DashScope 的 `qwen3-asr-flash` 模型进行语音识别，需要配置 API Key。

**1. 获取 API Key**

前往 [阿里云百炼控制台](https://bailian.console.aliyun.com/) → 右上角头像 → **API-KEY** → 新建并复制。

**2. 配置环境变量**

```bash
# 临时生效（当前终端）
export ALIYUN_API_KEY="sk-xxxxxxxxxxxxxxxxxxxx"

# 永久生效（写入 shell 配置文件）
echo 'export ALIYUN_API_KEY="sk-xxxxxxxxxxxxxxxxxxxx"' >> ~/.zshrc
source ~/.zshrc
```

> **注意：** 在 Claude Code 中设置环境变量后，需要重启 Claude Code 才能生效。

**3. 验证配置**

```bash
echo $ALIYUN_API_KEY
```

输出非空即表示配置成功。

**其他依赖（ASR 路径需要）**

```bash
# macOS
brew install yt-dlp ffmpeg

# 验证
yt-dlp --version
ffmpeg -version
```

## Skill 目录

| 工具 | Skills 目录 |
|------|------------|
| Claude Code | `~/.claude/skills/` |
| Codex CLI | `~/.codex/skills/` |
| OpenCode | `~/.opencode/skills/` |
| OpenClaw | `~/.openclaw/skills/` |
