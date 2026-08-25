# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a GNU Stow-managed dotfiles repository for an Omarchy system (DHH's Arch Linux + Hyprland distribution). Each top-level directory is a "stow package" that mirrors the home directory structure.

**Claude skill:** Use `/omarchy` for help with Hyprland config, keybindings, monitors, themes, input devices, or any `~/.config/hypr/` files. Omarchy 4 also ships its own skill at `$OMARCHY_PATH/default/agents/skills/omarchy/`, which tracks the current release — prefer it when the two disagree.

**This system runs Omarchy 4 ("Quattro"), upgraded 2026-08-23.** See the section below: pre-4 habits actively mislead.

## Omarchy 4 (Quattro)

**Omarchy is a pacman package now.** It lives at `/usr/share/omarchy`, root-owned —
not a git clone you can `git pull`. `~/.local/share/omarchy` is a compat symlink, so
old paths still resolve, but prefer `$OMARCHY_PATH` (Hyprland exports it). Per-machine
state moved from `~/.config/omarchy/` to `~/.local/state/omarchy/`, the current theme
included.

**Hyprland is configured in Lua.** `~/.config/hypr/hyprland.lua` is the entry point;
a `.conf` is read only when no `.lua` exists. Every Omarchy default under
`$OMARCHY_PATH/default/hypr/` is `.lua`. The `hypr/` package was converted
2026-08-23 — the old `.conf` files are in git history.

- API stubs, authoritative: `/usr/share/hypr/stubs/hl.meta.lua`
- Omarchy's `o.*` helpers: `$OMARCHY_PATH/default/hypr/helpers.lua`
- Validate every change: `hyprctl reload && hyprctl configerrors`

**Binding an already-bound key does not override it — both bindings fire.** Call
`hl.unbind(...)` first. `hl.unbind` matches the modifier string *literally* while
`o.bind` normalizes it, so `"SUPER + ALT + SHIFT + E"` will not unbind a key Omarchy
registered as `"SUPER + SHIFT + ALT + E"`; you get two live bindings and no error.
List what is actually bound with `omarchy menu keybindings --print`.

**`hyprctl dispatch` takes a Lua dispatcher.** `hyprctl dispatch togglespecialworkspace foo`
is a parse error; write `hyprctl dispatch 'hl.dsp.workspace.toggle_special("foo")'`.
Likewise `focuswindow` becomes `hl.dsp.focus({ window = "class:^(emacs)$" })`.

**waybar, mako, walker, swayosd, hyprlock and hypridle are all gone**, replaced by a
single Quickshell process (`quickshell -p $OMARCHY_PATH/shell`) covering bar,
notifications, launcher, OSD, lock and idle. Bar layout is `~/.config/omarchy/shell.json`.
Indicators are hidden while inactive unless hovered or given `alwaysShow` on
`omarchy.indicators`.

### Omarchy tools rewrite stowed files in place

Several Omarchy commands persist a setting with `sed -i` on a file in `~/.config`.
`sed -i` replaces a symlink with a regular file, so the file silently drops out of
stow and the repo stops being the source of truth. Seen during the Quattro upgrade:

| File | Written by |
|---|---|
| `~/.config/tmux/tmux.conf` | upgrade migration |
| `~/.config/xdg-terminals.list` | terminal picker |

After changing anything through an Omarchy menu, check the file with `ls -l` and
`stow -R <package>` if it became a regular file.

`~/.config/hypr/monitors.lua` used to be on that list — the display menu
(`omarchy-hyprland-monitor-scaling`) rewrites it. It was un-stowed on 2026-08-25 and is
now host-local by design: displays and scale are per-machine, and a single shared file
could only hold one scale. There is no longer a symlink there to clobber, so the menu
is free to write it. See `hypr/README.md` for what the shared version knew — including
why a hardcoded mode on `eDP-1` segfaults Hyprland at startup.

### `omarchy-emacs-setup` moves `~/.emacs.d` aside — say no

The personal Emacs config is a literate `config.org` in `~/.emacs.d`, its own repo
(`github.com/jra3/dot-emacs`). It is **not** stow-managed and not in this repo.

`omarchy-emacs-setup` wants Emacs to read `~/.config/emacs/`, and `~/.emacs.d` takes
precedence over that, so it prompts `Move ~/.emacs.d to ~/.emacs.d.bak? [y/N]`.
Answering `y` — as happened during the Quattro upgrade on 2026-08-23 — leaves Emacs
booting Omarchy's 9-line default init and every personal binding silently gone. The
config is not deleted, just renamed; move it back. **Answer `N`.** An Omarchy upgrade
can re-run this, so re-check `~/.emacs.d` after one.

