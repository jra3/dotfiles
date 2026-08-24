-- Extra autostart processes.
--
-- Omarchy's own autostart already launches udiskie (with --no-notify), the
-- shell, and the monitor watcher -- see $OMARCHY_PATH/default/hypr/autostart.lua.

-- QMK mic/DND/voxtype LED sync over raw HID. Only present on the Framework 16,
-- where the `qmk` stow package is deployed; skip it everywhere else.
local qmk_led_sync = os.getenv("HOME") .. "/.local/bin/qmk-mic-led-sync.py"
if o.cmd_present(qmk_led_sync) then
  o.exec_on_start(qmk_led_sync)
end
