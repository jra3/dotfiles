# typora

Typora theme and user scripts. Linux-only (macOS keeps themes under
`~/Library/Application Support/abnerworks.Typora/`). Stow it `--no-folding`:
on a fresh machine `~/.config/Typora` doesn't exist yet, and folded, Typora's
caches and session state would land in this repo.

## Theme: `tokyo-night.css`

Omarchy's tokyo-night palette, CaskaydiaMono Nerd Font throughout. Layout knobs
(`--content-width`, `--base-size`, `--line-height`, `--block-gap`, the font
variables) are the first `:root` block.

## User scripts

Typora has no user-script hook. `system/typora-inject-user-scripts` adds one tag
to `/usr/share/typora/resources/window.html`:

```html
<!-- jra3:user-scripts --><script src="typora://app/userData/user-scripts/init.js" defer></script>
```

`typora://app/userData/` is `~/.config/Typora/` (Typora loads themes through the
same mapping). `init.js` loads the rest, so a new script means one line in its
list, not another root patch.

| Script | Does |
|---|---|
| `frontmatter-highlight.js` | Colors YAML front matter keys, values, URLs, literals. Typora renders front matter as one text node, so this uses the CSS Custom Highlight API (no DOM changes; the block is editable and Typora saves from its text). Colors are the theme's `::highlight(fm-*)` rules |
| `theme-live-reload.js` | Applies theme edits within ~0.5 s, no restart: reads the changed CSS from disk into a `<style>` that replaces Typora's `<link>` (Typora's own reload, `File.setTheme`, serves the cached copy) |

Highlights are editor-only: HTML/PDF export does not run the scripts, so
exported front matter is plain.

### Install (root, once per machine)

`window.html` belongs to the `typora` package and every upgrade replaces it, so
a pacman hook re-runs the injector:

```sh
sudo install -Dm755 typora/system/typora-inject-user-scripts /usr/local/bin/typora-inject-user-scripts
sudo install -Dm644 typora/system/typora-user-scripts.hook /etc/pacman.d/hooks/typora-user-scripts.hook
sudo /usr/local/bin/typora-inject-user-scripts
```

Then restart Typora. Both files are **copied**, not linked: the hook runs as
root, and a root hook executing a file in this repo would let anything that can
write to `$HOME` run code as root. Re-run the `install` lines after editing
either file.

Check it: `grep -c jra3:user-scripts /usr/share/typora/resources/window.html`
should print `1`. With Help → Enable Debugging, the devtools console logs
`theme-live-reload: applied tokyo-night.css` after a theme edit. Scripts also
log to `~/.config/Typora/user-scripts.log`.

To undo: delete the hook and `/usr/local/bin` copy, then `sudo pacman -S typora`
to restore a stock `window.html`.
