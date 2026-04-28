# skill-pack

为 AI 编程助手精心整理的 skill 合集，兼容 Claude Code、Codex CLI、OpenCode 和 OpenClaw。

[English](README.md)

## 优先用哪个

新用户建议从 [`link-to-note`](skills/link-to-note/SKILL.md) 开始。它是推荐的「URL 转 Obsidian 笔记」工作流，覆盖 YouTube、Bilibili、Apple Podcasts、小宇宙，以及其他兼容的音频链接。

[`video-to-note`](skills/video-to-note/SKILL.md) 主要用于兼容旧的视频专用流程。新使用场景优先选择 `link-to-note`。

## Skills

| Skill | 状态 | 适合场景 | 输出位置 |
|-------|------|----------|----------|
| [link-to-note](skills/link-to-note/SKILL.md) | 推荐 | 将播客 / 视频 URL 转为结构化 Obsidian 笔记 | `AI/YouTube/`、`AI/Bilibili/`、`AI/Podcasts/` 或 `AI/Audio/` |
| [link-to-html](skills/link-to-html/SKILL.md) | 推荐 | 将 `link-to-note` 笔记或 URL 转为 Podwise 风格独立 HTML 页面 | 与源 `.md` 同目录 |
| [article-to-anki](skills/article-to-anki/SKILL.md) | 推荐 | 将网页文章或本地文章转为 Anki 可导入的 Markdown 卡片 | `AI/Anki/` |
| [video-to-note](skills/video-to-note/SKILL.md) | 旧版 | 旧的 YouTube / Bilibili 视频笔记流程 | `AI/YouTube/` 或 `AI/Bilibili/` |

## 快速开始

```bash
curl -fsSL https://raw.githubusercontent.com/LjyYano/skill-pack/main/install.sh | bash
```

重启你的 AI 编程助手，然后运行已安装的 skill 命令：

```sh
/link-to-note https://www.youtube.com/watch?v=xxx
/link-to-note https://www.bilibili.com/video/BV1rxqmBhE91/
/link-to-note https://podcasts.apple.com/cn/podcast/.../id1552904790?i=1000755467027
/link-to-html AI/Podcasts/example-note.md
/article-to-anki https://example.com/article
```

如果要生成 Obsidian 笔记，建议在 Obsidian vault 根目录运行助手。skill 会相对当前工作目录写入文件，从 vault 根目录运行时，生成的 `AI/...` 文件可以被 Obsidian 自动索引。

## 安装

### 一键安装

自动检测已安装工具，并安装到对应的 skill 目录：

```bash
curl -fsSL https://raw.githubusercontent.com/LjyYano/skill-pack/main/install.sh | bash
```

### 指定工具安装

```bash
curl -fsSL https://raw.githubusercontent.com/LjyYano/skill-pack/main/install.sh | bash -s -- <flag>
```

| Flag | 目标 |
|------|------|
| `--claude` | Claude Code（`~/.claude/skills/`） |
| `--codex` | Codex CLI（`~/.codex/skills/`） |
| `--opencode` | OpenCode（`~/.opencode/skills/`） |
| `--openclaw` | OpenClaw（`~/.openclaw/skills/`） |
| `--all` | 以上全部 |

### 手动安装

克隆本仓库后，将需要的 skill 复制到对应助手的 skill 目录：

```bash
SKILLS_DIR="$HOME/.codex/skills"  # Claude Code、OpenCode 或 OpenClaw 请改成对应目录。
mkdir -p "$SKILLS_DIR"
cp -r skills/link-to-note    "$SKILLS_DIR"/
cp -r skills/link-to-html    "$SKILLS_DIR"/
cp -r skills/article-to-anki "$SKILLS_DIR"/
```

常见 skill 目录：

| 工具 | Skills 目录 |
|------|------------|
| Claude Code | `~/.claude/skills/` |
| Codex CLI | `~/.codex/skills/` |
| OpenCode | `~/.opencode/skills/` |
| OpenClaw | `~/.openclaw/skills/` |

只有需要旧版流程时，再额外复制 `skills/video-to-note`。

## 依赖

