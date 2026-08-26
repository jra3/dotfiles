-- Control your input devices.
-- See https://wiki.hypr.land/Configuring/Basics/Variables/#input
--
-- Only the deltas from Omarchy's defaults belong here; anything not listed
-- keeps whatever $OMARCHY_PATH/default/hypr/input.lua set.
--
-- Not overridden on purpose:
--   kb_layout    -- Omarchy derives it from /etc/vconsole.conf.

-- kb_options: Caps is Ctrl everywhere, and Alt/Super are swapped on the
-- Framework 12 only.
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
-- WHERE THE SWAP APPLIES: the Framework 12 and nothing else.
--
-- The base string below is the default on every host. altwin:swap_alt_win is
-- opt-in, per host, because it only describes the Framework 12's bottom row --
-- it is a fix for that one keyboard, not a preference about modifiers.
--
-- This was inverted on 2026-08-26. The swap used to be global with an exemption
-- for the Kinesis Advantage 360, which put every current and future board on the
-- wrong side of the default: a keyboard that remaps modifiers in its own
-- firmware (the Adv360 is ZMK, chonky's Framework 16 board is QMK) gets swapped a
-- second time and cancels its own keymap out, so each one needed a new
-- exemption. Listing the one host that wants the swap is the smaller list and
-- the safer failure: a board this file has never heard of now behaves normally.
--
-- Caveat, since this matches on host and not on device: plug a programmable
-- keyboard into a listed host and it gets the swap too. Narrow that case with an
-- hl.device({ name = ..., kb_options = kb_options_base }) block when it happens.
-- Don't pre-empt it -- device names are not stable enough to guess at from
-- another machine. The Adv360 registers a pointer and a keyboard under one
-- libinput name, and Hyprland appends -1 to whichever it enumerates second, so
-- which one is "kinesis-kinesis-adv360" changes across replugs.
local kb_options_base = "compose:ralt,ctrl:nocaps,shift:both_capslock_cancel"

local swap_alt_win_hosts = {
  cupcake = true, -- Framework Laptop 12
}

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

local kb_options = kb_options_base
if swap_alt_win_hosts[hostname()] then
  kb_options = kb_options .. ",altwin:swap_alt_win"
end

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
