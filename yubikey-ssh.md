# Project: YubiKey-backed SSH for GitHub

> Tracking doc. Goal: a hardware-backed SSH key on the YubiKey that lets me work
> with GitHub after entering a PIN **once per reboot**, with PIN-entry UX that
> matches the Bitwarden flow (SUPER+SHIFT+/).
>
> **Stow note:** this is a plain top-level `.md` file (not a package dir) on
> purpose, so `stow */` won't try to symlink it into `$HOME`. Move it into a real
> package later if/when there's config to deploy.

## Requirements

1. **SSH key on the YubiKey** (hardware-resident), registered with GitHub.
2. **One PIN entry per computer reboot**, then frictionless `git` over SSH.
3. **PIN-entry UX matches Bitwarden**: the Bitwarden flow is `rbw` + `rbw-agent`
   (`pinentry: pinentry-gnome3`, `lock_timeout: 3600`) with `walker` as the menu.
   i.e. a graphical pinentry dialog popped by an **in-session** agent, cached for
   a while. Target: the YubiKey PIN prompt should feel the same (GUI, not a
   terminal prompt buried in a tty).

### Decisions (locked 2026-06-04)
- **Approach: Option A — FIDO2 `ed25519-sk` (touch, NO PIN) + ControlMaster.**
  Chosen `touch, no pin` + `frictionless after unlock`; those reconcile only via
  connection multiplexing: one touch opens the master ("unlock"), every git op
  after is frictionless until the master dies.
- **PIN-prompt UX: N/A** — no auth-time PIN at all. (FIDO2 PIN is entered *once*
  at key-creation because the key is `resident`; never again.) So the
  Bitwarden-pinentry-matching question is moot for this approach.
- **Touch: frictionless after unlock** — touch once per session (master open),
  not per push.
- **Key is `resident`** (per original ask) → portable: regenerate the stub on any
  machine with `ssh-keygen -K`, no file copying.
- Doc home: top-level `yubikey-ssh.md` for now. The ssh config change is tracked
  in the `ssh/` package (`config.shared`).

## Chosen design

FIDO2 `ed25519-sk`, resident, touch-required, NO `verify-required` (no auth PIN).
GitHub gets the `sk-ssh-ed25519@openssh.com` public key. `~/.ssh/config` (via
tracked `config.shared`) sets `ControlMaster auto` + `ControlPersist` for
github.com so one touch per session covers all git ops. Software key
`id_ed25519_github` stays listed as a transitional fallback until validated.

## Implementation plan

1. **[USER — needs the YubiKey]** Generate the resident key (touch + enter the
   FIDO2 PIN once when prompted):
   ```
   ssh-keygen -t ed25519-sk -O resident -O application=ssh:github \
     -C "yubikey-fido2 jra3 2026-06" -f ~/.ssh/id_ed25519_sk
   ```
   Leave the passphrase empty (the touch is the second factor). Produces
   `~/.ssh/id_ed25519_sk` (key handle) + `.pub`.
2. **[CLAUDE — needs confirm, outward-facing]** Add pubkey to GitHub:
   `gh ssh-key add ~/.ssh/id_ed25519_sk.pub --title "yubikey-fido2 jra3 2026-06"`.
3. **[CLAUDE — done ahead of time]** ssh config: sk key first + ControlMaster
   block in `ssh/.ssh/config.shared`; github block removed from machine-local
   `~/.ssh/config`; `~/.ssh/sockets/` created.
4. **[USER + CLAUDE]** Validate: `ssh -T git@github.com` (touch once → "Hi jra3"),
   then a second `ssh -T git@github.com` should NOT prompt for touch (master
   reused). Confirm a real `git fetch` works.
5. **[CLAUDE — needs confirm]** Cleanup once validated: remove the dead PIV ECDSA
   key from GitHub; drop the `id_ed25519_github` fallback line; optionally
   `ykman piv reset` to wipe the blocked PIV slot 9a.

### Validation (2026-06-04) — ✅ WORKING
- Resident key generated: `~/.ssh/id_ed25519_sk` (`sk-ssh-ed25519@openssh.com`,
  application `ssh:github`, touch, no auth PIN). FIDO2 PIN entered once at creation.
- Added to GitHub `jra3` as "yubikey-fido2 jra3 2026-06" (id 153522183).
- `ssh -T git@github.com`: 1st call → one touch → "Hi jra3!". Master persists
  (`ssh -O check` → "Master running"). 2nd call → **0s, no touch** (master reused).
  git traffic confirmed flowing over the multiplexed socket.
- Note: "am-jallen software (2026-06)" on GitHub is a key *title* on the `jra3`
  account, not a separate account. The dead PIV ECDSA key is already gone from
  GitHub (no cleanup needed there).

### Cleanup (done 2026-06-04)
- [x] Dropped `id_ed25519_github` fallback from `config.shared` → github.com is
  now **hardware-only** (sk key only). Verified auth still works.
