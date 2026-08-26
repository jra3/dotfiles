# YubiKey-backed SSH — multi-machine reference

> How hardware-backed SSH works across the machines that share this repo. **Every
> machine has its own YubiKey holding its own resident keys**; nothing is copied
> between machines and no private key ever leaves the hardware.
>
> **Stow note:** this is a plain top-level `.md` file (not a package dir) on
> purpose, so `stow */` won't try to symlink it into `$HOME`. Move it into a real
> package later if/when there's config to deploy.

## The model

Each machine's YubiKey carries **resident (discoverable) FIDO2 credentials**, so
a rebuilt machine recovers its own keys with `ssh-keygen -K` — there is no backup
to restore and no file to copy between machines. Each key serves one of two
roles:

| Role | Application | Local path | Used for |
|---|---|---|---|
| **Auth** | varies per machine | `~/.ssh/id_ed25519_sk` | tailnet SSH, agent forwarding, `ssh -T git@github.com` |
| **Signing** | `ssh:gitsign` | `~/.ssh/id_ed25519_sk_gitsign` | `git commit` / `git tag` signatures |

Both paths are load-bearing: `~/.ssh/id_ed25519_sk` is one of OpenSSH's **default
identity filenames**, so it gets offered automatically with no `IdentityFile`
line anywhere — and `git/.config/git/config` hardcodes
`user.signingkey = ~/.ssh/id_ed25519_sk_gitsign.pub`. A key parked at any other
path is simply never used.

> **Git transport does NOT use these keys.** Commit `8dcefd1` routes
> `git@github.com:` and `ssh://git@github.com/` through `https://github.com/` via
> the `gh` credential helper, so `fetch`/`push` never touch the YubiKey. The auth
> key's remaining jobs are tailnet SSH, agent forwarding, and sanity checks.
> Signing is unaffected by that rewrite — see the touch caveat below.

## Machine registry

Mirrors `git/.config/git/allowed_signers`. Signing fingerprints are authoritative
(verified from `allowed_signers`); auth-key attribution is flagged where it is
inferred rather than confirmed.

| Machine | YubiKey | Auth key (application) | Signing key fingerprint |
|---|---|---|---|
| **chonky** | 5 Nano, `37196467` | `ssh:chonky-notouch` *(tailnet)* and `ssh:chonky-nopin` *(GitHub)*, plus `ssh:chonky` and `ssh:chonky-touch-no-pinnano` | `SHA256:bIzPlE8zNZrvpm8ZscwtSG9fB6lc36fq0fjQr+I/++A` |
| **cupcake** | 5 Nano, `37196474` | `ssh:github-cupcake` | `SHA256:Gy580sDeIFooogvoROCcfxfkYWEsgQqYPRQ0p9iyFiI` |
| **paperweight** | 5C Nano, `16946249` | `ssh:github` *(inferred by elimination — confirm with `ssh-keygen -K` on that machine)* | `SHA256:C+wONGjhNv/j57dyLl7xR8zoabSEd4ljSWz8GfkgBk0` |

Naming is **not** consistent across machines: chonky uses `ssh:<hostname>*`,
cupcake uses `ssh:github-<hostname>`, and the oldest uses a bare `ssh:github`.
Only the *file path* matters at runtime, so this is cosmetic — but it does mean
you cannot infer the owning machine from the application string alone. New
machines should use `ssh:<hostname>`.

### chonky's four auth keys (flags re-measured 2026-08-02)

All four are physically resident on the key. The first three are registered on
the GitHub account; `ssh:chonky-notouch` deliberately is **not** — it exists only
for tailnet SSH, so a stolen laptop cannot use it against GitHub.

| Application | Flags | Policy |
|---|---|---|
| `ssh:chonky-notouch` | `0x20` | **no touch, no PIN** — deployed as `~/.ssh/id_ed25519_sk_rk_chonky-notouch` for tailnet SSH |
| `ssh:chonky-nopin` | `0x21` | touch, no PIN — **deployed** as `~/.ssh/id_ed25519_sk` (GitHub, plus the paperweight fallback) |
| `ssh:chonky-touch-no-pinnano` | `0x21` | touch, no PIN — functional duplicate of the above |
| `ssh:chonky` | `0x25` | touch **and** PIN |

`ssh:chonky-touch-no-pinnano` is redundant with `ssh:chonky-nopin` — identical
policy, and the name looks like a typo'd `touch-no-pin` + `nano`.

Flags come from the on-disk stub, which is authoritative (see the `-K` gotcha
below). To re-measure, decode the private key's base64 body and read the byte
after the application string — bit `0x01` is user-presence, `0x04` is user
verification, `0x20` is always set.

**The application string appears more than once** (three times for a gitsign
key: the public section, the private section, and the comment). Only the private
section's is followed by the flags byte; take the occurrence whose next byte has
`0x20` set, or you will read `0x00` off the public one and conclude the key is
touchless when it isn't.

