# tether

iPhone USB tethering on this `iwd` + `systemd-networkd` machine (no NetworkManager),
plus a waybar indicator.

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

## Waybar wiring (NOT tracked in this repo)

`~/.config/waybar/config.jsonc` + `style.css` are live Omarchy files, not stow-managed.
The indicator adds a `custom/tether` entry to `modules-right` (between `bluetooth` and
`network`), a matching module definition (`exec` → this script, `return-type: json`,
5s interval), and a `#custom-tether` margin rule in `style.css`. Re-apply by hand after
`omarchy refresh waybar`.

## First-time use

1. `stow tether` (deploys the script)
2. `sudo pacman -S --needed usbmuxd`
3. Run `pacman/configure-system` (writes the `.network` file), or drop it by hand.
4. Unlock iPhone → enable Personal Hotspot → plug in USB → tap **Trust This Computer**.
   `idevicepair pair` if the trust prompt loops.
