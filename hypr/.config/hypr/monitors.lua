-- Shared monitor config for all hosts.
-- Hyprland applies the last matching rule, and silently ignores rules whose
-- monitor isn't connected -- so we list every display across all machines
-- and let each host pick up the rules that apply.
--
-- CAUTION: "ignores rules whose monitor isn't connected" only holds for `desc:`
-- rules. Port names like eDP-1 exist on EVERY laptop, so a port-matched rule is
-- applied on every host. Never pin a hardcoded mode to eDP-1 here: if the panel
-- can't do that mode the DRM atomic commit fails, and Hyprland then segfaults
-- during startup in Aquamarine::SDRMConnector::releaseStashedCommit -- the
-- compositor dies ~4s after login and SDDM bounces you back to the greeter,
-- which looks exactly like the login password "not working". Use highrr instead
-- and let each panel resolve its own mode.
--
-- Omarchy sets neither GDK_SCALE nor a catch-all monitor rule in its defaults --
-- both live only in the user-level monitors.lua it ships as a template, which
-- this file replaces. So they have to be carried here.
--
-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and modes: hyprctl monitors all

-- The Omarchy display menu (omarchy-hyprland-monitor-scaling) persists a scale
-- change by sed-ing these two lines. Keep the names, the `local ` prefix, and
-- the bare numeric literal exactly as they are, or the menu applies a new scale
-- live but silently loses it on the next reload.
--
-- GTK only honors integer GDK_SCALE, so this is the monitor scale rounded to
-- the nearest whole number -- which is what the menu writes back.
local omarchy_gdk_scale = 2
local omarchy_monitor_scale = 1.6

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))

-- Every rule below derives from omarchy_monitor_scale rather than repeating a
-- number, so a scale change from the menu moves the displays together instead
-- of leaving the laptop misaligned against a hardcoded offset.
local function logical(pixels)
  return math.floor(pixels / omarchy_monitor_scale + 0.5)
end

-- LG SDQHD, 2560x2880 stacked dual-QHD -- desktop primary, at the origin.
local lg_width, lg_height = 2560, 2880

-- Fallback for any other monitors (must come first -- last matching rule wins).
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })

-- Match the LG by description so it works regardless of which port it lands on.
hl.monitor({
  output = "desc:LG Electronics LG SDQHD",
  mode = lg_width .. "x" .. lg_height .. "@60",
  position = "0x0",
  scale = omarchy_monitor_scale,
})

-- Laptop internal display, docked to the right of the LG with their bottom
-- edges aligned.
--
-- `highrr` = preferred resolution at the panel's highest refresh rate, so every
-- host resolves a mode that actually exists. The per-host difference is the Y
-- offset, since bottom-alignment depends on the panel's logical height.
local function docked_right_of_lg(panel_height)
  return logical(lg_width) .. "x" .. (logical(lg_height) - logical(panel_height))
end

-- Base rule -- chonky (2560x1600 panel). Hosts without a more specific rule
-- below land here.
hl.monitor({
  output = "eDP-1",
  mode = "highrr",
  position = docked_right_of_lg(1600),
  scale = omarchy_monitor_scale,
})

-- cupcake (BOE NV122WUM-N42, 1920x1200 panel). Matched by description, so it
-- overrides the eDP-1 base rule on this host only.
hl.monitor({
  output = "desc:BOE NV122WUM-N42",
  mode = "highrr",
  position = docked_right_of_lg(1200),
  scale = omarchy_monitor_scale,
})