### Touchless tailnet auth to paperweight (added 2026-08-02)

Minted so unattended agent sessions can reach paperweight without a human present
to tap the key:

```
ssh-keygen -t ed25519-sk -O resident -O no-touch-required \
  -O application=ssh:chonky-notouch -C "chonky no-touch tailnet auth" \
  -N "" -f ~/.ssh/id_ed25519_sk_rk_chonky-notouch
```

The `-f` path matches what `ssh-keygen -K` would emit for that application, so a
rebuild recovers it to the path the configs already reference. Creating a
resident credential needs the FIDO2 PIN and one touch **at creation time only**.

Three pieces make it work; all three are load-bearing:

1. **paperweight's `~/.ssh/authorized_keys`** carries the key with the
   `no-touch-required` option. That option is *permission, not policy* — it lets
   the server accept a signature lacking the presence flag, but the credential
   must also have been minted `0x20` or the token still demands a tap. The line
   that was there before this change had the option on `ssh:chonky-nopin`
   (`0x21`), so it never actually skipped the touch.
2. **`ssh:chonky-nopin` stays in that `authorized_keys`** as a touch-required
   fallback, so a failure of the no-touch credential can't lock chonky out.
   Nothing else in paperweight's `authorized_keys` belongs to chonky.
3. **chonky's machine-local `~/.ssh/config`** pins the offer order for paperweight
   with two `IdentityFile` lines (no-touch first, fallback second) plus
   `IdentitiesOnly yes`. This is the part that actually decides which key signs,
   and there is no substitute for it — see below.

**Loading the key into the agent is not enough, and neither is agent order.**
Measured 2026-08-02: with the no-touch key added to the agent *first*, plain
`ssh paperweight` still offered `~/.ssh/id_ed25519_sk` and hung waiting for a tap
(`rc=124` after a 15 s timeout). OpenSSH ranks default/`IdentityFile` identities
ahead of agent-only keys regardless of agent load order, and `id_ed25519_sk` is a
default filename — so it wins every time, gets `PK_OK` from paperweight (it is
still authorized there as the fallback), and blocks on presence. Reordering
`~/.ssh/agent-keys` does **not** fix this. Only an explicit per-host
`IdentityFile` + `IdentitiesOnly yes` does.

Verified with `ssh -o ControlPath=none -o ControlMaster=no`: plain `ssh
paperweight` makes three consecutive fresh connections at ~830 ms each, `-v` shows
only the no-touch key offered and accepted, and no `Confirm user presence`
appears. **Always disable multiplexing when testing this** — the 8h master will
happily mask a broken key, and did during this work.

`IdentitiesOnly` does not disturb agent forwarding: `ssh-add -l` on paperweight
still lists all three of chonky's keys over the forwarded socket, so remote
commit signing with `ssh:gitsign` is unaffected. The block is scoped to paperweight
alone — `ssh -G cupcake` still reports `identitiesonly no`.

### Signing-key anomaly

All three machines use the same application string `ssh:gitsign`, distinguished
only by which YubiKey holds them. chonky's signing key is *additionally*
registered as an **authentication** key on GitHub — it shows up in
`https://github.com/jra3.keys`, which lists auth keys only, whereas cupcake's and
paperweight's do not. Harmless, but inconsistent.

## Bootstrapping a machine (validated on chonky, 2026-07-28)

The rebuild path, in the order that actually works.

1. **Install `libfido2` before anything else.** Without it,
   `/usr/lib/ssh/ssh-sk-helper` fails to load and *every* sk operation dies with
   a misleading `unexpected internal error`. It is in `packages-arch.txt`, but a
   rebuild needs it before the full package install finishes:
   ```
   sudo pacman -S --needed libfido2 stow
   ```
2. **Recover the resident keys** — needs the FIDO2 PIN and a touch. `-K` writes
   into the **current directory**, so `cd` first:
   ```
   cd ~/.ssh && ssh-keygen -K
   ```
   Files land as `id_ed25519_sk_rk_<application minus the "ssh:" prefix>`, which
   matches neither path the configs expect.
3. **Rename to the expected paths:**
   ```
   mv id_ed25519_sk_rk_<auth-app>      id_ed25519_sk
   mv id_ed25519_sk_rk_<auth-app>.pub  id_ed25519_sk.pub
   mv id_ed25519_sk_rk_gitsign         id_ed25519_sk_gitsign
   mv id_ed25519_sk_rk_gitsign.pub     id_ed25519_sk_gitsign.pub
   chmod 600 id_ed25519_sk id_ed25519_sk_gitsign
   ```
4. **Write machine-local `~/.ssh/config`** — not stowed, so a rebuild has none.
   It must include the shared config **last**, since `ssh_config` is
   first-match-wins and local overrides need to come first:
   ```
   Include ~/.ssh/config.shared
   ```