The cost of declining is only Omarchy's theme/font syncing. To have both, load
`/usr/share/omarchy-emacs/config/omarchy.el` from the personal config instead.

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

# Deploy a package without directory folding
stow --no-folding <package>
```

**Directory folding gotcha:** when only one package provides a directory, stow
replaces the whole directory in `$HOME` with a symlink into the repo rather than
symlinking each file. That breaks systemd drop-ins — systemd silently ignores a
drop-in directory that is a symlink, and the failure is quiet (`systemctl --user
show <unit> -p DropInPaths` comes back empty). Folding only happens when the target
directory doesn't already exist, so it bites on a fresh machine. No package
currently ships a drop-in; the `emacs` one did until 2026-08-24. Any future one
needs `--no-folding`.

## Default Software

This documents the default software stack configured in Omarchy:

| Category | Software | Description |
|----------|----------|-------------|
| Shell | **zsh** | Default shell with XDG-compliant config |
| Prompt | **Starship** | Cross-shell prompt with git integration |
| Terminal | **Ghostty** | GPU-accelerated terminal (CaskaydiaMono Nerd Font). Omarchy 4 defaults to foot; `ghostty/.config/xdg-terminals.list` is what keeps `SUPER+ENTER` on Ghostty |
| Multiplexer | **tmux** | Terminal multiplexer. Config only — worktrees are Omarchy's `ga`/`gd`, workspaces are `herdr` |
| Compositor | **Hyprland** | Wayland tiling compositor, configured in **Lua** |
| Desktop shell | **Omarchy shell** | One Quickshell process: bar, notifications, launcher, OSD, lock, idle. Replaced waybar, mako, walker, swayosd, hyprlock, hypridle |
| Browser | **Helium** | Web browser |
| Editor | **Emacs** | Text editor. No daemon: `emacs` is aliased to `emacs -nw` in the shell, `SUPER+SHIFT+E` opens a GUI frame |
| AI | **Claude Code** | AI-powered coding assistant |
| VCS | **Git** | Version control with custom aliases |
| GitHub | **gh** | GitHub CLI with `gh prs` for PR listing |
| Search | **ripgrep** | Fast recursive grep |
| Worktrees | **Omarchy `ga`/`gd`** | Shell fns from `$OMARCHY_PATH/default/bash/fns/worktrees`, sourced in `.zshrc`. `ga <branch>` creates `../<repo>--<branch>` and cds in; `gd` removes the current one. Replaced `gtr` on 2026-08-24 |
| Database | **SQLite** | Database with custom config |
| Passwords | **Bitwarden** | Password manager with CLI (`bw`), via `bw-pick`. 1Password and KeePassXC are deliberately **not** installed (removed 2026-08-23) |
| Dictation | **voxtype** | Push-to-talk voice-to-text; `large-v3-turbo` on Vulkan |
| Packages | **pacman/yay** | Arch package manager (package lists tracked) |

## Architecture

**Stow packages** - Each directory is independent and can be deployed separately:
- `zsh/` - Shell configuration (XDG-compliant)
- `git/` - Git config, global ignore patterns, SSH commit signing (`allowed_signers` + `setup-git-signing`)
- `ghostty/` - Ghostty terminal emulator, plus `xdg-terminals.list` — the file `xdg-terminal-exec` reads to pick Ghostty over Omarchy 4's foot default
- `hypr/` - Hyprland compositor. `.lua` since Quattro (`hyprland`, `input`,
  `bindings`, `looknfeel`, `autostart`), plus the two `.conf` files read by *other*
  processes and so untouched by `hyprctl`: `hyprsunset.conf` (apply with
  `omarchy restart hyprsunset`) and `xdph.conf` (applies on portal restart).
  **`monitors.lua` is deliberately not here** — displays are host-local; see
  `hypr/README.md`
- `ripgrep/` - ripgrep configuration
- `sqlite/` - SQLite configuration
- `starship/` - Starship prompt configuration
- `tmux/` - tmux terminal multiplexer (config only; the `tn`/`twt` session scripts
  were removed 2026-08-24, unused since Dec 2025 and superseded by `ga`/`herdr`)
- `herdr/` - herdr terminal workspace manager (annotated default config). The binary
  is not stow-managed: it is the `herdr` package from **Omarchy's own pacman repo**
  at `/usr/bin/herdr`. Never the AUR `herdr-bin` — same binary, same version,
  `Provides: herdr`, so it only offers to replace the repo package and drops herdr
  off Omarchy's upgrade path. See `herdr/README.md`
- `gh/` - GitHub CLI config and `gh-prs` script
- `lazygit/` - lazygit TUI config with `gh stack` stacked-diff custom commands
  (needs the `github/gh-stack` gh extension; `gh extension install github/gh-stack`)
- `claude/` - Claude Code settings and custom commands
- `ccstatusline/` - Claude Code status line: the `ccstatusline` layout plus the `cc-pr-widget` PR/CI segment it shells out to; see `ccstatusline/README.md`
- `slack/` - `slack://` deep-link handler that opens links in the browser (no desktop Slack app); see `slack/README.md`
- `bitwarden/` - Bitwarden CLI helper script (`get-signature`) for extracting attachments
- `pacman/` - Arch package lists and `configure-system` for post-install setup
- `voxtype/` - Dictation config (`large-v3-turbo`, meeting capture) and `meeting-toggle`.
  The daemon and its `voxtype.service` are installed by `voxtype setup systemd`, not stowed
