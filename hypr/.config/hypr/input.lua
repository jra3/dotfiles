-- Control your input devices.
-- See https://wiki.hypr.land/Configuring/Basics/Variables/#input
--
-- Only the deltas from Omarchy's defaults belong here; anything not listed
-- keeps whatever $OMARCHY_PATH/default/hypr/input.lua set.
--
-- Not overridden on purpose:
--   kb_layout    -- Omarchy derives it from /etc/vconsole.conf.
--   kb_options   -- Omarchy sets "compose:caps,shift:both_capslock_cancel",
--                   which keeps the Caps-as-compose mapping we used to set by
--                   hand and adds a both-Shifts escape hatch for real Caps Lock.

hl.config({
  input = {
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
