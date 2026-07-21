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
| Passwords | **Bitwarden** | Password manager with CLI (`bw`) |
| Packages | **pacman/yay** | Arch package manager (package lists tracked) |

## Architecture

**Stow packages** - Each directory is independent and can be deployed separately:
- `zsh/` - Shell configuration (XDG-compliant)
- `git/` - Git config, global ignore patterns, SSH commit signing (`allowed_signers` + `setup-git-signing`)
- `ghostty/` - Ghostty terminal emulator
- `hypr/` - Hyprland compositor (monitors, keybindings, autostart, etc.)
- `ripgrep/` - ripgrep configuration
- `sqlite/` - SQLite configuration
- `starship/` - Starship prompt configuration
- `tmux/` - tmux terminal multiplexer
- `herdr/` - herdr terminal workspace manager (annotated default config; binary at `~/.local/bin/herdr`, not stow-managed); see `herdr/README.md`
- `gh/` - GitHub CLI config and `gh-prs` script
- `gtr/` - Git worktree runner wrapper
- `lazygit/` - lazygit TUI config with Graphite (gt) stacked-diff custom commands
- `claude/` - Claude Code settings and custom commands
- `slack/` - `slack://` deep-link handler that opens links in the browser (no desktop Slack app); see `slack/README.md`
- `bitwarden/` - Bitwarden CLI helper script (`get-signature`) for extracting attachments
- `pacman/` - Arch package lists and `configure-system` for post-install setup
- `qmk/` - Optional: `qmk-mic-led-sync.py` daemon syncing mic/DND/voxtype/pomodoro state to a Framework 16 ANSI keyboard via raw HID
- `tether/` - `waybar-iphone-tether` status script for the waybar iPhone USB-tethering indicator; see `tether/README.md`. The `.network` file and `usbmuxd` are handled by `pacman/configure-system` + `packages-arch.txt`

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

Run `pacman/configure-system` to configure system services (Tailscale operator, Emacs daemon, etc.). The script is idempotent and safe to re-run.

## Git commit signing (per-machine YubiKey)

Commits are signed with a YubiKey-resident SSH key. Config is shared via the `git/`
package (`gpg.format=ssh`, `commit.gpgsign`, `user.signingkey` → a canonical key
path), but **each machine has its own signing key on its own YubiKey**:

1. On a new machine, run `setup-git-signing` (from `git/.local/bin/`, on `$PATH`).
   It generates a resident no-touch/no-PIN `sk-ed25519` key at
   `~/.ssh/id_ed25519_sk_gitsign`, registers it in `allowed_signers`, and uploads
   it to GitHub as a signing key. Idempotent.
2. Commit the updated `allowed_signers` so other machines can verify this one's
   commits.

`allowed_signers` accumulates one line per machine. Both identities
(`github@porcnick.com` personal, `john@antimetal.com` work) share each key.
Note: `commit.gpgsign` is global, so the signing key must exist before committing —
run `setup-git-signing` as part of bootstrapping a new machine.
