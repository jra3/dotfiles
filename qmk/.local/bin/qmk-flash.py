#!/usr/bin/env python3
"""Flash the Framework 16 ANSI keyboard module: poke it into BOOTSEL and load a
UF2, both as root in one go.

The firmware itself lives in the other repo -- `jra3/qmk_firmware`, branch
`fw16-john`, checked out at ~/jra3/qmk_firmware. Build there first:

    qmk compile -kb framework/ansi -km john

then run this. See that repo's CLAUDE.md for the board's gotchas, and the
`qmk-mic-led-sync.py` daemon next to this script for the host half of the
keymap's indicator LEDs.

Two things this gets right that are easy to get wrong:

* **Authenticate before the board leaves.** Once it is in BOOTSEL the keyboard
  is gone, so a polkit dialog raised after that point has to be answered on a
  keyboard that no longer exists. Doing the poke and the flash inside one
  already-root process means the dialog comes first. Answer it with a YubiKey
  touch or fingerprint. Use pkexec, not `sudo -A`: this machine's PAM stack
  leads with pam_u2f and pam_fprintd, which an askpass helper cannot satisfy.

* **Wait for BOOTSEL by reading sysfs, never by polling `picotool info`.** A
  picotool poll appears to knock the RP2040 back during enumeration -- with one
  running at 3 Hz the device never finished coming up (20s and 60s deadlines
  both expired), and both times it appeared within seconds of the loop
  stopping. Reading sysfs never touches the device; the whole cycle then takes
  about ten seconds, dialog included.

Usage:

    pkexec /usr/bin/python3 ~/.local/bin/qmk-flash.py [firmware.uf2]
"""
import glob
import os
import subprocess
import sys
import time

DEFAULT_UF2 = os.path.expanduser("~/jra3/qmk_firmware/.build/framework_ansi_john.uf2")

RAW_HID_USAGE_PAGE = b"\x06\x60\xff"  # 0xFF60, the interface factory.c listens on
KEYBOARD_HID_ID = "0003:000032AC:00000012"
BOOTSEL_VID, BOOTSEL_PID = "2e8a", "0003"  # RP2 Boot


def find_rawhid():
    """The keyboard's raw-HID interface, or None if it is not enumerated."""
    for d in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
        try:
            with open(f"{d}/device/report_descriptor", "rb") as f:
                usage_page = f.read(3)
            with open(f"{d}/device/uevent") as f:
                uevent = f.read()
        except OSError:
            continue
        if usage_page == RAW_HID_USAGE_PAGE and KEYBOARD_HID_ID in uevent:
            return "/dev/" + os.path.basename(d)
    return None


def bootsel_present():
    for vid_path in glob.glob("/sys/bus/usb/devices/*/idVendor"):
        try:
            with open(vid_path) as f:
                if f.read().strip() != BOOTSEL_VID:
                    continue
            with open(vid_path[: -len("idVendor")] + "idProduct") as f:
                if f.read().strip() == BOOTSEL_PID:
                    return True
        except OSError:
            continue
    return False


uf2 = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_UF2
if not os.path.exists(uf2):
    sys.exit(f"no such firmware: {uf2}")

dev = find_rawhid()
if dev:
    # factory.c's f_bootloader: command 0x0B, subcommand 0xFE. Works on any
    # build of this board including stock, no key combo, no reseating.
    print(f"raw HID: {dev} -- sending 0x0B 0xFE (f_bootloader)")
    fd = os.open(dev, os.O_RDWR)
    os.write(fd, bytes([0x00, 0x0B, 0xFE]) + bytes(29))
    os.close(fd)
elif bootsel_present():
    print("keyboard already in BOOTSEL")
else:
    sys.exit("no raw-HID interface and nothing in BOOTSEL -- is the module attached?")

deadline = time.time() + 60
while not bootsel_present():
    if time.time() > deadline:
        sys.exit("RP2040 never appeared in BOOTSEL")
    time.sleep(0.5)

time.sleep(1.0)  # let enumeration settle before picotool claims the device
print(f"BOOTSEL device up, flashing {uf2}")
sys.exit(subprocess.run(["picotool", "load", "-x", uf2]).returncode)
