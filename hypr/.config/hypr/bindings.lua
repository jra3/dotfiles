-- Personal keybindings. Loaded after Omarchy's defaults, but a second bind on
-- an already-bound key does NOT replace the first -- both fire. So every key
-- Omarchy already claims has to be hl.unbind()'d before we rebind it.
--
-- List what's currently bound: omarchy menu keybindings --print
--
-- Deliberately NOT redefined here, because Omarchy 4 now ships the same thing:
--   SUPER+RETURN            omarchy-launch-terminal already opens in the
--                           active terminal's cwd
--   SUPER+SHIFT+RETURN      Browser
--   SUPER+SHIFT+B           Browser
--   SUPER+SHIFT+ALT+B       Browser (private)
--   SUPER+SHIFT+F           File manager
--   SUPER+ALT+SHIFT+F       File manager (cwd)
--   SUPER+SHIFT+D           Docker (lazydocker)
--   SUPER+ALT+RETURN        Tmux -- Omarchy's attaches to a session named
--                           "Work" rather than always opening a new one
--   SUPER+CTRL+P            Power menu (Tailscale lives in the Omarchy plugin)
--   SUPER+CTRL+3/4/5        Bar panels 3-5 (the old macOS-style screenshot
--                           binds are gone; capture is on PRINT and
--                           SUPER+CTRL+C)

--------------------------------------------------------------------------------
-- Keys taken back from Omarchy 4 defaults
--------------------------------------------------------------------------------

hl.unbind("SUPER + T")                 -- was: Toggle window floating/tiling
hl.unbind("SUPER + SHIFT + E")         -- was: Email (HEY)
-- NOTE: hl.unbind matches the modifier string literally, while o.bind
-- normalizes it. Spell these exactly as Omarchy does or the unbind silently
-- does nothing and both bindings fire.
-- SUPER+SHIFT+ALT+E is meant to do nothing. This unbind is load-bearing, not
-- leftover: Omarchy claims the key for HEY compose, so deleting the line revives
-- that binding rather than freeing the key.
hl.unbind("SUPER + SHIFT + ALT + E")   -- was: New email (HEY)
hl.unbind("SUPER + SHIFT + W")         -- was: Omawrite
hl.unbind("SUPER + SHIFT + SLASH")     -- was: Passwords (1Password)
hl.unbind("SUPER + SHIFT + G")         -- was: Signal (launch, not scratchpad)
hl.unbind("SUPER + SHIFT + A")         -- was: ChatGPT
hl.unbind("SUPER + SHIFT + C")         -- was: Calendar (HEY)
hl.unbind("SUPER + SHIFT + M")         -- was: Music (Spotify)
hl.unbind("SUPER + SHIFT + Y")         -- was: YouTube (launch, not scratchpad)
hl.unbind("SUPER + SHIFT + N")         -- was: Editor
hl.unbind("SUPER + SHIFT + S")         -- was: Google Maps
hl.unbind("SUPER + SHIFT + P")         -- was: Google Photos

-- SUPER+T stays unbound on purpose, so Helium gets it for new tabs.

--------------------------------------------------------------------------------
-- Tiling features we don't use, unbound to free the keys
--------------------------------------------------------------------------------

-- Window groups ("tabs"), pseudo-tiling, and Omarchy's generic scratchpad go
-- unused here, so their 20 default keys are freed rather than left live. Nothing
-- is rebound onto them yet; they are a pool for future bindings.
--
-- This does NOT touch the per-app Scratchpads section below. Those are our own
-- special workspaces (Signal, Slack, ...), not `special:scratchpad`.
--
-- Spelled exactly as $OMARCHY_PATH/default/hypr/bindings/tiling.lua spells them.
-- hl.unbind matches the modifier string literally, so "SUPER + ALT + SHIFT + TAB"
-- written with SHIFT before ALT would silently leave the binding live.

hl.unbind("SUPER + P")                 -- was: Pseudo window

hl.unbind("SUPER + S")                 -- was: Toggle scratchpad
hl.unbind("SUPER + ALT + S")           -- was: Move window to scratchpad

