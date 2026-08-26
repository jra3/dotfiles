# hypr

Hyprland config, Lua since Omarchy 4 ("Quattro"). Only the deltas from
`$OMARCHY_PATH/default/hypr/` belong in these files; anything not set here keeps
Omarchy's default.

Validate every change:

```bash
hyprctl reload && hyprctl configerrors
```

## `monitors.lua` is deliberately NOT in this package

Each machine manages its own displays. `~/.config/hypr/monitors.lua` is a plain
host-local file — Omarchy's template, edited per machine — and never enters the repo.

It *was* stowed and shared across hosts until 2026-08-25. Two things killed that:

- **Scale is per-machine, and a shared file can only hold one.** The file carried a
  single `omarchy_monitor_scale` used by every rule, so a value tuned for one panel
  was wrong on another. chonky's 2560x1600 wanted 1.6; cupcake's 12.2" 1920x1200
  wants 1.25, which at 1.6 would have meant a 1200x750 logical desktop.
- **The Omarchy display menu writes the file with `sed -i`**, which replaces a symlink
  with a regular file and silently drops it out of stow. Keeping the file host-local
  turns that hazard into a non-event: there is no symlink left to clobber, and
  `omarchy-hyprland-monitor-scaling` can persist a scale the normal way.

### What the shared version knew

Reference for anyone hand-writing a `monitors.lua`. These are measured, not guessed.

**Never pin a hardcoded mode to `eDP-1`.** Hyprland silently ignores rules whose
monitor isn't connected, but that only holds for `desc:` rules — port names like
`eDP-1` exist on *every* laptop, so a port-matched rule applies on every host. If the
panel can't do the mode, the DRM atomic commit fails and Hyprland **segfaults during
startup** in `Aquamarine::SDRMConnector::releaseStashedCommit`. The compositor dies
~4s after login and SDDM bounces you back to the greeter — which looks exactly like
the login password "not working". Use `mode = "highrr"` and let each panel resolve
its own mode.

**Match external displays by `desc:`, not by port**, so the rule follows the monitor
across ports and is skipped on hosts that don't have it:

```lua
hl.monitor({ output = "desc:LG Electronics LG SDQHD", mode = "2560x2880@60", position = "0x0", scale = s })
```

**Omarchy's defaults set neither `GDK_SCALE` nor a catch-all monitor rule.** Both live
only in the user-level `monitors.lua` template, so a hand-written file has to carry
them or they are simply absent:

```lua
hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })
```

The catch-all must come **first** — last matching rule wins.

**Keep the two magic names.** The display menu persists a scale by `sed`-ing exactly
`local omarchy_monitor_scale` and `local omarchy_gdk_scale`, matching a bare numeric
literal. Rename them, or compute the value, and a scale change applies live and then
vanishes on the next reload. `GDK_SCALE` must be an integer (GTK ignores fractional),
which is why it is the monitor scale rounded to the nearest whole number.

**Known geometry**, for reconstruction:

| Host | Panel | Notes |
|---|---|---|
| chonky | 2560x1600 eDP | docked right of the LG, scale 1.6 |
| cupcake | BOE NV122WUM-N42, 1920x1200 | Framework Laptop 12, scale 1.25 |
| paperweight | none, desktop | drives the LG alone, scale 1.6, `GDK_SCALE` 2 |
| — | LG Electronics LG SDQHD, 2560x2880 | desktop primary at `0x0` |

Bottom-aligning a laptop panel beside the LG means offsetting Y by the difference of
their *logical* heights, i.e. `(2880 - panel_height) / scale`.
