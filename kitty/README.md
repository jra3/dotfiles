# kitty

Stow package for the Kitty terminal, default since 2026-09-08 (ghostty 1.3.1-2
segfaults its io thread whenever herdr attaches; fixed upstream in August 2026 but
not yet in the Arch package). **Stow it `--no-folding`:** `omarchy font set` and
`omarchy display text size` both `sed -i` into `~/.config/kitty/`, and a folded
directory would put those writes straight into this repo.

## Layout

| File | Where | Why |
|---|---|---|
| `.config/kitty/shared.conf` | stowed | everything shared between hosts |
| `.config/kitty/tab_colors.py` | stowed | per-tab colours by running command (see *Tab colours*) |
| `.config/xdg-terminals.list` | stowed | tells `xdg-terminal-exec` (SUPER+ENTER, `omarchy launch terminal`) to use kitty. The terminal picker (`omarchy default terminal`) rewrites it with `cat >`, which writes *through* the symlink, so the repo copy changes and the switch shows up in `git status` |
| `~/.config/kitty/kitty.conf` | host-local, **not** stowed | holds `font_size` and includes `shared.conf` |

## Host-local kitty.conf

Omarchy's installer drops its default at this path; replace it by hand on a new
machine with:

```
# Host-local, deliberately NOT stowed — `omarchy display text size` persists the
# terminal size by running sed -i on this exact path, which would clobber a
# symlink. Everything shared is in shared.conf (stowed from ~/.dotfiles/kitty).
# Kitty applies later lines over earlier ones, so with the include last
# shared.conf wins on any key present in both — keep only host-only keys
# (font_size) here.
font_size 12.0
include ~/.config/kitty/shared.conf
```

`omarchy display text size` matches `^font_size[[:space:]]+` in this file and
`omarchy font set` matches `^font_family ` — the family is pinned in
`shared.conf`, so the font menu no longer reaches kitty (the same trade-off the
retired `ghostty/` package made).

**The size menu now opens on the wrong number.** `omarchy-display-text-size`
*writes* every terminal config that exists, kitty included, but its
`term_current_pt` reads back the first one it finds in a fixed order:
ghostty, alacritty, kitty, foot. Removing `~/.config/ghostty/config` promoted
`~/.config/alacritty/alacritty.toml` to that slot, and alacritty is still
installed (it is in `packages-arch.txt`, unused). The two agree at 11 today, so
nothing is visibly wrong; they diverge the moment anything sets one without the
other. Delete `~/.config/alacritty/` — or drop `alacritty` from
`packages-arch.txt` — if the menu ever reports a size kitty is not using.

The canonical size for a display is whatever `term_current_pt` computes:
`round(shell_px * 9 / 12)`, where `shell_px` is the bar font size that
`omarchy display text size` also drives, and which GTK's `text-scaling-factor`
tracks. On the LG SDQHD (2560x2880, Hyprland scale 1.6, factor 1.1818) that is
11 — the value every terminal here holds. If 11 nonetheless renders larger or
smaller than ghostty did at 11, that is kitty and ghostty disagreeing about
points-per-pixel under fractional scaling, not a misconfiguration: change
`font_size` in the host-local `kitty.conf` and leave the other terminals alone.
`ctrl+shift+=` / `ctrl+shift+-` adjust a running window live (2.0pt steps) and
`ctrl+shift+backspace` resets to the configured value, which is the quickest way
to find the number worth persisting. Kitty 0.48 has no remote-control command
that reports the live size back, so read it off the screen.

## SSH and TERM

Kitty sets `TERM=xterm-kitty`, and a remote host without that terminfo entry
mangles keys and colours. Fix it once per remote, either with
`pacman -S kitty-terminfo` there (the `kitty` package pulls it in as a hard
dependency, so any host in `packages-arch.txt` already has it) or by connecting
once with an explicit `kitten ssh <host>`, which copies the entry into the
remote's `~/.terminfo` and needs no root.

An interactive kitty shell takes the second route on its own: `zsh/.zshrc`
defines an `ssh()` function that routes through the kitten. Inside herdr or tmux
the multiplexer owns `TERM`, so the guard is off there and you get plain `ssh`.

**Do not alias `ssh` to `kitten ssh`.** Omarchy's `fns/ssh-reconnect` defines an
`ssh()` *function* — it reconnects a dropped link and disarms the mouse-tracking
and alternate-screen modes a killed remote tmux leaves armed — and
`~/.zshrc.local` sources that whole `fns/` directory. zsh expands aliases while
parsing a function definition, so any `alias ssh=...` anywhere turns that file
into `defining function based on alias 'ssh'` plus a parse error, in every new
shell. Ordering does not help; the alias loses either way, and the reconnect
wrapper is worth more than saving a one-time-per-host setup step. (An earlier
draft of this file claimed the alias existed. It was added on 2026-09-08, broke
every shell immediately, and was reverted the same day.)

## Splits are unbound

