# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a GNU Stow-managed dotfiles repository for an Omarchy system (DHH's Arch Linux + Hyprland distribution). Each top-level directory is a "stow package" that mirrors the home directory structure.

**Claude skill:** Use `/omarchy` for help with Hyprland config, keybindings, monitors, themes, input devices, or any `~/.config/hypr/` files.

## Common Commands

```bash
# Deploy a package (creates symlinks in $HOME)
stow <package>

# Deploy all packages
stow */

# Remove a package's symlinks
stow -D <package>

# Preview what stow would do (dry run)
stow -n -v <package>

# Re-stow (useful after adding files)
stow -R <package>
```

## Default Software

This documents the default software stack configured in Omarchy:

| Category | Software | Description |
|----------|----------|-------------|
| Shell | **zsh** | Default shell with XDG-compliant config |
| Prompt | **Starship** | Cross-shell prompt with git integration |
| Terminal | **Ghostty** | GPU-accelerated terminal (CaskaydiaMono Nerd Font) |
| Multiplexer | **tmux** | Terminal multiplexer with worktree integration |
| Compositor | **Hyprland** | Wayland tiling compositor |
| Browser | **Helium** | Web browser |
| Editor | **Emacs** | Text editor (emacsclient for fast startup) |
| AI | **Claude Code** | AI-powered coding assistant |
| VCS | **Git** | Version control with custom aliases |
| GitHub | **gh** | GitHub CLI with `gh prs` for PR listing |
| Search | **ripgrep** | Fast recursive grep |
| Worktrees | **gtr** | Git worktree runner for parallel development |
| Database | **SQLite** | Database with custom config |
| Packages | **pacman/yay** | Arch package manager (package lists tracked) |

## Architecture

**Stow packages** - Each directory is independent and can be deployed separately:
- `zsh/` - Shell configuration (XDG-compliant)
- `git/` - Git config and global ignore patterns
- `ghostty/` - Ghostty terminal emulator
- `hypr/` - Hyprland compositor (monitors, keybindings, autostart, etc.)
- `ripgrep/` - ripgrep configuration
- `sqlite/` - SQLite configuration
- `starship/` - Starship prompt configuration
- `tmux/` - tmux terminal multiplexer
- `gh/` - GitHub CLI config and `gh-prs` script
- `gtr/` - Git worktree runner wrapper
- `claude/` - Claude Code settings and custom commands
- `pacman/` - Arch package lists for reproducibility

**XDG compliance** - Configs use XDG Base Directory paths:
- Config files go in `<package>/.config/<app>/`
- Shell config files (`.zshenv`, `.zshrc`) must remain in home directory per zsh conventions

**Directory mirroring** - Stow creates symlinks by mirroring the package structure into `$HOME`. For example:
```
.dotfiles/git/.config/git/config  →  ~/.config/git/config
.dotfiles/zsh/.zshenv             →  ~/.zshenv
```

## Adding New Configurations

1. Create a new package directory: `mkdir <package>`
2. Mirror the home directory structure inside it
3. Move/create config files in the mirrored location
4. Run `stow <package>` to deploy

## Post-Install Setup

Some software requires additional setup after stowing:

```bash
# Enable Emacs daemon (runs emacs --fg-daemon at login)
systemctl --user enable --now emacs
```