hl.unbind("SUPER + G")                 -- was: Toggle window grouping
hl.unbind("SUPER + ALT + G")           -- was: Move active window out of group
hl.unbind("SUPER + ALT + LEFT")        -- was: Move window to group on left
hl.unbind("SUPER + ALT + RIGHT")       -- was: Move window to group on right
hl.unbind("SUPER + ALT + UP")          -- was: Move window to group on top
hl.unbind("SUPER + ALT + DOWN")        -- was: Move window to group on bottom
hl.unbind("SUPER + ALT + TAB")         -- was: Next window in group
hl.unbind("SUPER + ALT + SHIFT + TAB") -- was: Previous window in group
hl.unbind("SUPER + CTRL + LEFT")       -- was: Move grouped window focus left
hl.unbind("SUPER + CTRL + RIGHT")      -- was: Move grouped window focus right
hl.unbind("SUPER + ALT + mouse_down")  -- was: Next window in group
hl.unbind("SUPER + ALT + mouse_up")    -- was: Previous window in group

-- "Switch to group window 1-5". Omarchy binds these by keycode, so unbind by
-- keycode too: code:10 is `1`.
for index = 1, 5 do
  hl.unbind("SUPER + ALT + code:" .. tostring(index + 9))
end

--------------------------------------------------------------------------------
-- Applications
--------------------------------------------------------------------------------

-- GDK_BACKEND=wayland: the pgtk build picks X11 through XWayland otherwise.
o.bind("SUPER + SHIFT + E", "Emacs", o.launch("env GDK_BACKEND=wayland emacs"))
o.bind("SUPER + SHIFT + T", "Activity", { tui = "btop" })
o.bind("SUPER + SHIFT + W", "Typora", o.launch("typora --enable-wayland-ime"))
-- Passwords: retired 2026-08-25. bw-pick shells out to `walker`, which Omarchy 4
-- replaced with the Quickshell launcher, so the binding was a no-op. The unbind
-- above stays: without it Omarchy's own 1Password binding comes back, and
-- 1Password is deliberately not installed either. Key is intentionally dead
-- until bw-pick is rewritten. See CLAUDE.md.
-- o.bind("SUPER + SHIFT + SLASH", "Passwords", o.launch("bw-pick"))
o.bind("SUPER + SHIFT + ALT + K", "Chess", { webapp = "https://chess.com/home", focus = true })

--------------------------------------------------------------------------------
-- Scratchpads
--------------------------------------------------------------------------------

-- SUPER+SHIFT+<key> toggles a special workspace holding one app, launching it
-- on first use. The window probe is the liveness check, because toggling an
-- empty special workspace just flashes an empty overlay.
--
-- This is pure Lua rather than the `hyprctl clients | jq` pipeline the .conf
-- version used. Omarchy 4's `hyprctl dispatch` takes a Lua dispatcher, so
-- `hyprctl dispatch togglespecialworkspace <name>` is now a parse error -- it
-- would fail the toggle and fall through to launching a duplicate window.

-- True when any open window's class satisfies `matches`.
local function any_window(matches)
  for _, window in ipairs(hl.get_windows()) do
    if window.class and matches(window.class) then
      return true
    end
  end

  return false
end

local function toggle_or_launch(keys, description, name, matches, launch)
  o.bind(keys, description, function()
    if any_window(matches) then
      hl.dispatch(hl.dsp.workspace.toggle_special(name))
    else
      hl.exec_cmd(launch)
    end
  end)
end

