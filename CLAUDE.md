# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a GNU Stow-managed dotfiles repository for an Arch Linux system running Hyprland (Wayland compositor). Each top-level directory is a "stow package" that mirrors the home directory structure.

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

## Architecture

**Stow packages** - Each directory is independent and can be deployed separately:
- `zsh/` - Shell configuration (XDG-compliant)
- `git/` - Git config and global ignore patterns
- `ghostty/` - Ghostty terminal emulator
- `hypr/` - Hyprland compositor (monitors, keybindings, autostart, etc.)
- `ripgrep/` - ripgrep configuration
- `sqlite/` - SQLite configuration

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
