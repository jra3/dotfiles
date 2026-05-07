# Bitwarden picker via rbw + walker

**Date:** 2026-05-07
**Status:** Approved (brainstorming complete, awaiting implementation plan)

## Problem

The Bitwarden desktop app is Electron-based and behaves poorly on Hyprland/Omarchy: tray icon doesn't integrate with the Wayland session, focus and modal-dialog quirks, slow startup, and a heavy memory footprint for a tool we use to fetch a single secret at a time. The current keybind `Super+Shift+/` launches `bitwarden-desktop` and inherits all of these issues.

## Goal

Replace the desktop app with a fast, keyboard-driven picker that works natively on Wayland and integrates with the dotfiles repo via stow. Keep the official browser extension for in-page autofill — this design covers everything else (terminal, native apps, ad-hoc clipboard fetches).

## Non-goals

- Auto-type into focused windows (Wayland makes this fragile; not requested).
- Favorites / recent-entry pinning (walker fuzzy search is fast enough).
- Replacing the browser extension's in-page fill flow.
- A GUI for creating/editing entries — `rbw add` / `rbw edit` are sufficient.

## Architecture

```
[Super+Shift+/]
   │
   ▼
bw-pick (script in bitwarden/.local/bin/)
   │
   ├─► rbw ls                       (list entries; format: "name (username)")
   ├─► walker -d -p "Bitwarden"     (entry picker)
   ├─► walker -d -p "<entry>"       (field picker: password/username/TOTP/URL/notes)
   ├─► rbw get / rbw code <entry>   (decrypt requested field)
   └─► wl-copy --paste-once         (clipboard, auto-clears after first paste)
                                    + 30s watchdog clear as backup

rbw-agent (auto-spawned by rbw on first call)
   │
   └─► pinentry-gnome3              (master password prompt, Wayland-native)
```

**Why rbw + walker:**
- `rbw` (Rust client) ships with `rbw-agent` — agent socket-activates on first call, caches the master password (like ssh-agent / gpg-agent), no autostart needed.
- `walker` is already installed on Omarchy and supports dmenu mode (`-d`) and password mode (`-x`).
- Both are native (no Electron, no Node.js startup penalty).

## Components

### New files

| Path | Purpose |
|------|---------|
| `bitwarden/.local/bin/bw-pick` | Picker script (~60 lines bash). Single entry point invoked by the keybind. |
| `bitwarden/.config/rbw/config.json` | rbw config: email, server URL (default `https://api.bitwarden.com`), `pinentry: pinentry-gnome3`. Email may need to be a placeholder template the user edits post-stow — see Open questions. |

### Modified files

| Path | Change |
|------|--------|
| `hypr/.config/hypr/bindings.conf` | Replace `bindd = SUPER SHIFT, SLASH, Passwords, exec, uwsm-app -- bitwarden-desktop` with `bindd = SUPER SHIFT, SLASH, Passwords, exec, uwsm-app -- bw-pick` |
| `pacman/` package list | Add `rbw` and `pinentry-gnome3` (verify which repo each lives in — `rbw` may be AUR via yay) |

### Existing assets reused

- `bitwarden/.local/bin/get-signature` — unchanged; this script extracts attachments via the official `bw` CLI for SSH keys and is orthogonal to the picker.

## User flow

### Happy path (vault unlocked, agent warm)
1. `Super+Shift+/` → walker pops with entry list, fuzzy-searchable
2. Type a few chars, hit Enter → second walker pops with field menu: `Password`, `Username`, `TOTP`, `URL`, `Notes`
3. Enter on field → value copied to clipboard, walker closes, notification confirms "Password copied (clears in 30s)"

### First trigger after boot / agent timeout
Identical flow, except step 1 first shows a `pinentry-gnome3` prompt for the master password. Agent caches it for the rest of the session.

### TOTP detail
TOTP codes rotate every 30 seconds. When the user picks TOTP, the notification shows the remaining seconds in the current rotation window so they know whether to paste immediately or wait for the next rotation.

## Edge cases

| Case | Behavior |
|------|----------|
| Vault not configured (first-ever run) | Script detects missing `rbw` config, shows notification: "Run `rbw config set email YOUR@EMAIL` then `rbw login`". Hard-fails rather than producing half-working state. |
| User cancels pinentry or walker | Script exits silently, clipboard untouched. |
| Entry has no TOTP | Show TOTP option but `rbw code` returns empty — script catches empty result and notifies "No TOTP for this entry" instead of copying an empty string. |
| Multiple entries with same name | Disambiguate in the list with `name (username)`. Pass exact name + `--user <username>` to `rbw get`. |
| Vault sync stale | Append a `Sync vault` pseudo-entry at the bottom of the picker that calls `rbw sync` and exits (no field menu). |
| Clipboard not pasted within timeout | Two-layer clear: `wl-copy --paste-once` (auto-clears after first paste) plus a backgrounded 30s `wl-copy --clear` as fallback. |

## First-run setup (documented, not automated)

After stowing the package, the user runs:
```bash
rbw config set email theactualjohnallen@gmail.com  # or edit config.json directly
rbw login                                            # one-time master password
rbw sync                                             # initial vault download
```

Subsequent reboots: just trigger the keybind; agent prompts via pinentry.

## Open questions for implementation

1. **Email in config.json:** Should the stowed `config.json` contain the user's email, or be a template that errors helpfully if not customized? Email is in the user's auto-memory but committing it to the dotfiles repo means it ships with any future fork/share. Recommendation: omit from config.json, document `rbw config set email` in the package's README or in a comment in `bw-pick`.
2. **`rbw` package source:** Verify whether `rbw` is in `extra` or only AUR — affects whether it goes in the pacman or yay package list.
3. **Notification mechanism:** Use `notify-send` (libnotify, Omarchy default via mako/dunst) for clipboard-clear and TOTP-rotation notifications.

## Testing

- Manual smoke test on first install: stow, run `bw-pick` directly from terminal, verify each field type copies correctly.
- Test edge cases: cancel pinentry, cancel walker, pick entry with no TOTP, pick `Sync vault`.
- Verify clipboard auto-clear: copy password, wait 35s, paste — should be empty.
- Verify keybind replacement: `hyprctl reload` and confirm `Super+Shift+/` triggers `bw-pick`, not `bitwarden-desktop`.

## Out of scope (future work, not now)

- Removing `bitwarden-desktop` from the system entirely (leave installed for now in case of fallback need).
- Migrating `get-signature` from `bw` to `rbw` (rbw doesn't currently support attachments — keep `bw` for that one use case).
