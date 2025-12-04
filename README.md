# Dotfiles

Personal configuration files managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Requirements

- GNU Stow
- Arch Linux (configurations assume systemd, pacman, etc.)
- zsh

## Installation

Clone the repository:

```bash
git clone <repo-url> ~/.dotfiles
cd ~/.dotfiles
```

Deploy all packages:

```bash
stow */
```

Or deploy individual packages:

```bash
stow zsh git ghostty
```

## Packages

| Package | Description |
|---------|-------------|
| `git` | Git configuration and global ignore patterns |
| `ghostty` | Ghostty terminal emulator configuration |
| `hypr` | Hyprland compositor (keybindings, monitors, autostart, appearance) |
| `ripgrep` | ripgrep configuration |
| `sqlite` | SQLite configuration |
| `zsh` | Zsh shell configuration with XDG compliance |

## Usage

### Deploy a package

```bash
stow <package>
```

### Remove a package

```bash
stow -D <package>
```

### Re-stow after changes

```bash
stow -R <package>
```

### Preview changes (dry run)

```bash
stow -n -v <package>
```

## Structure

Each package directory mirrors the home directory structure. Stow creates symlinks from `$HOME` pointing into this repository.

```
.dotfiles/
  git/
    .config/
      git/
        config    -> ~/.config/git/config
        ignore    -> ~/.config/git/ignore
  zsh/
    .zshenv       -> ~/.zshenv
    .config/
      zsh/
        .zshrc    -> ~/.config/zsh/.zshrc
```

## XDG Base Directory

Configurations follow the XDG Base Directory Specification where supported:

- `XDG_CONFIG_HOME` (~/.config) - Configuration files
- `XDG_DATA_HOME` (~/.local/share) - Application data
- `XDG_STATE_HOME` (~/.local/state) - State data (history, logs)
- `XDG_CACHE_HOME` (~/.cache) - Non-essential cached data

The zsh package uses a two-file approach: `.zshenv` in the home directory sets `ZDOTDIR` to redirect zsh to look for `.zshrc` in `~/.config/zsh/`.

## Adding New Configurations

1. Create a package directory: `mkdir ~/.dotfiles/<package>`
2. Create the directory structure mirroring where files should go in `$HOME`
3. Add or move configuration files into the package
4. Deploy with `stow <package>`

Example for adding neovim configuration:

```bash
mkdir -p ~/.dotfiles/nvim/.config/nvim
mv ~/.config/nvim/init.lua ~/.dotfiles/nvim/.config/nvim/
stow nvim
```
