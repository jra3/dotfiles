-- Control your input devices.
-- See https://wiki.hypr.land/Configuring/Basics/Variables/#input
--
-- Only the deltas from Omarchy's defaults belong here; anything not listed
-- keeps whatever $OMARCHY_PATH/default/hypr/input.lua set.
--
-- Not overridden on purpose:
--   kb_layout    -- Omarchy derives it from /etc/vconsole.conf.

-- kb_options: Caps is Ctrl, and Alt/Super are swapped.
--
-- This REPLACES Omarchy's "compose:caps,shift:both_capslock_cancel" rather than
-- adding to it -- kb_options is a single string, not a list.
--
-- Bottom-left row on the Framework Laptop 12, left to right. The target is
-- Fn, Ctrl, Alt, Cmd:
--
--   pos 1  Ctrl           -- wants Fn     -- NOT POSSIBLE, see below
--   pos 2  Fn             -- wants Ctrl   -- NOT POSSIBLE, see below
--   pos 3  Framework key  -- wants Alt    -- altwin:swap_alt_win
--   pos 4  Alt            -- wants Cmd    -- altwin:swap_alt_win
--
-- Fn CANNOT be moved from software, and nothing here tries. The Framework 12's
-- ChromeOS-style EC (/dev/cros_ec, the cros-ec-* platform devices) handles Fn
-- entirely in firmware: KEY_FN is absent from the AT keyboard's evdev
-- capability bitmap, so the keypress never reaches Linux at all. No XKB option,
-- no udev hwdb entry and no hyprctl call can reach it -- only BIOS setup or a
-- custom EC build. Don't burn an afternoon rediscovering this.
--
-- Caps Lock itself is still reachable: shift:both_capslock_cancel keeps it on
-- both-Shifts-together (and releases it on the next lone Shift, so a misfire
-- clears itself). That option is inherited from Omarchy's default string, which
-- had it for the same reason back when Caps was Compose.
--
-- Compose moves from Caps to Right Alt. compose:ralt and
-- altwin:swap_alt_win BOTH claim <RALT> -- swap_alt_win expands to
-- swap_lalt_lwin + swap_ralt_rwin -- so the two options genuinely collide.
-- Compose wins; verified by compiling the keymap rather than by reading the
-- rules files:
--
--   xkbcli compile-keymap --layout us --options \
--     "compose:ralt,ctrl:nocaps,shift:both_capslock_cancel,altwin:swap_alt_win"
--
--   <CAPS> -> Control_L      <LWIN> -> Alt_L, Meta_L
--   <RALT> -> Multi_key      <LALT> -> Super_L
--
-- The cost is AltGr, which a US layout barely uses. Re-run that command after
-- touching this string; a collision here fails silently, not loudly.
--
-- ctrl:nocaps, not caps:ctrl_modifier -- the latter keeps the key identifying
-- as Caps Lock and still able to latch, which is not what "Caps is Ctrl" means.
--
-- NOTE: altwin:swap_alt_win applies on every host, not just the Framework 12.
-- Alt/Super sit in the same order on the Framework 16 (chonky), so the swap
-- lands the same way there -- but a keyboard that remaps modifiers in its own
-- firmware swaps them a second time and cancels the keymap out. chonky's board
-- is QMK; the Kinesis Advantage 360 on the desktop is ZMK and is exempted at
-- the bottom of this file. That exemption matches on device name, not host, so
-- it follows the board to whatever machine it is plugged into. Check any new
-- programmable board before trusting the global string.
--
-- Split in two so that exemption can reuse the shared part instead of
-- repeating it and drifting.
local kb_options_base = "compose:ralt,ctrl:nocaps,shift:both_capslock_cancel"
local kb_options = kb_options_base .. ",altwin:swap_alt_win"

hl.config({
  input = {
    kb_options = kb_options,

    -- Faster than Omarchy's 40/250.
    repeat_rate = 50,
    repeat_delay = 425,

    touchpad = {
      tap_to_click = true,
      -- Omarchy ships 0.4; 0.3 is calmer on the Framework trackpad.
      scroll_factor = 0.3,
    },
  },
})

-- Kinesis Advantage 360: exempt from the Alt/Super swap.
--
-- The Adv360 places its modifiers in ZMK firmware, not in XKB -- LCTRL and
-- LEFT_ALT in the thumb row, LEFT_COMMAND and RIGHT_COMMAND on the bottom row
-- (see ~/jra3/Adv360-Pro-ZMK, config/adv360.keymap). Applying
-- altwin:swap_alt_win on top of that swaps them a second time and undoes the
-- keymap. Everything else in the string is still wanted: the board has a real
-- CAPS key for ctrl:nocaps to take, and a RIGHT_ALT for compose:ralt.
--
-- Drop this block if the Framework 12 gets a ZMK keyboard and the global string
-- stops being the laptop default.
--
-- `name` is the device as `hyprctl devices` reports it, and the Adv360 does NOT
-- have one stable name. It registers a pointer as well as a keyboard, both
-- reported by libinput as "Kinesis Kinesis Adv360", and Hyprland breaks that tie
-- by appending -1 to whichever it enumerates second. So the typing keyboard is
-- `kinesis-kinesis-adv360` on some boots and `kinesis-kinesis-adv360-1` on
-- others; it was the bare name when this exemption was first written and the -1
-- on the very next replug, which put the swap back on the keyboard and the
-- exemption on the mouse.
--
-- Claim both names. kb_options on a pointer device is inert, so whichever one is
-- the mouse this boot just ignores it. (The -consumer-control and
-- -system-control endpoints get distinct names from libinput and carry no
-- layout, so they need nothing.)
for _, name in ipairs({ "kinesis-kinesis-adv360", "kinesis-kinesis-adv360-1" }) do
  hl.device({
    name = name,
    kb_options = kb_options_base,
  })
end
