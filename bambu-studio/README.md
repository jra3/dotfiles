# bambu-studio — BambuStudio launcher with per-monitor GTK scaling

BambuStudio is the AUR `bambustudio-bin` package (`/usr/bin/bambu-studio` →
`/opt/bambustudio-bin/AppRun`). This package only owns how it is launched.

## Contents

- `.local/bin/bambu-studio-launch` — sets `GDK_SCALE` / `GDK_DPI_SCALE` from the
  focused Hyprland monitor's scale, then execs `/usr/bin/bambu-studio`.
  `bambu-studio-launch --print` shows what this host would get without launching.
- `.local/share/applications/BambuStudio.desktop` — shadows the package's own
  entry (same file name, `~/.local` wins) so the app launcher, `xdg-open` on a
  `.3mf`/`.stl`, and `bambustudio://` links all go through the script.
- `tests/bambu-studio-launch.bats` (repo root) covers the scale maths.

## Why a script, and not a scale in the `.desktop`

**BambuStudio always runs under XWayland.** Its `main()` sets `GDK_BACKEND=x11`
itself (its OpenGL canvas is GLX-only), so a `GDK_BACKEND=wayland` in the
environment is ignored — the launcher carried one for months to no effect.

**Omarchy sets `xwayland.force_zero_scaling = true`**, so XWayland windows are
drawn at physical pixels and the compositor does not scale them. That keeps them
sharp, but it means GTK has to do all the scaling, and GTK on X11 has exactly
two levers:

| Variable | Range | Moves |
|---|---|---|
| `GDK_SCALE` | integer only | the whole layout: widgets, icons, fonts, dialog sizes |
| `GDK_DPI_SCALE` | fractional | fonts only |

wxWidgets on GTK3 treats pixels as DIPs, so BambuStudio's `FromDIP()` layout
follows `GDK_SCALE` and nothing else: with `GDK_SCALE=2` the Setup Wizard is
1312×1056 logical px, with `GDK_SCALE=1` it is 656×528, whatever `GDK_DPI_SCALE`
says. Fractional scaling of the layout is simply not available.

**Fonts bigger than the layout truncate.** Tried on cupcake (1.25):
`GDK_SCALE=1 GDK_DPI_SCALE=1.25` gives right-sized text but the sidebar
labels become `Recently Op…`, `Maker's …`, `User Man…`, because Bambu sizes
those controls in DIPs. Fonts smaller than the layout only add padding. Hence
the rule in the script:

```
GDK_SCALE     = round(monitor scale)          # Omarchy's own convention
GDK_DPI_SCALE = min(1, monitor scale / GDK_SCALE)
```

| Monitor scale | Host | `GDK_SCALE` | `GDK_DPI_SCALE` | Result |
|---|---|---|---|---|
| 1.25 | cupcake | 1 | 1 | sharp, everything 80% of the rest of the desktop |
| 1.6 | chonky, paperweight | 2 | 0.8 | sharp, layout 125%, text at true size (not yet tried there) |
| 2 | — | 2 | 1 | sharp, exact |

**The `.desktop` file is shared, monitors are not.** The `Exec` line was
hand-tuned three times (`1/1.25`, none, `2/0.85`) — each right for the machine
it was edited on and wrong on the others. On cupcake the `2/0.85` version drew
everything at 2× on a 1.25× screen; the Setup Wizard was taller than the
display. Computing at launch time is the only version that is right everywhere.

**Don't read the session's `GDK_SCALE` either.** Omarchy imports Hyprland's env
into systemd/dbus once, at Hyprland startup (`autostart.lua`). Change
`monitors.lua` and `hyprctl reload`, and the session keeps the old value until
the next login — cupcake's `monitors.lua` said 1 while every app launched from
the shell still got 2. The script asks `hyprctl monitors` instead.

## The alternative, if 80% is too small on a 1.25 host

Set `xwayland = { force_zero_scaling = false }` in `hyprland.lua`. XWayland then
renders at 1× and Hyprland upscales it by the monitor scale: right size, but
bilinear-blurred, and it applies to every XWayland client, not just this one.
Hyprland has no per-window switch for it. Not done; noted so it isn't re-derived.

## Debugging without switching workspaces

XWayland windows can be captured over X11 even when their workspace is not
visible — every X toplevel is redirected to a pixmap. `xprop` and ImageMagick
are already installed:

```sh
for w in $(xprop -root _NET_CLIENT_LIST | grep -o '0x[0-9a-f]*'); do
  xprop -id "$w" WM_CLASS | grep -q BambuStudio && import -window "$w" "bambu-$w.png"
done
```

The image is in physical pixels; divide by the monitor scale for the on-screen
size. `hyprctl clients -j` gives the same in logical px (`size`).
