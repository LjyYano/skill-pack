# skill-pack

为 AI 编程助手精心整理的 skill 合集，兼容 Claude Code、Codex CLI、OpenCode 和 OpenClaw。

[English](README.md)

## Skills

| Skill | 说明 |
|-------|------|
| [link-to-note](skills/link-to-note/SKILL.md) | 将任意 URL（播客 / 视频 / 文章）转为结构化 Obsidian 笔记 |
| [link-to-html](skills/link-to-html/SKILL.md) | 将任意 URL 或 Obsidian 笔记转为 Podwise 风格的独立 HTML 展示页面 |
| [article-to-anki](skills/article-to-anki/SKILL.md) | 将网页文章转为 Anki 卡片（Markdown 格式，可导入 Anki） |

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
cp -r skills/link-to-note   ~/.claude/skills/
cp -r skills/link-to-html    ~/.claude/skills/
cp -r skills/article-to-anki ~/.claude/skills/
```

## 示例

### link-to-note 示例

```sh
/link-to-note https://mp.weixin.qq.com/s/Ld_NbZZaYd2z9qpfMxP_aQ
/link-to-note https://podcasts.apple.com/cn/podcast/.../id1552904790?i=1000755467027
/link-to-note https://www.bilibili.com/video/BV1rxqmBhE91/
```

> 输入任意 URL（文章 / 播客 / 视频）→ skill 自动识别类型 → 提取内容 → 输出包含摘要、要点、思维导图、金句和转录/全文的结构化 Obsidian 笔记。

<details>
<summary>查看截图</summary>

![极简主义背后的逻辑](assets/examples/article-to-note.png)

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

### link-to-html 示例

```sh
/link-to-html https://podcasts.apple.com/cn/podcast/%E5%95%86%E4%B8%9A%E5%B0%8F%E6%A0%B735-%E9%9C%8D%E5%B0%94%E6%9C%A8%E5%85%B9%E6%B5%B7%E5%B3%A1%E4%B8%8A%E7%9A%84%E7%89%B9%E6%AE%8A%E4%BF%9D%E9%99%A9/id1552904790?i=1000755467027
```

> 输入任意 URL 或已有 Obsidian 笔记路径 → skill 生成 Podwise 风格的独立 HTML 页面，包含侧边栏、6 个标签页（摘要、思维导图、转录/全文、关键词、金句、信息）、深色/浅色主题切换和交互式 markmap。

<video src="https://github.com/LjyYano/skill-pack/raw/main/assets/examples/podcast-to-html.mp4" controls width="100%"></video>

### article-to-anki 示例

```sh
/article-to-anki https://mp.weixin.qq.com/s/Ld_NbZZaYd2z9qpfMxP_aQ
```

> 输入文章链接 → skill 自动提取正文 → 按逻辑拆分为独立知识卡片 → 输出 Markdown 格式的 Anki 卡片文件。

## Skill 目录

| 工具 | Skills 目录 |
|------|------------|
| Claude Code | `~/.claude/skills/` |
| Codex CLI | `~/.codex/skills/` |
| OpenCode | `~/.opencode/skills/` |
| OpenClaw | `~/.openclaw/skills/` |
