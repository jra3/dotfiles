# sudo-touch

Touch-gated sudo for Omarchy: every escalation needs a FIDO2 touch, and a
dialog on the desktop says what the touch is for before the key blinks. Not a
stow package. Run `./install` from a real terminal, with a root shell open in
another one until the tests at the end pass.

## Pieces

| File | Runs as | Where it lands |
| -- | -- | -- |
| `sudo-escalation-notify` | root, from PAM | `/usr/local/bin`, root-owned |
| `plugin/` | the user, inside `omarchy-shell` | `~/.config/omarchy/plugins/jra3.sudo-escalation/` |
| `install` | the user, with sudo | writes `/etc/pam.d/sudo`, `/etc/pam.d/polkit-1`, `/etc/sudoers.d/10-touch-gated`, `/etc/tmpfiles.d/sudo-escalation.conf` |

The hook only writes files. In the auth phase, before `pam_u2f` starts
waiting, it drops a JSON record into `/run/sudo-escalation/<epoch>-<pid>.json`:
sudo's full argv read from `/proc/<pid>/cmdline`, the executable resolved
through sudoers' `secure_path` rather than the caller's `$PATH`, the caller's
process chain, tty and cwd. In the session phase, which sudo runs right after
a successful touch, it drops an empty `.approved` marker beside the record.
Records are root-owned, 0640 to the user's group, in a 0755 directory: the
dialog and the agent both run as the user, and a record the user could write
could be swapped for something harmless while the dialog is up.

The plugin is a `service` with `keepLoaded`. It watches that one directory,
and nothing else, with a `FolderListModel`: only root can create a record
there, so nothing running as the user can make the plugin draw a dialog. It
keeps a centred dialog on every screen until the sudo resolves, and polls
the sudo front end's pid with `kill -0`. It lasts:

- approved (marker appears): 1.5s, then gone
- denied: closes on the click
- ended with no touch (pid gone): 3s, or at once if the sudo was already gone
  when the plugin first saw its record
- `sh -c` payloads are laid out one command per line; control characters and
  bidi overrides are drawn as symbols, never interpreted
- more than one sudo at once queues, with a count and a touches-today tally
- after the 30s touch window the scrim drops and only the card takes clicks,
  so a password fallback (the askpass dialog under `sudo -A`) is reachable

Deny sends SIGTERM to the sudo front end. The user may signal it (sudo keeps
the caller's real uid) and SIGTERM ends the touch wait in about three seconds.
SIGINT does not: sudo defers it until pam_u2f's own wait ends, measured at
29s. A `sudo -A` waiting on its askpass helper ignores SIGTERM until the
helper exits, so Deny signals sudo's descendants too and follows up with
SIGKILL after 3s. The dialog closes on the click, not when the kill lands. An agent running as the user can deny its own sudo this way, which is
harmless.

What being user-writable does cost: the plugin draws the dialog, and the
agent runs as the same user. It cannot forge a record, but it could edit the
plugin and restart the shell, or open a lookalike window of its own, and show
something harmless over a real sudo. The record is root's word; the dialog is
only as trustworthy as the user's session.

## Testing

There is no unprivileged dry run. An earlier version had one: the hook wrote
records into `$XDG_RUNTIME_DIR/sudo-escalation-test/` when run as the user,
and the plugin watched that directory too. That let any process running as
the user, an agent included, put a sudo dialog on screen, so it is gone.

```
sudo true                                      # dialog, touch, approved
sudo sh -c 'true && echo two'                  # one command per line
omarchy-shell jra3.sudo-escalation status     # what the dialog holds
node plugin/SudoModel.test.js                  # parsing and layout
```

## Gotchas that cost time

- pam_exec runs its command as the caller's real uid, which under sudo is the
  user. `seteuid` is required on the PAM line.
- A `keepLoaded` service is not replaced on plugin hot-reload; edits take
  effect only after `omarchy-restart-shell`.
- An object passed through `createObject(parent, { entry: obj })` arrives as a
  copy. The pid watcher settling that copy left the dialog up forever. Pass
  scalars and look the live entry up.
- `FileView` needs `blockAllReads`, not just `blockLoading`: with only the
  latter, `text()` after a `path` change returns the previous file.
- A `FolderListModel` pointed at a directory that does not exist yet never
  wakes up, hence the tmpfiles entry and the plugin's probe timer.
- The old 0711 record directory could not be watched at all, and
  `inotify_add_watch` fails silently as far as the model is concerned.
- The installer itself costs about seven touches with `timestamp_timeout=0`.
