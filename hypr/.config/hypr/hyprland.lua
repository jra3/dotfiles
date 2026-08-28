-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/Start/

-- Omarchy's bootstrap keeps path setup out of this user config.
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

-- Load Omarchy defaults.
require("default.hypr.omarchy")

-- Personal overrides, loaded after Omarchy's defaults so package updates can
-- improve the defaults without rewriting these files.
require("hypr.monitors")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")

-- Keep chess.com on workspace 9 rather than wherever it was launched from.
o.window("chrome-chess\\.com.*", { workspace = "9" })

-- The Windows VM's RDP window. ~/.local/bin/windows passes /wm-class:windows-vm,
-- which lands in WM_CLASS's second field, the one Hyprland matches on. Bare
-- xfreerdp is there so Omarchy's own launcher, which sets no class, is caught
-- too. Vncviewer is the QEMU console (windows --console) -- capitalized because
-- that is TigerVNC's class (its instance is lowercase) and these are case-
-- sensitive; the StartupWMClass in its .desktop file names the wrong one.
-- Treat it like a media window rather than an app window: the contents are a
-- whole other desktop, so Omarchy's transparency and rounded corners land on
-- the guest's taskbar and title bars instead of on chrome we own.
o.window("^(windows-vm|xfreerdp|Vncviewer)$", { tag = "-default-opacity" })
o.window("^(windows-vm|xfreerdp|Vncviewer)$", { opacity = "1 1" })
o.window("^(windows-vm|xfreerdp|Vncviewer)$", { rounding = 0 })

-- Host input goes to the compositor while typing into RDP, so hypridle already
-- sees that as activity -- but reading or watching something in the guest is
-- invisible to it, and the host would lock over top of a live session.
o.window("^(windows-vm|xfreerdp|Vncviewer)$", { tag = "+noidle" })

-- Toggle config flags dynamically.
require("default.hypr.toggles")
