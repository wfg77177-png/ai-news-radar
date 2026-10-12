#!/bin/bash
# SessionStart hook for Claude Code cloud sessions.
#  1. Installs Python deps into .venv so pytest works.
#  2. Links public skills from this repo and sibling repos into ~/.claude/skills.
#  3. Installs the official frontend-design and claude-security plugins.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKSPACE_DIR="$(dirname "$REPO_DIR")"

# --- 1. Python deps (uv builds sgmllib3k; the system setuptools cannot) ---
cd "$REPO_DIR"
if command -v uv >/dev/null 2>&1; then
  [ -x .venv/bin/python ] || uv venv -q .venv
  uv pip install -q --python .venv/bin/python -r requirements-dev.txt
else
  python3 -m venv .venv
  .venv/bin/python -m pip install -q --upgrade pip setuptools wheel
  .venv/bin/python -m pip install -q -r requirements-dev.txt
fi
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"$REPO_DIR/.venv/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi

# --- 2. Skills: link skills/<name>/SKILL.md from repos present in the session ---
SKILLS_DIR="$HOME/.claude/skills"
mkdir -p "$SKILLS_DIR"
for repo in ai-news-radar dbx OpenShell; do
  for skill_md in "$WORKSPACE_DIR/$repo"/skills/*/SKILL.md; do
    [ -f "$skill_md" ] || continue
    skill_dir="$(dirname "$skill_md")"
    name="$(awk '/^name:/ {print $2; exit}' "$skill_md")"
    name="${name:-$(basename "$skill_dir")}"
    target="$SKILLS_DIR/$name"
    # Never clobber a real skill directory; only refresh our own symlinks.
    if [ -e "$target" ] && [ ! -L "$target" ]; then
      continue
    fi
    ln -sfn "$skill_dir" "$target"
  done
done

# --- 3. Plugins (best effort: a network hiccup must not block the session) ---
if command -v claude >/dev/null 2>&1; then
  installed="$(claude plugin list 2>/dev/null || true)"
  if ! claude plugin marketplace list 2>/dev/null | grep -q claude-plugins-official; then
    claude plugin marketplace add anthropics/claude-plugins-official >/dev/null 2>&1 || true
  fi
  for plugin in frontend-design claude-security; do
    if ! grep -q "$plugin@claude-plugins-official" <<<"$installed"; then
      claude plugin install "$plugin@claude-plugins-official" >/dev/null 2>&1 || true
    fi
  done
fi