-- Web apps, keyed on the chrome-<host> class Omarchy gives them.
local function scratchpad(keys, description, name, class_prefix, launch)
  toggle_or_launch(keys, description, name, function(class)
    return class:sub(1, #class_prefix) == class_prefix
  end, launch)

  o.window("^" .. class_prefix:gsub("%.", "\\.") .. ".*", { workspace = "special:" .. name })
end

-- Signal is a native app with an exact class, so it matches exactly.
toggle_or_launch("SUPER + SHIFT + G", "Signal", "signal", function(class)
  return class == "signal"
end, o.launch("signal-desktop"))
o.window("^signal$", { workspace = "special:signal" })

scratchpad("SUPER + SHIFT + A", "Claude", "claude", "chrome-claude.ai", o.launch_webapp("https://claude.ai"))
scratchpad("SUPER + SHIFT + C", "Calendar", "calendar", "chrome-calendar.google.com", o.launch_webapp("https://calendar.google.com"))
scratchpad("SUPER + SHIFT + M", "Email", "mail", "chrome-mail.google.com", o.launch_webapp("https://mail.google.com"))
scratchpad("SUPER + SHIFT + Y", "YouTube", "youtube", "chrome-youtube.com", o.launch_webapp("https://youtube.com/"))
scratchpad("SUPER + SHIFT + K", "Chessly", "chessly", "chrome-chessly.com", o.launch_webapp("https://chessly.com/home"))
scratchpad("SUPER + SHIFT + L", "Linear", "linear", "chrome-linear.app", o.launch_webapp("https://linear.app"))
scratchpad("SUPER + SHIFT + N", "Notion", "notion", "chrome-app.notion.com", o.launch_webapp("https://app.notion.com/p/antimetal/"))
scratchpad("SUPER + SHIFT + S", "Slack", "slack", "chrome-app.slack.com", o.launch_webapp("https://app.slack.com/client/T04MQQ4C0LU/D0936HPFMQT"))

-- Apple Music runs under chromium, not Helium: it needs Widevine L1 for full
-- playback. setsid keeps it off the compositor's process group.
scratchpad(
  "SUPER + SHIFT + P",
  "Apple Music",
  "music",
  "chrome-music.apple.com",
  "setsid " .. o.launch("chromium --app=https://music.apple.com")
)

--------------------------------------------------------------------------------
-- Dictation, pedal, and mouse thumb buttons
--------------------------------------------------------------------------------

-- Hold to dictate, release to stop. Omarchy binds the same pair to F9.
o.bind("mouse:275", "Start dictation", "voxtype record start")
o.bind("mouse:275", "Stop dictation", "voxtype record stop", { release = true })

o.bind("XF86Tools", "Start dictation", "voxtype record start")
o.bind("XF86Tools", "Stop dictation", "voxtype record stop", { release = true })

-- Newline insert via the far mouse thumb button (forward / BTN_EXTRA).
-- Sends Shift+Enter: a newline in chat inputs (Slack, browsers) and, via
-- ghostty's shift+enter CSI-u keybind, in Claude Code too.
--
-- Uses wtype rather than the `send_shortcut` dispatcher on purpose. voxtype
-- types through wtype, which installs its own virtual keyboard + keymap; until
-- a real key is pressed that virtual keyboard stays the seat's active one, so
-- send_shortcut resolves `Return` against a keymap that doesn't contain it and
-- silently does nothing. wtype carries its own keymap, so it always works.
-- The `-s 40` gives the focused client time to load that keymap before Return
-- arrives (same reason voxtype has pre_type_delay_ms / wtype_shift_prefix).
o.bind("mouse:276", "Insert newline", "wtype -M shift -s 40 -k Return -m shift")

-- Meeting capture (transcription + Claude notes). Ships in the `voxtype` stow
-- package, which isn't deployed on every host.
if o.cmd_present("meeting-toggle") then
  o.bind("SUPER + CTRL + M", "Toggle meeting capture", "meeting-toggle")
end

--------------------------------------------------------------------------------
-- QMK firmware chords (Framework 16 ANSI keymap "john")
--------------------------------------------------------------------------------

-- F4/F5/F6 send HYPER+F12, HYPER+8 and HYPER+9. The keymap lives in
-- jra3/qmk_firmware on branch fw16-john; its LEDs reflect the state these
-- commands produce, so keep the chords in sync with keymap.c.
o.bind("SUPER + CTRL + SHIFT + ALT + F12", "Mic mute toggle", "pactl set-source-mute @DEFAULT_SOURCE@ toggle")
o.bind("SUPER + CTRL + SHIFT + ALT + 8", "Notification silencing", "omarchy-toggle-notification-silencing")
o.bind("SUPER + CTRL + SHIFT + ALT + 9", "Voxtype toggle", "voxtype record toggle")
