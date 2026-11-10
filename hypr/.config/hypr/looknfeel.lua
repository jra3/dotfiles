-- Change the default Omarchy look'n'feel.
-- See https://wiki.hypr.land/Configuring/Basics/Variables/

hl.config({
  decoration = {
    -- Omarchy ships square corners.
    rounding = 8,
  },
})

-- Opt another application in to Omarchy's standard transparency.
-- Find its class with: hyprctl clients
-- o.transparent_window("my-app")
-- o.transparent_window("my-app", "0.9 0.85") -- Custom active/inactive opacity.
