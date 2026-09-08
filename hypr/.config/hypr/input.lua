-- Control your input devices.
-- See https://wiki.hypr.land/Configuring/Basics/Variables/#input
--
-- Only the deltas from Omarchy's defaults belong here; anything not listed
-- keeps whatever $OMARCHY_PATH/default/hypr/input.lua set.
--
-- Not overridden on purpose:
--   kb_layout    -- Omarchy derives it from /etc/vconsole.conf.

-- kb_options is a single string, not a list, so setting it REPLACES Omarchy's
-- "compose:caps,shift:both_capslock_cancel" rather than adding to it.
--
-- COMPOSE AND CTRL BOTH WANT CAPS, AND THEY CANNOT SHARE IT.
--
-- ctrl:nocaps wins over compose:caps in EITHER order -- this is not a
-- last-one-wins race, so reordering the string does not help. Verified by
-- compiling the keymap rather than by reading the rules files:
--
--   xkbcli compile-keymap --layout us --options \
--     "compose:caps,ctrl:nocaps,shift:both_capslock_cancel" | grep -A2 '<CAPS>'
--
--   <CAPS> -> Control_L
--
-- So each host picks one, and that is what splits the two strings below.
--
-- A keyboard that puts Ctrl somewhere reachable in its own firmware (the Adv360
-- is ZMK, chonky's Framework 16 board is QMK) does not need ctrl:nocaps, which
-- leaves Caps free for Compose -- where Omarchy puts it by default, and where a
-- Compose key belongs on a board with no key to spare. A stock laptop board
-- needs Ctrl on Caps, and then Compose has to go somewhere else.
--
-- Real Caps Lock survives either way on both-Shifts-together
-- (shift:both_capslock_cancel), and the next lone Shift releases it, so a
-- misfire clears itself.
--
-- ctrl:nocaps, not caps:ctrl_modifier -- the latter keeps the key identifying
-- as Caps Lock and still able to latch, which is not what "Caps is Ctrl" means.
local kb_options_default = "compose:caps,shift:both_capslock_cancel"

-- cupcake, the Framework Laptop 12, is the one host with a stock board. Its
-- bottom-left row, left to right, wants to be Fn, Ctrl, Alt, Cmd:
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
-- Ctrl on Caps evicts Compose, and here it lands on Right Alt. That is a second
-- collision: compose:ralt and altwin:swap_alt_win BOTH claim <RALT>, because
-- swap_alt_win expands to swap_lalt_lwin + swap_ralt_rwin. Compose wins, again
-- verified by compiling:
--
--   xkbcli compile-keymap --layout us --options \
--     "compose:ralt,ctrl:nocaps,shift:both_capslock_cancel,altwin:swap_alt_win"
--
--   <CAPS> -> Control_L      <LWIN> -> Alt_L, Meta_L
--   <RALT> -> Multi_key      <LALT> -> Super_L
--
-- The cost is AltGr, which a US layout barely uses. Re-run that command after
-- touching this string; a collision here fails silently, not loudly.
local kb_options_by_host = {
  cupcake = "compose:ralt,ctrl:nocaps,shift:both_capslock_cancel,altwin:swap_alt_win",
}

-- WHY THE EXCEPTION IS THE LAPTOP AND NOT THE PROGRAMMABLE BOARDS: this file
-- used to apply the laptop treatment everywhere and exempt boards one at a time
-- -- the Alt/Super swap inverted on 2026-08-26, Compose and Ctrl followed on
-- 2026-09-03. Both are the same argument. A keyboard that remaps modifiers in
-- its own firmware gets remapped a second time and cancels its own keymap out,
-- so a global default needed a new exemption per board, and every future board
-- started out wrong. Listing the one host with a stock keyboard is the smaller
-- list and the safer failure: a board this file has never heard of now behaves
-- normally.
--
-- Not verified on chonky: its QMK keymap is not documented as putting Ctrl
-- anywhere in particular, so it may want the Caps treatment after all. If it
-- does, give it its own entry above rather than moving anything back into the
-- default.
--
-- Caveat, since this matches on host and not on device: plug a stock keyboard
-- into an unlisted host and it gets the default, Caps included. Narrow that case
-- with an hl.device({ name = ..., kb_options = ... }) block when it happens.
-- Don't pre-empt it -- device names are not stable enough to guess at from
-- another machine. The Adv360 registers a pointer and a keyboard under one
-- libinput name, and Hyprland appends -1 to whichever it enumerates second, so
-- which one is "kinesis-kinesis-adv360" changes across replugs.

-- /etc/hostname rather than a `hostname` subprocess: Hyprland reaps its own
-- children, and Omarchy's own input.lua reads /etc/vconsole.conf the same way.
local function hostname()
  local file = io.open("/etc/hostname", "r")
  if not file then
    return nil
  end

  local name = file:read("*l")
  file:close()

  return name and name:match("^%s*(.-)%s*$")
end

local kb_options = kb_options_by_host[hostname()] or kb_options_default

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
