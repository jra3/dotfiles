---
name: gui-sudo
description: Run sudo commands from Claude Code by popping a graphical password dialog on the user's desktop. Use whenever a task needs root and sudo fails with "a terminal is required to read the password" or "sudo: a password is required" — including disk imaging (dd), mounting devices, systemctl, package installs, and editing root-owned files. Also use proactively before any sudo command when sudo credentials are not already cached.
---

# GUI sudo from Claude Code

## The problem

Claude Code's Bash tool runs without a controlling TTY. So:

- `sudo <cmd>` → `sudo: a terminal is required to read the password`
- `sudo -n <cmd>` → `sudo: a password is required` (no prompt at all)
- Telling the user to run `! sudo -v` **also fails** — the `!` prefix runs in the
  same TTY-less context, and even when it doesn't, `tty_tickets` (default on Arch)
  means the cached timestamp won't apply to the Bash tool's session anyway.

The fix: give sudo a **graphical** askpass helper via `SUDO_ASKPASS` and run `sudo -A`.
A dialog appears on the user's desktop; they type the password there; the command runs.

## Preflight

Check all of this in one call before setting anything up:

```bash
# 1. Is sudo already cached? (skip everything if so)
sudo -n true 2>/dev/null && echo "SUDO CACHED" || echo "SUDO NOT CACHED"

# 2. Is there a GUI session to draw a dialog on?
echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset} DISPLAY=${DISPLAY:-unset}"

# 3. Which dialog tool exists?
for p in zenity kdialog yad gxmessage qarma; do command -v $p; done

# 4. Is a polkit agent running? (enables the pkexec fallback)
pgrep -a polkit | head -3
```

If `WAYLAND_DISPLAY` and `DISPLAY` are both unset, there is no desktop to draw on —
skip to **Fallback: user runs it themselves**.

## Setup

Write the helper to the scratchpad directory (never the user's project):

```bash
cat > "$SCRATCH/askpass.sh" <<'EOF'
#!/usr/bin/env bash
zenity --password --title="sudo — <short description of what this authorizes>" 2>/dev/null
EOF
chmod +x "$SCRATCH/askpass.sh"
```

Make the title specific — `"sudo — flash SD card (/dev/sda)"` beats `"sudo"`. The user
is being asked to authorize something; the dialog should say what.

Per-tool syntax if `zenity` is missing:

| tool | command |
|---|---|
| zenity | `zenity --password --title="..."` |
| kdialog | `kdialog --password "..."` |
| yad | `yad --entry --hide-text --title="..."` |
| qarma | `qarma --password --title="..."` |

## Run

```bash
export SUDO_ASKPASS="$SCRATCH/askpass.sh"
sudo -A <command>
```

**Then tell the user a dialog just appeared on their screen** — otherwise the turn
looks hung while it silently waits for input they don't know is there.

For anything slow (imaging, large installs), put the whole thing in one script and run
it backgrounded so the turn isn't blocked:

```bash
export SUDO_ASKPASS="$SCRATCH/askpass.sh"
sudo -A bash "$SCRATCH/task.sh" 2>&1
```

## Batch the work into one script

Each `sudo -A` invocation can re-prompt. For multi-step root work, write **one** script
and call it with a single `sudo -A` — one dialog, not five. Put safety guards inside
that script (see below) rather than relying on separate checked calls.

## Safety guards for destructive root work

When the script touches block devices or deletes things, assert the target is what you
think it is and abort otherwise:

```bash
TRAN=$(lsblk -ndo TRAN "$DEV")
[ "$TRAN" = "usb" ] || { echo "!! $DEV is not USB -- aborting" >&2; exit 1; }
```

Cheap, and it turns "wrong variable" from a wiped NVMe into a clean abort.

## Fallbacks

**1. pkexec** — if a polkit agent is running (`polkit-gnome-authentication-agent-1`,
`hyprpolkitagent`, `polkit-kde-agent`), this pops its own dialog:

```bash
pkexec bash "$SCRATCH/task.sh"
```

Caveat: `pkexec` sanitizes the environment, so export what the script needs inside the
script itself, not in the caller.

**2. User runs it themselves** — headless, or the dialog never appears. Write the script,
then hand over one copy-pasteable line:

```
! sudo bash /full/path/to/task.sh
```

If that fails on the TTY error too, ask them to run it in a real terminal window outside
Claude Code and paste back the output.

## Never

- Never ask the user to type their password into the chat, and never accept it if offered.
  It would land in the transcript. The dialog exists precisely so the password never
  transits the conversation.
- Never write a password into the askpass script, a file, or an env var.
- Never add a NOPASSWD entry to `/etc/sudoers` to work around a prompt unless the user
  explicitly asks for that specific change — it is a permanent, system-wide privilege
  escalation, not a convenience tweak.