5. **Write `~/.ssh/agent-keys`** — host-local list read by `ssh-add-keys.service`.
   `pacman/configure-system` will seed it by globbing `~/.ssh/id_*sk*`, which on
   a freshly-recovered machine sweeps in **every** leftover `_rk_` key, including
   PIN-required ones. Write it by hand first (the script never overwrites an
   existing file) so the agent can't offer a PIN-gated key ahead of the
   touch-only one.
6. **Seed `known_hosts`** from GitHub's published keys instead of accepting
   trust-on-first-use — otherwise the first connection stops at an interactive
   prompt:
   ```
   curl -s https://api.github.com/meta | jq -r '.ssh_keys[] | "github.com \(.)"' >> ~/.ssh/known_hosts
   ```
7. **Verify**, in order:
   ```
   ssh -T git@github.com          # one touch → "Hi jra3!"
   ssh -O check git@github.com    # "Master running"
   ssh -T git@github.com          # instant, no touch (master reused)
   ```
8. **New machine only** (not a rebuild): run `setup-git-signing` to mint a fresh
   signing key, then commit the updated `allowed_signers` so other machines can
   verify this one's commits. A *rebuild* skips this — `ssh-keygen -K` already
   recovered the existing key and its `allowed_signers` line is still valid.

## Gotchas

- **`ssh-keygen -K` does not preserve `no-touch-required`.** Downloaded stubs come
  back with the user-presence bit set (`flags=0x21`) regardless of how the
  credential was originally created. OpenSSH then asks the authenticator for
  whatever the stub says, so the key demands a touch even if it was minted
  without one. Measured on chonky 2026-07-28: signing prompts
  `Confirm user presence`. `CLAUDE.md` describes `setup-git-signing` keys as
  "no-touch/no-PIN" — that claim does not survive a `-K` round trip. The on-disk
  stub's flags byte, not the doc, is authoritative. **This now applies to
  `ssh:chonky-notouch` too:** it is `0x20` on disk today, but recovering it on a
  rebuilt machine will hand back a `0x21` stub and silently reintroduce the
  touch. Re-check the flags byte after any `-K`, and patch it back to `0x20`
  rather than assuming the credential changed.

  **Patching it back is one command** (`ssh-keygen -p` sets FIDO options, not
  just passphrases). It rewrites the on-disk stub only — no token, no PIN, no
  touch, and the credential itself is untouched:

  ```
  ssh-keygen -p -O no-touch-required -P "" -N "" -f ~/.ssh/id_ed25519_sk_gitsign
  ```

  Validated on cupcake 2026-08-25: `-K` recovery came back `0x21`, this flipped
  it to `0x20`, and `git commit -S` with stdin closed then exited 0 and verified
  `G` with no touch. So a rebuild does NOT have to choose between key continuity
  and unattended signing — recover, patch, done. Generating a fresh key throws
  away the `allowed_signers` entry and the GitHub registration for nothing.

  This only works if the credential on the token was minted `no-touch-required`
  in the first place. The stub flag and the authenticator's own policy are
  separate; this edits the stub. If the credential requires presence, the token
  still demands a tap and the smoke test below will hang.
- **`commit.gpgsign = true` is global again (2026-08-21, GTD-38), so whether a
  commit needs a touch is decided by each machine's flags byte.** Commit
  `8dcefd1` made *transport* touchless; committing is touchless only where the
  gitsign stub is `0x20`. On chonky it is `0x21`, so an agent session with nobody
  present to tap the key hangs on commit. On paperweight it is `0x20`, and
  `git commit -S` with stdin closed exits 0 and verifies `G` (measured
  2026-08-21). Check the byte before assuming either.
- **A timed-out touch reports as a passphrase error.** `Couldn't sign message:
  incorrect passphrase supplied to decrypt private key` on an sk key almost
  always means "nobody touched it in time," not a bad passphrase.
- **Default identity filenames are the mechanism, and they outrank the agent.**
  There is no `IdentityFile` line for github.com in `config.shared`;
  `~/.ssh/id_ed25519_sk` works purely because OpenSSH probes that filename by
  default. An `id_ed25519_sk_rk_*` path is never offered on its own; the agent or
  an explicit config block has to name it. **But an agent-only key is always
  offered *after* the default-filename ones** — measured 2026-08-02, adding a key
  to the agent first does not get it offered first. When two keys are both
  authorized on a host and only one is acceptable, per-host `IdentityFile` +
  `IdentitiesOnly yes` is the only reliable lever. Renaming a key onto a default
  filename is the other option, and the reason `id_ed25519_sk` is so
  load-bearing.
- **`~/.ssh/sockets/` must exist** or every multiplexed connection fails — ssh
  won't create it. `pacman/configure-system` does.
