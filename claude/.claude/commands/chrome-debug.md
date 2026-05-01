---
description: Launch Chrome with remote debugging on port 9222 for claude-in-chrome MCP
allowed-tools: Bash(gtk-launch:*), Bash(ss:*), Bash(pgrep:*), Bash(sleep:*)
---

# Launch Debug Chrome

Start Google Chrome with CDP remote debugging enabled so the `claude-in-chrome` MCP can attach.

## Instructions

1. Check whether Chrome is already listening on port 9222:
   ```bash
   ss -tlnp 2>/dev/null | grep -q ':9222 '
   ```
2. If it's already running, tell the user and stop — do not launch a second instance.
3. Otherwise launch via the desktop entry (which carries the debug flags and dedicated profile):
   ```bash
   gtk-launch google-chrome
   ```
   Run it in the background so it doesn't block.
4. Sleep 2 seconds, then verify port 9222 is listening and a process with `--remote-debugging-port=9222` exists:
   ```bash
   ss -tlnp 2>/dev/null | grep 9222
   pgrep -af 'remote-debugging-port=9222' | head -1
   ```
5. Report the PID and confirm the MCP can now attach. If verification fails, surface the error instead of claiming success.

## Notes

- The desktop entry at `~/.local/share/applications/google-chrome.desktop` (from the `google-chrome` stow package) supplies `--remote-debugging-port=9222 --remote-allow-origins=* --user-data-dir=$HOME/.config/google-chrome-debug`.
- The debug profile is isolated from the default Chrome profile at `~/.config/google-chrome`.