kitty calls splits "windows", and none are used here — herdr owns layout, and every
herdr tab holds exactly one pane too. `shared.conf` therefore `no_op`s kitty's entire
window group (2026-09-08): `ctrl+shift+enter`, `ctrl+shift+[`/`]`, `ctrl+shift+f`/`b`,
``ctrl+shift+` ``, `ctrl+shift+r`, `ctrl+shift+l` (layouts only arrange splits),
`ctrl+shift+f7`/`f8`, and `ctrl+shift+0` (`tenth_window`).
`close_window` (`ctrl+shift+w`) was already redirected to `close_tab`.

`first_window`..`ninth_window` (`ctrl+shift+1`..`9`) are unbound too, but by reuse
rather than `no_op`: tab switching moved onto those keys in the Tabs section of
`shared.conf`. It lived on `alt+1`..`9` until 2026-09-08, where it shadowed herdr's
`focus_agent = "prefix+alt+1..9"` — kitty dispatches its own shortcuts before the key
reaches the app, in every context, including after herdr's prefix. Freeing `alt+N` made
those agent jumps work for the first time. **Do not add `no_op` lines for
`ctrl+shift+1`..`9`**: they would sit later in the file than the `goto_tab` maps and the
last map for a key wins.

`ctrl+shift+escape` is the exception: it opens kitty's debug shell, whose default target
is a split, so it is re-pointed at `kitty_shell overlay` rather than unbound — same
feature, no split. `ctrl+shift+n` (`new_os_window`) is untouched: a whole OS window, not
a split.

`no_op` removes the mapping **and lets the key through to the app**, rather than
swallowing it: `options/utils.py` rewrites `no_op` to an empty definition, and
`boss.py combine()` early-returns `consumed = False` on one. A later `map` for the same
key wins over an earlier one (`keys.py matching_key_actions` ends with
`matches = [matches[-1]]`), which is also why the `close_tab`/`close_os_window` swap
above works.

**Comments must be on their own line for a `map` line.** kitty takes the whole rest of
the line as the action, so `map ctrl+shift+f no_op  # move_window_forward` parses the
action as `no_op  # move_window_forward`, which is not the `no_op` literal and so does
not unbind anything.

Verify with kitty's own parser rather than by eye — `kitty +runpy` with no path loads
*only* the defaults, so pass the real file:

```bash
kitty +runpy '
from kitty.config import load_config
o = load_config("/home/john/.config/kitty/kitty.conf")
km = o.keyboard_modes[""].keymap
for k, defs in km.items():
    ds = [d.definition for d in defs]
    if any("window" in x or "layout" in x for x in ds):
        print(k, "=>", ds)
'
```

Each unbound key should print as `['<action>', '']` — the trailing `''` is the one that
wins.

## Tab colours

Two layers, because tabs are coloured from two places.

**All tabs, statically**, in the Tabs block of `shared.conf`. kitty's inactive
defaults are `#444` on `#999` — 3.4:1, under the 4.5:1 WCAG AA floor, and the
reason an inactive title is hard to read. They are pinned to Tokyo Night's
`selection_background` and `foreground` (6.4:1). These are literal values, so
the theme include at the top of `shared.conf` no longer drives them and
`omarchy theme set` leaves them behind — the same trade-off `font_family`
already takes. Omarchy's `kitty.conf.tpl` writes exactly one tab key,
`active_tab_background`, so nothing here fights it. A
`~/.config/omarchy/themed/kitty.conf.tpl` would keep theme tracking, at the cost
of living outside this repo.

**One tab at a time**, from `tab_colors.py`, wired up by `watcher` in
`shared.conf`. kitty fires `on_cmd_startstop` for every command when shell
integration is on (`no-cursor` still counts — that value only declines the
cursor-shape changes), so the watcher recolours a tab when herdr starts in it
and reverts when herdr exits. No polling, no shell wrapper, and it does not care
how herdr was invoked. Rules live in the `RULES` dict, keyed by command name.

Colours are four `int|None` attributes on the Tab object — the same ones
`kitten @ set-tab-color` assigns — so the watcher sets them directly instead of
shelling out to the remote-control socket on every prompt.

Two limits are worth knowing before debugging a rule that "doesn't work", both
measured on 0.48.2:

* **Watcher modules are cached per kitty process**, in `launch.py`'s
  `watcher_modules` dict, keyed by resolved path. Editing `tab_colors.py` and
  sending SIGUSR1 does *not* reload it; nor does opening a new tab. Only a new
  kitty process picks up the edit.
* **Watchers attach at window creation.** A config reload reaches only windows
  made after it, and a tab that already had herdr running when kitty started
  never saw a start event. Paint those by hand once:

  ```bash
  kitten @ set-tab-color --match id:<tab> \
    active_fg=#1a1b26 active_bg=#f7768e inactive_fg=#f7768e inactive_bg=#3d2430
  ```

Both limits go away under `tab_bar_style custom`, where a draw-time `tab_bar.py`
sees every tab on every frame. That is the next step if the rules grow past
"colour it by what is running".

## Ghostty

The `ghostty/` stow package was removed on 2026-09-08, and `~/.config/ghostty/`
with it. It had the identical host-local/shared split (`config` held `font-size`
and a `config-file` include of a stowed `shared.conf`), so git history before that
date is the reference if the arrangement ever needs recovering. `ghostty` also came
out of `pacman/packages-arch.txt`; the binary is left installed on hosts that
already have it, as a fallback with stock defaults.

## Applying changes

`omarchy restart terminal` sends SIGUSR1, which makes running kitty windows
reload `kitty.conf` and everything it includes.
