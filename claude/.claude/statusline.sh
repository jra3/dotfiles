#!/bin/bash
# Claude Code statusline that follows omarchy theme

# Get current omarchy theme from symlink
OMARCHY_THEME=$(readlink ~/.config/omarchy/current/theme 2>/dev/null | xargs basename)

# Map omarchy themes to claude-powerline themes
case "$OMARCHY_THEME" in
  tokyo-night)    POWERLINE_THEME="tokyo-night" ;;
  nord)           POWERLINE_THEME="nord" ;;
  gruvbox)        POWERLINE_THEME="gruvbox" ;;
  rose-pine)      POWERLINE_THEME="rose-pine" ;;
  catppuccin)     POWERLINE_THEME="tokyo-night" ;;  # closest match
  catppuccin-latte) POWERLINE_THEME="light" ;;
  flexoki-light)  POWERLINE_THEME="light" ;;
  everforest)     POWERLINE_THEME="gruvbox" ;;      # warm tones
  kanagawa)       POWERLINE_THEME="tokyo-night" ;;  # similar aesthetic
  hackerman)      POWERLINE_THEME="dark" ;;
  matte-black)    POWERLINE_THEME="dark" ;;
  osaka-jade)     POWERLINE_THEME="dark" ;;
  ristretto)      POWERLINE_THEME="gruvbox" ;;      # warm browns
  ethereal)       POWERLINE_THEME="nord" ;;         # cool tones
  *)              POWERLINE_THEME="dark" ;;         # fallback
esac

# Check if we're in a git worktree
WORKTREE_INDICATOR=""
if git rev-parse --git-dir &>/dev/null; then
  GIT_DIR=$(git rev-parse --git-dir 2>/dev/null)
  GIT_COMMON_DIR=$(git rev-parse --git-common-dir 2>/dev/null)

  # If git-dir != git-common-dir, we're in a worktree
  if [[ "$GIT_DIR" != "$GIT_COMMON_DIR" && -n "$GIT_COMMON_DIR" ]]; then
    # Get the main repo directory (parent of .git)
    MAIN_REPO=$(dirname "$GIT_COMMON_DIR")
    MAIN_REPO_NAME=$(basename "$MAIN_REPO")
    WORKTREE_INDICATOR=" ⊛ ${MAIN_REPO_NAME}"
  fi
fi

# Pass stdin through to claude-powerline, then append worktree indicator
npx -y @owloops/claude-powerline@latest --style=minimal --theme="$POWERLINE_THEME" | while IFS= read -r line; do
  echo "${line}${WORKTREE_INDICATOR}"
done
