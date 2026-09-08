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
`shared.conf`, so the font menu no longer reaches kitty (same trade-off as
`ghostty/`).

## SSH and TERM

Kitty sets `TERM=xterm-kitty`. A host without that terminfo mangles keys and
colours; paperweight was one on 2026-09-08 (it has ghostty's entry, not kitty's).
`.zshrc` aliases `ssh` to `kitten ssh` when the shell is running inside kitty,
which copies the terminfo into `~/.terminfo` on the remote on first connect, no
root needed. The permanent fix on an Arch host is `pacman -S kitty-terminfo`.

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

## Applying changes

`omarchy restart terminal` sends SIGUSR1, which makes running kitty windows
reload `kitty.conf` and everything it includes.
