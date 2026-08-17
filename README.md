# Dotfiles

Personal configuration files managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Requirements

- GNU Stow
- zsh
- **Arch Linux (Omarchy)** or **macOS**. Most packages are shared; the ones that
  aren't are skipped automatically per platform — see [Platforms](#platforms).

## Installation

Clone the repository, then let `bootstrap` deploy the right package set for the
platform it's running on:

```bash
git clone <repo-url> ~/jra3/dotfiles
cd ~/jra3/dotfiles

./bootstrap --list      # show which packages this platform will stow/skip
./bootstrap --dry-run   # preview, change nothing
./bootstrap             # deploy
```

Then install packages and configure the system — same two steps, different
directory per platform:

```bash
pacman/install-packages && pacman/configure-system   # Arch
brew/install-packages   && brew/configure-system     # macOS
```

You can still drive stow by hand; `bootstrap` is only a wrapper that knows the
platform split:

```bash
stow zsh git kitty
```

> **If you ever add a package that ships a systemd drop-in, stow it with
> `--no-folding`.** Stow's default folding replaces a directory it alone provides
> with a symlink, and systemd silently ignores a drop-in directory that is a
> symlink. No package currently does this.

## Platforms

`bootstrap` sorts every package into one of three buckets. The authoritative
lists live at the top of the script.

- **Shared** — `zsh git tmux starship ripgrep sqlite gh ghostty claude
  ccstatusline lazygit gtr bitwarden herdr ssh`
- **Linux only** — `hypr emacs power obsidian webapps bambu-studio
  google-chrome slack tether voxtype qmk captive-browser scripts`. These need
  systemd units, `.desktop` files, or Hyprland/Wayland.
- **macOS only** — `macos` (system preferences via `defaults`).

`pacman/` and `brew/` are tooling, not dotfiles, and are never stowed — they
hold the package lists and `configure-system` scripts for their platform.

On macOS, `bootstrap` also passes `--ignore` for `systemd` and `environment.d`,
so shared packages that happen to ship Linux units (`herdr`, `ssh`) don't
symlink dead directories into `~/.config`.

### macOS notes

- **Homebrew and PATH.** `brew shellenv` runs in *both* `.zshenv` and
  `.zprofile`, deliberately. `.zshenv` covers non-login shells (scripts, git
  hooks, editors); `.zprofile` re-asserts it because `/etc/zprofile` runs
  `path_helper` *after* `.zshenv` and would otherwise leave `/opt/homebrew/bin`
  ranked below `/usr/bin`.
- **Tailscale** installs from a `.pkg` and needs an interactive `sudo`, so
  `brew bundle` aborts on it in a non-interactive run. Install it separately.
- A few configs carry Linux-only keys that are simply inert here (Ghostty's
  `gtk-toolbar-style` and `async-backend`, for instance) — they validate clean
  on macOS, so the files are not split.

## Packages

| Package | Description |
|---------|-------------|
| `brew` | macOS Brewfile, install script, and system configuration |
| `codex` | Codex CLI skills. Symlinks into the `claude` package so there is one copy per skill. Stow it `--no-folding` |
| `gh` | GitHub CLI configuration and custom commands |
| `ghostty` | Ghostty terminal emulator configuration (kept, no longer the default) |
| `git` | Git configuration and global ignore patterns |
| `helium` | The `youtube-no-shorts` unpacked Chromium extension. Stow it **folded** (plain `stow helium`), then run `pacman/configure-system` — see `helium/README.md` |
| `hypr` | Hyprland compositor (keybindings, monitors, autostart, appearance) |
| `kitty` | Kitty terminal emulator configuration, the default terminal. Stow it `--no-folding` |
| `macos` | macOS system preferences (`macos-defaults`) |
| `pacman` | Arch Linux package lists, install script, and system configuration |
| `ripgrep` | ripgrep configuration |
| `sqlite` | SQLite configuration |
| `starship` | Starship prompt configuration |
| `tmux` | Tmux configuration |
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