| Skill | 必需 | 可选 / 条件触发 |
|-------|------|-----------------|
| `link-to-note` | `python3`、`requests`；YouTube、播客和通用音频 URL 需要 `yt-dlp` | 播客、音频链接、无字幕视频需要 `ALIYUN_API_KEY` |
| `link-to-html` | `link-to-note` 格式的 `.md` 笔记，或可先由 `link-to-note` 处理的 URL | markmap 渲染需要访问 CDN 脚本 |
| `article-to-anki` | 文章 URL 或本地文章文件 | 助手侧可用的网页正文提取能力 |
| `video-to-note` | `yt-dlp`、`ffmpeg`、`python3`、`requests`、Obsidian CLI | ASR 兜底需要 `ALIYUN_API_KEY` |

### ASR 配置

`link-to-note` 会优先使用视频字幕。视频没有字幕，或输入为播客 / 音频 URL 时，会使用阿里云 DashScope 的 `paraformer-v2` 模型进行异步语音识别。

前往 [阿里云百炼控制台](https://bailian.console.aliyun.com/) 创建 API Key，然后配置环境变量：

```bash
# 临时生效，仅当前终端
export ALIYUN_API_KEY="sk-xxxxxxxxxxxxxxxxxxxx"

# 持久生效，以 zsh 为例
echo 'export ALIYUN_API_KEY="sk-xxxxxxxxxxxxxxxxxxxx"' >> ~/.zshrc
source ~/.zshrc
```

设置环境变量后，需要重启你的 AI 编程助手。

macOS 安装 `yt-dlp`，用于 YouTube、播客和通用音频 URL：

```bash
brew install yt-dlp
yt-dlp --version
```

如果缺少 Python 依赖，可以安装 `requests`：

```bash
python3 -m pip install requests
```

`link-to-note` 不需要 `ffmpeg`；`paraformer-v2` 会直接处理整段音频。

## 示例

### link-to-note

```sh
/link-to-note https://podcasts.apple.com/cn/podcast/.../id1552904790?i=1000755467027
/link-to-note https://www.xiaoyuzhoufm.com/episode/xxx
/link-to-note https://www.youtube.com/watch?v=xxx
/link-to-note https://www.bilibili.com/video/BV1rxqmBhE91/
```

`link-to-note` 会自动识别平台，优先从字幕获取转录，无字幕时使用 ASR 兜底，并输出包含摘要、要点、思维导图、章节、金句、详细论点、个人思考和完整转录的 Obsidian 笔记。

<details>
<summary>查看截图</summary>

![link-to-note 示例](assets/examples/video-to-note.png)

</details>

### link-to-html

```sh
/link-to-html https://podcasts.apple.com/cn/podcast/%E5%95%86%E4%B8%9A%E5%B0%8F%E6%A0%B735-%E9%9C%8D%E5%B0%94%E6%9C%A8%E5%85%B9%E6%B5%B7%E5%B3%A1%E4%B8%8A%E7%9A%84%E7%89%B9%E6%AE%8A%E4%BF%9D%E9%99%A9/id1552904790?i=1000755467027
/link-to-html AI/Podcasts/example-note.md
```

输入播客 / 视频 URL，或传入已有的 `link-to-note` 生成 `.md` 笔记。skill 会生成独立 HTML 页面，包含侧边栏、6 个标签页、深色 / 浅色主题切换、转录搜索、金句、Shownotes 和交互式 markmap 思维导图。

<video src="https://github.com/LjyYano/skill-pack/raw/main/assets/examples/podcast-to-html.mp4" controls width="100%"></video>

### article-to-anki

```sh
/article-to-anki https://mp.weixin.qq.com/s/Ld_NbZZaYd2z9qpfMxP_aQ
```

输入文章 URL 或本地文章路径。skill 会提取正文，按逻辑拆分为独立知识卡片，并写入可导入 Anki 的 Markdown 文件。

<details>
<summary>查看截图</summary>

![article-to-anki 示例](assets/examples/article-to-note.png)

</details>

## 注意事项

- 生成文件会写入当前工作目录下。
- `link-to-note` 不标注说话人；转录行只保留时间戳和正文。
- `link-to-note` 处理 Bilibili 时走 REST API，不走 `yt-dlp`，因为当前 `yt-dlp` 提取 Bilibili 可能返回 HTTP 412。
- `link-to-html` 会在源 `.md` 同目录输出 `.html` 文件。
