# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a GNU Stow-managed dotfiles repository targeting **two platforms**: an
Omarchy system (DHH's Arch Linux + Hyprland distribution) and **macOS**. Each
top-level directory is a "stow package" that mirrors the home directory
structure.

Most packages are shared. `./bootstrap` knows which are Linux-only (systemd
units, `.desktop` files, Hyprland) and which are macOS-only, and stows only what
applies — run `./bootstrap --list` to see the split for the current machine.
**When adding a package, add it to one of the three lists at the top of
`bootstrap`**, or it will never be deployed.

Platform-specific tooling lives in two non-stowed directories that mirror each
other: `pacman/` (`install-packages`, `configure-system`, package lists) and
`brew/` (`install-packages`, `configure-system`, `Brewfile`).

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
| `~/.config/kitty/kitty.conf` | `omarchy display text size`, `omarchy font set` (never stowed: the file is host-local, shared bits live in `shared.conf` — see the `kitty/` entry. Same arrangement `~/.config/ghostty/config` had before ghostty was retired on 2026-09-08) |

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

## Helium extensions are force-installed by policy

Helium reads Chromium's policy directory, `/etc/chromium/policies/managed/*.json`
— the only policy path in the binary, and it opens every file there at startup.
Omarchy creates that directory in `install/config/theme-system.sh` and `chmod
a+rw`s it so `omarchy theme set` can write `color.json` unprivileged.
`configure-system` adds `extensions.json`, force-installing these into every
Helium profile on the machine:

| Extension | ID |
|---|---|
| floccus — bookmark sync | `fnaicdffflnofjppbagibeoednhnbjhg` |
| Fluff Busting Purity — Facebook feed cleanup | `nmkinhboiljjkhaknpaeaicmdjhagpep` |

**That `a+rw` does not always survive.** On 2026-09-14 the directory was found
`root:root 755` holding only `color.json`, with no `extensions.json` at all and
floccus reduced to an empty husk (`{}`) in the profile — i.e. silently not
installed for some time. `configure-system` falls back to `sudo tee` when the
directory isn't writable, so it recovers, but nothing warns you that it regressed.
If an extension goes missing, check this directory first.

**The `?prodversion=` on the update URL is load-bearing.** Helium is
ungoogled-chromium-based and strips `prodversion` from Chrome Web Store update
requests; the store answers `<updatecheck status="noupdate"/>` to any request
that omits it. So a plain `<id>;https://clients2.google.com/service/update2/crx`
forcelist entry fails for *every* extension, and fails silently — nothing appears
in the UI, and the only trace is `failed to install … no_update_info: 1` under
`--vmodule='*extension*=2'`. Chromium appends its own query params to whatever
update URL it is handed, so carrying `prodversion` in the URL puts it back on the
wire. Verified 2026-08-31 (floccus 5.10.3) and again 2026-09-14 at
`prodversion=152.0.7977.82`: floccus 5.10.3 and F.B. Purity 38.4.0.0 both install
into a fresh profile, `location 7`, no disable reasons.

The pinned version only has to be >= the extension's `minimum_chrome_version`, so
a stale pin keeps working; re-run `configure-system` after a Helium upgrade to
refresh it. Note that policy installs the extension but **not its settings** —
floccus's sync account and F.B. Purity's options panel both stay per-machine
setup. Adding another extension means adding one `id|description` line to the
`helium_extensions` array in `configure-system`.

## Common Commands

```bash
# Deploy everything appropriate for THIS platform (preferred entry point)
./bootstrap
./bootstrap --list      # show the stow/skip split, change nothing
./bootstrap --dry-run   # full preview

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

The reverse also bites: `helium/` **must** be folded, because Chromium will not
load extension resources that resolve outside the extension root. See its README.

**Drop-ins are not the only victim.** Folding also means any tool that writes into
that directory writes *into the repo*, with nothing in `ls -l` to reveal it — the
file is genuinely a regular file, because the symlink is one level up. On 2026-08-25
`voxtype setup` rewrote the stowed `~/.config/voxtype/config.toml` this way: `model`
reverted to `base.en` and the whole `[meeting]` block vanished, silently, in the
tracked file. Unfolded it would have replaced the *symlink* instead, leaving the repo
intact and the drift visible. So `--no-folding` applies to any directory an external
tool writes to, not just drop-in dirs.

## Default Software

This documents the default software stack configured in Omarchy:

| Category | Software | Description |
|----------|----------|-------------|
| Shell | **zsh** | Default shell with XDG-compliant config |
| Prompt | **Starship** | Cross-shell prompt with git integration |
| Terminal | **kitty** | GPU-accelerated terminal (CaskaydiaMono Nerd Font), default since 2026-09-08. Omarchy 4 defaults to foot; `kitty/.config/xdg-terminals.list` is what keeps `SUPER+ENTER` on kitty. Replaced Ghostty, whose 1.3.1-2 segfaults its io thread whenever herdr attaches (fixed upstream Aug 2026, not yet packaged) |
| Multiplexer | **tmux** | Terminal multiplexer. Config only — worktrees are Omarchy's `ga`/`gd`, workspaces are `herdr` |
| Compositor | **Hyprland** | Wayland tiling compositor, configured in **Lua** |
| Desktop shell | **Omarchy shell** | One Quickshell process: bar, notifications, launcher, OSD, lock, idle. Replaced waybar, mako, walker, swayosd, hyprlock, hypridle |
| Browser | **Helium** | Web browser. Its flags file and the `youtube-no-shorts` extension are the `helium/` package |
| Files | **Nautilus** | GNOME Files, the `inode/directory` default. Sidebar shortcuts are `gtk/.config/gtk-3.0/bookmarks` |
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
- `gtk/` - GTK bookmarks (the Nautilus sidebar, and every GTK file chooser),
  plus `setup-inbox` — which creates `~/jra3/inbox` and sets its icon. Stow it
  `--no-folding`: GTK writes into `~/.config/gtk-3.0/`. The bookmark is
  declarative but its **sidebar** icon is not settable at all, and the file-view
  icon is gvfs metadata rather than a file, so it is applied per machine by
  `configure-system`. See `gtk/README.md`
- `kitty/` - kitty terminal emulator, the default since 2026-09-08, plus
  `xdg-terminals.list` — the file `xdg-terminal-exec` reads to pick kitty over
  Omarchy 4's foot default. **Stow it `--no-folding`**, because Omarchy writes
  into `~/.config/kitty/` — the same reason as `gtk/`. The stowed file is
  `shared.conf`, not `kitty.conf`: **`~/.config/kitty/kitty.conf` is deliberately
  host-local** — it holds only `font_size` (a per-display answer) and an `include`
  of `shared.conf`. `omarchy display text size` persists by `sed -i` on that exact
  path, so the file Omarchy seds must be a regular file. kitty applies later lines
  over earlier ones, so with the include last never add `font_size` to
  `shared.conf` — it would override every host. Side effect: `omarchy font set`
  seds `font_family` in `kitty.conf` only, so it no longer reaches kitty; the
  family is pinned in `shared.conf` instead. `omarchy default terminal` writes
  `xdg-terminals.list` with `cat >`, which goes *through* the symlink, so a picker
  change lands in the repo as a diff rather than un-stowing the file. Splits are
  unbound (herdr owns layout) and tab switching sits on `ctrl+shift+1..9` so
  `alt+N` reaches herdr. Inside kitty `.zshrc` routes `ssh` through `kitten ssh`
  so remote hosts get the `xterm-kitty` terminfo. See `kitty/README.md`.
  Replaced the `ghostty/` package, removed 2026-09-08; it had the identical
  host-local/shared split, and git history has it if the arrangement needs
  recovering
- `helium/` - One unpacked Chromium extension, `youtube-no-shorts`, which removes
  Shorts from YouTube and redirects `/shorts/` to the normal watch page.
  **`~/.config/helium-browser-flags.conf` is deliberately not here** — it is
  generated per-machine by `configure-system` from Omarchy's
  `chromium-flags.conf` with `~/` expanded to `$HOME` (the wrapper escapes `$VAR`
  and `~` before eval, so a tilde path silently fails to load), and that stanza
  appends this package's extension dirs to Omarchy's `--load-extension` line — so
  a new Omarchy bundled extension is picked up automatically, with no copy to
  drift. Chromium keeps only the last occurrence of a repeated switch, so the
  list cannot be split. Stow this one **folded** — the sole exception to the
  `--no-folding` rule below. Chromium canonicalises extension resources and
  refuses any that resolve outside the extension root, so unfolded the file
  symlinks mean the content scripts are never injected while the manifest and DNR
  rules still load — it looks healthy and blocks nothing. See `helium/README.md`
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
- `codex/` - Codex CLI skills. The skill files themselves live in `claude/`, and
  `codex/.codex/skills/<name>` is a repo-internal symlink to them, so a skill has
  one copy and editing it updates both agents. **Stow it `--no-folding`.**
  `~/.codex` holds live state (`auth.json`, the session and history sqlite dbs), so
  on a fresh machine where the directory does not exist yet, folding would replace
  the whole of `~/.codex` with a symlink into this repo and Codex would write its
  state into your dotfiles. Currently ships `unslop`. Codex reads skills from both
  `~/.codex/skills` and the cross-agent `~/.agents/skills`; confirm what it actually
  loaded with `codex debug prompt-input | grep -o '[^"]*<skill-name>[^"]*'`
- `ccstatusline/` - Claude Code status line: the `ccstatusline` layout plus the `cc-pr-widget` PR/CI segment it shells out to; see `ccstatusline/README.md`
- `slack/` - `slack://` deep-link handler that opens links in the browser (no desktop Slack app); see `slack/README.md`
- `bambu-studio/` - BambuStudio launcher. `bambu-studio-launch` picks `GDK_SCALE` /
  `GDK_DPI_SCALE` from the focused monitor's scale at launch time, because BambuStudio
  forces X11 and Omarchy's XWayland draws at physical pixels. **Never hardcode a scale
  in the `.desktop`** — it is shared across machines with different monitors, and did
  get hand-tuned per machine three times before the script. `--print` shows the env a
  host would get. See `bambu-studio/README.md`
- `bitwarden/` - Bitwarden CLI helpers. `get-signature` (extracts attachments) still
  works. **`bw-pick` is broken by Omarchy 4** — it drives its two-step picker with
  `walker`, which Quattro replaced with the Quickshell launcher, so every invocation
  fails. Its `SUPER + SHIFT + SLASH` binding is commented out in `bindings.lua`
  rather than deleted, so the key stays dead instead of reviving Omarchy's
  1Password binding. To be replaced rather than ported; `rbw` itself is fine and
  the pure helpers still have coverage in `tests/bw-pick.bats`
- `ssh/` - Shared SSH config (`config.shared`, included last so host-local `~/.ssh/config` wins), the ssh-agent loader, and the committed **public** halves of the YubiKey resident auth keys in `.ssh/authorized_keys.d/` — one file per machine, assembled into a host-local `~/.ssh/authorized_keys` by `build-authorized-keys`. Private credentials never leave their YubiKey; see `yubikey-ssh.md`
- `pacman/` - Arch package lists and `configure-system` for post-install setup (not stowed)
- `brew/` - macOS `Brewfile`, `install-packages`, and `configure-system` (not stowed)
- `macos/` - macOS system preferences (`macos-defaults`); macOS-only stow package
- `voxtype/` - Dictation. Only `meeting-toggle` is stowed: **`config.toml` is
  deliberately host-local** — `model` is a per-machine answer and voxtype rewrites the
  file itself (`voxtype setup`, `voxtype config set`). The binary is
  `omarchy/voxtype-bin`; the daemon and `voxtype.service` come from
  `voxtype setup systemd`, not stow. See `voxtype/README.md` for the reference config
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
- `zai/` - z.ai's GLM Coding Plan as a fourth tab in Omarchy's agents panel.
  `omarchy-agent-usage-zai` prints the record contract the panel reads and a
  systemd user timer writes it every 5 minutes — the packaged
  `omarchy-agent-usage-update` only iterates collectors inside
  `$OMARCHY_PATH/bin`, so a user collector can never join its loop. Reads the
  same key as `claude-zai`. See `zai/README.md`

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

Run the `configure-system` for the current platform. Both are idempotent and safe to re-run.

- **Arch:** `pacman/configure-system` — system services (Tailscale operator, Emacs daemon, sshd on the tailnet, power policy, pacman hooks).
- **macOS:** `brew/configure-system` — `~/tmp` (for the `TMPDIR` set in `.zshenv`), `~/.ssh/sockets`, the `~/.ssh/config` → `config.shared` include, the `git-worktree-runner` clone that `gtr` wraps, and the `gh-stack` extension.

The macOS script deliberately does *not* emulate the Arch-only half (systemd units, sshd binding, UPower, xdg-mime). System preference tweaks live separately in `macos-defaults`, which is not called automatically because it restarts Dock and Finder.

## macOS gotchas

**Homebrew must be initialized twice.** `brew shellenv` runs in both `zsh/.zshenv` and `zsh/.zprofile`, and both are load-bearing:

- `.zshenv` is the only one non-login shells read — scripts, git hooks, editors, and Claude Code's Bash tool. Without it they get a `PATH` with no Homebrew at all, which breaks `git`, `tmux`, `rg`, `starship`, and `stow`.
- `.zprofile` is needed because `/etc/zprofile` runs `path_helper` *after* `.zshenv`. `path_helper` rebuilds `PATH` with the system directories first, demoting `/opt/homebrew/bin` below `/usr/bin` so every formula that shadows a system binary silently loses. Re-running `shellenv` from `~/.zprofile` (which zsh reads after `/etc/zprofile`) restores precedence.

Version-manager shims (pyenv, mise) are prepended later in `.zshrc`, so they still land ahead of Homebrew. If you touch `PATH` setup, verify all three invariants:

```bash
/bin/zsh -i -l -c 'echo $PATH | tr ":" "\n" | grep -n "pyenv/shims\|^/opt/homebrew/bin$\|^/usr/bin$"'
# expected order: pyenv shims < /opt/homebrew/bin < /usr/bin
```

**Never hardcode `/opt/homebrew`.** That path is Apple Silicon only; Intel Macs use `/usr/local`. Use `$HOMEBREW_PREFIX` (exported by `shellenv`), as `darwin.zsh` does.

**Ghostty has no OS conditionals**, but it registers Linux-only keys (`gtk-toolbar-style`, `async-backend`) as known fields on every platform, so they validate clean and are ignored on macOS. The config is deliberately *not* split. Check changes with `ghostty +validate-config --config-file=...`. Note Ghostty does **not** support trailing `#` comments — a comment after a value becomes part of the value.

**Tailscale** installs from a `.pkg` requiring interactive `sudo`, so it aborts a non-interactive `brew bundle`. Install it on its own from a real terminal.

## Git commit signing (per-machine YubiKey, on)

**Signing is on** — `commit.gpgsign = true` in the `git/` package. Skip it for one
commit with `git -c commit.gpgsign=false commit`.

It was off from 2026-08-02 (`aaf5553`) to 2026-08-21, because an `sk-` (FIDO2)
key that wants a touch fails in any non-interactive context. **Whether it wants
one is per-machine, and the two machines measured disagree:**

| Machine | gitsign flags | Signs unattended? | Measured |
|---|---|---|---|
| chonky | `0x21` | no, prompts `Confirm user presence` | 2026-07-28, `yubikey-ssh.md` |
| paperweight | `0x20` | yes, `git commit -S` with stdin closed exits 0 and verifies `G` | 2026-08-21, GTD-38 |
| cupcake | `0x20` | yes, same test | 2026-08-25, after a `-K` recovery + patch |

`setup-git-signing` asks for no-touch/no-PIN, and paperweight's key kept it.
chonky's did not, because a `-K` recovery hands back a `0x21` stub and silently
reintroduces the touch. Read the flags byte on each machine; do not trust either
this file or the key's provenance. `yubikey-ssh.md` has the decoding recipe.

**A `0x21` stub is a one-command fix, not a reason to regenerate.**
`ssh-keygen -p` sets FIDO options as well as passphrases, so a recovered key can
be flipped back in place, without the token:

```sh
ssh-keygen -p -O no-touch-required -P "" -N "" -f ~/.ssh/id_ed25519_sk_gitsign
```

This matters on a rebuild. Recovering with `ssh-keygen -K` keeps the machine's
existing key — so its `allowed_signers` line and GitHub registration stay valid,
and every commit it ever signed keeps verifying. Generating a fresh key instead
discards all of that. cupcake was rebuilt this way on 2026-08-25.

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
