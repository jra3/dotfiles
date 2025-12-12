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

# Pass stdin through to claude-powerline with the mapped theme
exec npx -y @owloops/claude-powerline@latest --style=minimal --theme="$POWERLINE_THEME"
