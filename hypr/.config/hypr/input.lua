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
-- NOTE: this applies on every host, not just the Framework 12. Alt/Super sit in
-- the same order on the Framework 16 (chonky), so the swap lands the same way
-- there -- but chonky's keyboard is QMK, and if its firmware ever remaps these
-- itself the two layers stack and cancel out. Check there before trusting it.
local kb_options = "compose:ralt,ctrl:nocaps,shift:both_capslock_cancel,altwin:swap_alt_win"

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