- [x] Removed the `am-jallen software (2026-06)` software key from GitHub `jra3`.
- [ ] `ykman piv reset` to wipe the blocked PIV slot 9a — **skipped** (user kept
  it; independent of the working FIDO2 setup).

### Open risk to watch
- ControlMaster master can be dropped by GitHub on long idle → next op re-touches
  (one more touch, no PIN). `ServerAliveInterval 60` mitigates. Acceptable per
  decision. If it proves annoying, revisit (e.g. a login-time `ssh -fNT` warmer).

## Key insight (2026-06-04)

The earlier PIV/yubikey-agent failure was **the systemd sandbox, not pinentry
itself.** `rbw-agent` pops the *same* `pinentry-gnome3` dialog successfully
because it is spawned **in-session** (on-demand by `rbw`, inheriting the Hyprland
graphical env), whereas `yubikey-agent` ran as a hardened systemd `--user`
service that couldn't host the gcr SystemPrompter. **Lesson: any PIN agent must
be launched in-session like rbw-agent, not as a sandboxed unit.**

## Options

### A — FIDO2 `ed25519-sk` + ControlMaster/ControlPersist
One touch+PIN opens a master connection to github.com; all git ops multiplex over
it → no further prompts until the master dies.
- ➕ GitHub-native `sk-` key; simplest crypto; PIN prompt on terminal (tty) — no
  daemon/pinentry battle. FIDO standard forbids PIN caching, but we cache the
  *connection* instead, sidestepping that entirely.
- ➖ "Once per **master lifetime**," not strictly per-reboot — GitHub drops idle
  masters; `ServerAliveInterval` extends but no guarantee. Per-host (github only).
- UX: prompt is terminal / `ssh-askpass`, not the gnome dialog (could be dressed
  up with a GUI/walker askpass).

### B — FIDO2 `ed25519-sk`, touch-only (no PIN)
No PIN ever; one **touch** per git op.
- ➕ Dead simple, robust, GitHub-native.
- ➖ Not "PIN once" — it's "touch every time, PIN never." Baseline for comparison.

### C — PIV slot, PIN policy = ONCE, in-session agent + GUI askpass
PIN once per key power-up (cached on-card until unplug/reboot), enforced on-card.
Touch policy independently configurable (never / 15s-cached / always).
- ➕ Genuinely "PIN once per reboot," **all hosts**, survives connection drops.
  Can match Bitwarden UX exactly by running the agent in-session with
  `pinentry-gnome3` (now proven to render via rbw).
- ➖ More moving parts (PKCS#11). Use Yubico's **`libykcs11.so`**, NOT OpenSC —
  OpenSC has known bugs ignoring PIV PIN-policy (re-prompts regardless).
  The "in-session agent renders pinentry" hypothesis still needs a clean test.

## What we've tried (history)

- **Current GitHub SSH = software key.** `~/.ssh/id_ed25519_github` +
  `IdentitiesOnly yes`, registered as "am-jallen software (2026-06)". No
  agent/PIN/touch. This is the working baseline we're trying to upgrade.
- **yubikey-agent (PIV) — ABANDONED (2026-06-03/04).** On-device PIV key, agent,
  GitHub registration, ssh_config all correct. ONLY blocker: PIN pinentry dialog
  wouldn't render from the **sandboxed systemd daemon** under Hyprland/wlroots.
  - Ruled out: wrong PIN, systemd sandbox (relaxed it), Qt6 plugin, env,
    pinentry-gnome3 (gcr SystemPrompter opened then instantly closed — no GNOME
    Shell to host it *from the daemon*).
  - Closest: `systemd-run --user --pipe` + `pinentry-qt` + pure-wayland popped a
    real dialog on a manual GETPIN, but the agent's own Assuan
    `OPTION display=`/`ttyname=` flipped pinentry back off pure-wayland.
  - Every failed attempt blocks the PIV PIN after 3 tries →
    `ykman piv access unblock-pin` (PUK) to recover.
  - **Reinterpreted (2026-06-04):** the daemon sandbox was the real culprit (see
    Key insight). Option C revisits PIV with an **in-session** agent instead.

### Leftovers to clean up
- `yubikey-agent` AUR pkg installed, service disabled.
- Dead YubiKey ECDSA key still on GitHub → `gh auth refresh -s admin:public_key`
  then delete.
- PIV slot 9a still holds the (blocked) key → `ykman piv reset` to wipe.

## Hardware / env facts
- Strix Halo Arch box, Hyprland/wlroots. No GNOME Shell.
- GitHub SSH uses `id_ed25519_github` software key today.
- Bitwarden: `rbw` + `rbw-agent` (not a systemd unit), `pinentry-gnome3`,
  `lock_timeout 3600`, `walker` menu via `bitwarden/.local/bin/bw-pick`.
- `ykman`, `yubico-piv-tool`, multiple pinentry-* binaries present.
</content>
</invoke>
