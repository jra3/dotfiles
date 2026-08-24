# tether

iPhone USB tethering on this `iwd` + `systemd-networkd` machine (no NetworkManager),
plus a bar indicator.

> **TODO — the indicator is broken on Omarchy 4 (Quattro).** Waybar no longer exists;
> the bar is one Quickshell process at `$OMARCHY_PATH/shell`. The networking half below
> (the `.network` file, `usbmuxd`, and the detection logic in `waybar-iphone-tether`)
> is unaffected and still correct — only the presentation layer is gone.
>
> Two ways out, in preference order:
>
> 1. **Find an existing Omarchy shell plugin** for USB tethering or generic network
>    interfaces. Check `$OMARCHY_PATH/shell/plugins/bar/indicators/` and the omarchy
>    plugin ecosystem before writing anything.
> 2. **Write a Quickshell indicator.** `$OMARCHY_PATH/shell/plugins/bar/indicators/Dictation.qml`
>    is the smallest working example: a `BarIndicator` running a `Process` whose stdout
>    is parsed by a `SplitParser`, with `active` driving visibility. Two mismatches to
>    bridge: this script prints **once and exits**, whereas `Dictation.qml` expects a
>    process that *streams* (compare `omarchy-voxtype-status`, which execs
>    `voxtype status --follow`) — so either poll it on a `Timer` or add a follow loop.
>    And it emits `text`/`class`/`tooltip` but no `alt`, while `Dictation.qml` reads
>    `alt || class`; `class` is `connected` / `pending` / absent, which is what the
>    indicator's `active` should key off.
>
> Note that indicators are hidden while inactive unless hovered, or given `alwaysShow`
> on `omarchy.indicators` in `~/.config/omarchy/shell.json`.

## What's where

- **`.local/bin/waybar-iphone-tether`** (this package, stowed) — waybar `custom/tether`
  module. Prints Waybar JSON: a phone glyph when the iPhone is plugged but not yet
  routing (Personal Hotspot off / locked), a USB glyph once it has a DHCP lease, and
  an empty string (module hidden) when no iPhone is attached. Detects the interface by
  its `ipheth` kernel driver, so it doesn't care whether udev names it `usb0` or `enp…`.
- **`/etc/systemd/network/15-usb-tether.network`** — installed by `pacman/configure-system`.
  Matches the tether driver, runs DHCPv4, route-metric 200 (beats Wi-Fi's 600, yields to
  wired Ethernet's 100). IPv4 only — iPhone tether IPv6 stalls. The `15-` prefix is
  deliberate: the tether often appears as `eth0`, which stock `20-ethernet.network` also
  matches, and networkd uses only the first file in lexical order — so this must sort first.
- **`usbmuxd`** — in `pacman/packages-arch.txt`. Ships the udev rule that autostarts the
  pairing daemon on plug-in.

## Waybar wiring (OBSOLETE — waybar removed in Omarchy 4)

Kept for reference until the Quickshell indicator above replaces it. None of the
files below exist on a Quattro machine.

`~/.config/waybar/config.jsonc` + `style.css` are live Omarchy files (Omarchy
rewrites them on refresh/update), so the indicator isn't stowed. To reproduce on a
new machine — or after `omarchy refresh waybar` — apply these three edits:

1. Add `"custom/tether"` to `modules-right` in `config.jsonc`, between `bluetooth`
   and `network`.
2. Add the module definition to `config.jsonc`:

   ```jsonc
   "custom/tether": {
     "exec": "$HOME/.local/bin/waybar-iphone-tether",
     "return-type": "json",
     "interval": 5,
     "format": "{}",
     "tooltip": true
   },
   ```

3. Add the spacing rule to `style.css` (mirrors `#bluetooth`/`#network`):

   ```css
   #custom-tether {
     margin-right: 17px;
   }
   ```

Then `omarchy restart waybar`.

## First-time use (fresh machine)

1. `stow tether` — deploys `waybar-iphone-tether` to `~/.local/bin`.
2. `sudo pacman -S --needed usbmuxd` (already in `pacman/packages-arch.txt`).
3. Run `pacman/configure-system` — installs `15-usb-tether.network` **iff**
   systemd-networkd is in use (NetworkManager systems tether natively, no file).
4. Apply the waybar wiring above (optional — only for the tray icon).
5. Unlock iPhone → enable Personal Hotspot → plug in USB → tap **Trust This
   Computer**. Run `idevicepair pair` if the trust prompt loops.
