#!/usr/bin/env bash
set -e

REPO="https://raw.githubusercontent.com/LjyYano/skill-pack/main"
SKILLS=(
  "video-to-note"
  "article-to-note"
  "article-to-anki"
)

# Target directories per tool
CLAUDE_DIR="$HOME/.claude/skills"
CODEX_DIR="$HOME/.codex/skills"
OPENCODE_DIR="$HOME/.opencode/skills"
OPENCLAW_DIR="$HOME/.openclaw/skills"

install_skills() {
  local target_dir="$1"
  local tool_name="$2"

  mkdir -p "$target_dir"
  echo "Installing to $target_dir ($tool_name)..."
  for skill in "${SKILLS[@]}"; do
    mkdir -p "$target_dir/$skill"
    curl -fsSL "$REPO/skills/$skill/SKILL.md" -o "$target_dir/$skill/SKILL.md"
    echo "  ✓ $skill"
  done
}

# Parse args: --claude / --codex / --opencode / --all (default: auto-detect)
TARGET="${1:-auto}"

case "$TARGET" in
  --claude)
    install_skills "$CLAUDE_DIR" "Claude Code"
    ;;
  --codex)
    install_skills "$CODEX_DIR" "Codex CLI"
    ;;
  --opencode)
    install_skills "$OPENCODE_DIR" "OpenCode"
    ;;
  --openclaw)
    install_skills "$OPENCLAW_DIR" "OpenClaw"
    ;;
  --all)
    install_skills "$CLAUDE_DIR"    "Claude Code"
    install_skills "$CODEX_DIR"     "Codex CLI"
    install_skills "$OPENCODE_DIR"  "OpenCode"
    install_skills "$OPENCLAW_DIR"  "OpenClaw"
    ;;
  auto)
    INSTALLED=0
    [ -d "$HOME/.claude" ]    && install_skills "$CLAUDE_DIR"    "Claude Code"  && INSTALLED=1
    [ -d "$HOME/.codex" ]     && install_skills "$CODEX_DIR"     "Codex CLI"    && INSTALLED=1
    [ -d "$HOME/.opencode" ]  && install_skills "$OPENCODE_DIR"  "OpenCode"     && INSTALLED=1
    [ -d "$HOME/.openclaw" ]  && install_skills "$OPENCLAW_DIR"  "OpenClaw"     && INSTALLED=1
    if [ $INSTALLED -eq 0 ]; then
      echo "No supported AI tool detected. Use a flag to install manually:"
      echo "  --claude    → $CLAUDE_DIR"
      echo "  --codex     → $CODEX_DIR"
      echo "  --opencode  → $OPENCODE_DIR"
      echo "  --openclaw  → $OPENCLAW_DIR"
      echo "  --all       → all four"
      exit 1
    fi
    ;;
  *)
    echo "Usage: install.sh [--claude|--codex|--opencode|--openclaw|--all]"
    exit 1
    ;;
esac

echo ""
echo "Done! Restart your AI tool to use the new skills."
