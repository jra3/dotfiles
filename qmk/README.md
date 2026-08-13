# `qmk` — Framework 16 keyboard, host side

The host half of a custom keymap for the Framework Laptop 16 ANSI keyboard
module. Optional: nothing else in this repo depends on it, and it is inert
without the matching firmware.

## The other repo

The firmware lives in **`jra3/qmk_firmware`**, branch **`fw16-john`**, checked
out at `~/jra3/qmk_firmware`. It is a fork of *Framework's* QMK fork, not QMK
proper — the Framework 16 boards exist only in Framework's tree. The keymap is
`keyboards/framework/ansi/keymaps/john/`.

Read that repo's `CLAUDE.md` before touching the firmware, and the keymap's own
`readme.md` for the wire protocol, the LED index derivation, and the modifier
layout.

The split is deliberate: **the firmware renders, the host decides.** All state
and timing — pomodoro phases, when a phase expires, what "muted" means — lives
here in `qmk-mic-led-sync.py`. The keymap only paints what it is told and
reports key presses back. Changing a phase length or a poll interval is a
restart of a Python script; changing a colour is a reflash.

## Scripts

| Script | Role |
|---|---|
| `qmk-mic-led-sync.py` | Daemon: syncs mic mute / DND / voxtype / pomodoro state to the keyboard over raw HID, and handles the pomodoro keys coming back. Autostarted from `hypr/.config/hypr/autostart.conf`. |
| `qmk-flash.py` | Pokes the board into BOOTSEL over raw HID and flashes a UF2. |

### Daemon

Needs `python-hid` — **not** `python-hidapi`, which provides a different API
(`hid.device()` rather than `hid.Device()`) and conflicts with it.

It reopens the device on disconnect and forces a full state resync, so it
survives an unplug or a reflash on its own. **Do not restart it after
flashing** — that only throws away the running pomodoro.

### Flashing

Build in the firmware repo, then flash from anywhere:

    qmk compile -kb framework/ansi -km john      # in ~/jra3/qmk_firmware
    pkexec /usr/bin/python3 ~/.local/bin/qmk-flash.py

`picotool` needs root and no udev rules are installed. Use `pkexec`, not
`sudo -A`: this machine's PAM stack leads with `pam_u2f` and `pam_fprintd`,
which an askpass helper cannot satisfy. Answer the dialog with a YubiKey touch
or fingerprint — by the time it matters the keyboard is in BOOTSEL and cannot
type.

The script's header documents the two non-obvious constraints (authenticate
before the board leaves; poll sysfs, never `picotool info`).