- **No `ssh-askpass` installed** → `notify_start: exec(/usr/lib/ssh/ssh-askpass):
  No such file or directory` on each touch-required op. Harmless in a terminal
  (OpenSSH prints the prompt to stderr), but GUI-launched git operations get no
  visible "touch me" cue — just a silently blinking key.

## Design decisions (locked 2026-06-04, still current)

- **FIDO2 `ed25519-sk`, resident, touch-required, no auth PIN.** Resident so any
  machine can regenerate its stub with `ssh-keygen -K` — portable, no file
  copying. The FIDO2 PIN is entered *once at key creation*, never at auth time.
- **ControlMaster/ControlPersist for frictionless SSH.** `config.shared` sets
  `ControlMaster auto`, `ControlPath ~/.ssh/sockets/cm-%C`, `ControlPersist 8h`.
  One touch opens the master; everything after multiplexes over it for free. The
  FIDO standard forbids caching the *PIN*, so we cache the *connection* instead.
  *(Superseded for git by the HTTPS rewrite; still the mechanism for tailnet SSH.)*
- **Any PIN agent must run in-session, never as a hardened systemd unit.** See
  the key insight below.

### Key insight (2026-06-04)

The earlier PIV/`yubikey-agent` failure was **the systemd sandbox, not pinentry
itself.** `rbw-agent` pops the *same* `pinentry-gnome3` dialog successfully
because it is spawned **in-session** (on-demand by `rbw`, inheriting the Hyprland
graphical env), whereas `yubikey-agent` ran as a hardened systemd `--user`
service that couldn't host the gcr SystemPrompter. **Lesson: any PIN agent must
be launched in-session like rbw-agent, not as a sandboxed unit.**

## Rejected alternatives

- **B — touch-only, no ControlMaster.** A touch on *every* git op. Simple and
  robust, rejected as too much friction. Now largely moot: the HTTPS rewrite took
  git off the SSH path entirely.
- **C — PIV slot, PIN policy `ONCE`, in-session agent + GUI askpass.** Genuinely
  "PIN once per reboot," for *all* hosts, surviving connection drops — the only
  option that fully meets the original requirement. Rejected for complexity
  (PKCS#11), and it needs Yubico's **`libykcs11.so`**, not OpenSC (OpenSC has
  known bugs ignoring PIV PIN-policy and re-prompts regardless). Worth revisiting
  only if touch-per-commit becomes intolerable.
- **`yubikey-agent` (PIV) — ABANDONED 2026-06-03/04.** On-device key, agent,
  GitHub registration and `ssh_config` were all correct; the sole blocker was the
  PIN dialog refusing to render from the sandboxed daemon under Hyprland/wlroots.
  Ruled out along the way: wrong PIN, the systemd sandbox (relaxed it), Qt6
  plugin, env, `pinentry-gnome3`. Closest attempt: `systemd-run --user --pipe` +
  `pinentry-qt` + pure-wayland popped a real dialog on a manual `GETPIN`, but the
  agent's own Assuan `OPTION display=`/`ttyname=` flipped pinentry back off
  pure-wayland. Every failed attempt blocks the PIV PIN after 3 tries →
  `ykman piv access unblock-pin` (PUK) to recover.

## Open items

- [ ] **Touch-per-commit blocks unattended sessions.** Still open, but the
  tailnet work on 2026-08-02 narrowed it. Confirmed: a credential minted with
  `-O no-touch-required` lands at `0x20` and genuinely signs with no tap, so the
  *mechanism* works — the only question left is whether `ssh:gitsign` was minted
  that way. Cheapest test unchanged: flip the signing stub's flags byte `0x21` →
  `0x20` and try a commit. If it was minted no-touch, that fixes it locally with
  no re-registration; if the authenticator refuses, regenerate `ssh:gitsign` with
  `-O no-touch-required` (as `ssh:chonky-notouch` was) and update
  `allowed_signers` plus GitHub. Note the security tradeoff differs from the
  tailnet key: a no-touch *signing* key means malware on the laptop can mint
  signed commits in your name, which the tailnet key cannot do.
- [ ] Fix `CLAUDE.md`'s "no-touch/no-PIN" claim for `setup-git-signing` keys.
- [ ] Confirm `ssh:github` really is paperweight's (`ssh-keygen -K` on that box).
- [ ] Consider deleting the redundant `ssh:chonky-touch-no-pinnano` from GitHub
      and from the key.
- [ ] Consider dropping chonky's `ssh:gitsign` from GitHub's **auth** key list so
      signing keys stay signing-only, matching the other two machines.
- [ ] Install an `ssh-askpass` so GUI-triggered touch prompts are visible.
- [ ] chonky's PIV slot 9a still holds a blocked key — `ykman piv reset` to wipe.
      Independent of the working FIDO2 setup; deliberately skipped so far.
