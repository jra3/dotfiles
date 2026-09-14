# gtk

GTK bookmarks — the sidebar shortcuts in Nautilus and in every GTK file chooser —
plus `setup-inbox`, the per-machine half of the `~/jra3/inbox` setup.

Stow with `--no-folding`:

```sh
stow --no-folding gtk
```

`~/.config/gtk-3.0/` is a directory GTK writes into (`settings.ini`, and
`bookmarks` itself), so folding it would put those writes inside the repo with
nothing in `ls -l` to show it. See the folding section in the top-level CLAUDE.md.

## bookmarks

`~/.config/gtk-3.0/bookmarks` is one `URI  label` line per sidebar entry, in
sidebar order. GTK 4 apps still read this GTK 3 path.

The file is **co-owned**: adding, removing, renaming or dragging a bookmark in
the GUI rewrites it. That is safe for stow — GTK saves with
`g_file_replace_contents()` and no backup, which writes *through* a symlink
rather than replacing it (verified 2026-08-30), so an edit made in Nautilus lands
in the repo and shows up in `git status` instead of silently un-stowing the file.
Commit it or `git checkout` it.

URIs must be absolute, so `/home/john` is hardcoded. Every machine uses `john`.

## The icon

Two different icons are involved, and only one of them can be set:

| Where | Icon | Controllable? |
|---|---|---|
| File view (grid/list) | `metadata::custom-icon-name` on the folder | yes |
| Sidebar row | generic `folder-symbolic` | **no** |

Nautilus reads `metadata::custom-icon-name` (a themed icon name) and
`metadata::custom-icon` (a `file://` URI, what Properties → pencil sets) through
`NautilusFile`. Its sidebar does not: bookmark rows are drawn from GIO's
`standard::symbolic-icon`, which does not surface those metadata attributes —
`gio info -a standard::symbolic-icon` on a folder with a custom icon still
returns `folder-symbolic`. Confirmed visually on 2026-08-30. Downloads, Pictures
and Videos get distinct sidebar icons because they are XDG user dirs
(`~/.config/user-dirs.dirs`), which the sidebar special-cases by path — not
because of any metadata. The only lever for an inbox sidebar icon would be
pointing an unused XDG dir (`XDG_PUBLICSHARE_DIR`, `XDG_TEMPLATES_DIR`) at it,
which hijacks that directory's meaning for every other app. Not worth it.

The icon that *is* settable is not a file: gvfs keeps it in a binary per-machine
store under `~/.local/share/gvfs-metadata/`, so nothing here can be stowed. Hence
`setup-inbox`, which `pacman/configure-system` calls. Change the icon with

```sh
INBOX_ICON=folder-download setup-inbox
```

Any name in the active icon theme works. `mail-inbox` (the default) is a mail
tray, deliberately unlike the surrounding folders; `folder-download` is a themed
folder with a down arrow that matches the other folders but reads as Downloads.
Both come from `yaru-icon-theme`, which Omarchy installs in its base package set,
and resolve under every Yaru accent (they all inherit `Yaru`).