- `webapps/` - `.desktop` entries: `Hidden=true` stubs that suppress Omarchy's
  preinstalled web apps, plus real entries for our own. Omarchy upgrades reinstate
  the ones we hide, so re-stow after an upgrade. The stubs also shadow unwanted
  entries from *pacman* packages, which is the only way to suppress a root-owned
  `/usr/share/applications/` file that an upgrade would otherwise restore — the
  three `emacs*` stubs leave `emacs.desktop` as the sole Emacs launcher entry
- `qmk/` - Optional: host side of a Framework 16 ANSI keymap — the `qmk-mic-led-sync.py` daemon syncing mic/DND/voxtype/pomodoro state over raw HID, and `qmk-flash.py` for reflashing. The firmware half is a separate repo, `jra3/qmk_firmware` branch `fw16-john` at `~/jra3/qmk_firmware`; see `qmk/README.md`
- `tether/` - **TODO: broken by Omarchy 4.** `waybar-iphone-tether` writes waybar JSON,
  and waybar no longer exists. Needs either an existing Omarchy shell plugin for
  USB tethering or a Quickshell one written against
  `$OMARCHY_PATH/shell/plugins/bar/indicators/` (see `Dictation.qml` for the shape:
  a `BarIndicator` polling a script that streams bar-friendly JSON). The script
  itself still detects the tether correctly — only the presentation layer is gone.
  See `tether/README.md`. The `.network` file and `usbmuxd` are handled by
  `pacman/configure-system` + `packages-arch.txt`

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

## Git commit signing (per-machine YubiKey, on)

**Signing is on** — `commit.gpgsign = true` in the `git/` package. Skip it for one
commit with `git -c commit.gpgsign=false commit`.

It was off from 2026-08-02 (`aaf5553`) to 2026-08-21, because an `sk-` (FIDO2)
key that wants a touch fails in any non-interactive context. **Whether it wants
one is per-machine, and the two machines measured disagree:**

| Machine | gitsign flags | Signs unattended? | Measured |
|---|---|---|---|
| chonky | `0x21` | no, prompts `Confirm user presence` | 2026-07-28, `yubikey-ssh.md` |
| am-jallen | `0x20` | yes, `git commit -S` with stdin closed exits 0 and verifies `G` | 2026-08-21, GTD-38 |

`setup-git-signing` asks for no-touch/no-PIN, and am-jallen's key kept it.
chonky's did not, because a `-K` recovery hands back a `0x21` stub and silently
reintroduces the touch. Read the flags byte on each machine; do not trust either
this file or the key's provenance. `yubikey-ssh.md` has the decoding recipe.

So: on a `0x20` machine, signing costs nothing and agents are fine. On a `0x21`
machine, an unattended session hangs on every commit, and `git rebase --exec`
stops mid-rebase and leaves you detached, which reads like lost commits. Fix the
flags byte rather than turning signing off globally.

Either way the token has to be in the port. A container, or a machine with the
Nano pulled, fails at signing time.

The per-machine key setup below applies to every machine that signs.
Config is shared via the `git/` package (`gpg.format=ssh`, `user.signingkey` → a
canonical key path), but **each machine has its own signing key on its own
YubiKey**:

1. On a new machine, run `setup-git-signing` (from `git/.local/bin/`, on `$PATH`).
   It generates a resident no-touch/no-PIN `sk-ed25519` key at
   `~/.ssh/id_ed25519_sk_gitsign`, registers it in `allowed_signers`, and uploads
   it to GitHub as a signing key. Idempotent.
2. Commit the updated `allowed_signers` so other machines can verify this one's
   commits.

`allowed_signers` accumulates one line per machine. Both identities
(`github@porcnick.com` personal, `john@antimetal.com` work) share each key.
Since `commit.gpgsign` is `true`, run `setup-git-signing` before committing on a
new machine, or every `git commit` fails with no signing key. Until then, commit
with `git -c commit.gpgsign=false commit`.
