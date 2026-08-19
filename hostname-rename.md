# Renaming this machine: `am-jallen` -> `paperweight`

Runbook for the console session. Written 2026-08-19; the rename itself is
deliberately **not** done yet.

The old name was Antimetal-issued (`am-` + `jallen`) and Antimetal is no longer
relevant. `paperweight` is the desktop.

## Why this is done sitting at the machine

Nothing here *should* drop connectivity — the node key and the tailnet IP
`100.106.2.101` are untouched by a rename, so live SSH sessions, the exit-node
advertisement and Ollama all survive it. But "should" is doing real work in that
sentence, and this is the only desktop. Do it with a keyboard in front of you.

## Preparation already done (2026-08-19)

- **`ssh/.ssh/config.shared`** — `Host paperweight` stanza added; the old
  `Host am-jallen` entry converted into a legacy alias pointed at
  `100.106.2.101`. Committed and pushed, so other machines can pull *before* the
  rename: the alias is correct on both sides of the flip.
- **`~/jra3/genes/opencode.json`** — Ollama provider now
  `http://paperweight:11434/v1`. Local file, not a git repo, nothing syncs it.
  **This provider is dead until the rename lands** — that is the one thing the
  prep leaves broken on purpose.
- **`tailscale serve`** — reset. It was proxying
  `https://am-jallen.corgi-hammerhead.ts.net` to `127.0.0.1:13305`. Nothing was
  listening, but that is because **13305 is Lemonade** (`lemond`, AUR
  `lemonade-server-git`) and the service is stopped — not because the serve was
  abandoned. Removed rather than carried to the new name; if Lemonade comes back
  and wants a tailnet URL again:

  ```sh
  sudo tailscale serve --bg 13305      # -> https://paperweight.corgi-hammerhead.ts.net
  ```

## Reference values

Captured before the rename, for comparison afterwards.

| | |
|---|---|
| Old hostname | `am-jallen` |
| New hostname | `paperweight` |
| Tailnet IP (must not change) | `100.106.2.101` |
| MagicDNS suffix | `corgi-hammerhead.ts.net` |
| Machine ID | `acc11000e01d48c483c10fd3db81d092` |

Host keys are **not** regenerated, so these fingerprints must be identical
afterwards:

```
256  SHA256:nmBpfPUglQj5WPv1+0apN0o6J9GOr44ybdJzyVRDVE8  (ECDSA)
256  SHA256:ygaX6hWPDfiJkYhfDa3hLFF3FnaRUhAAR2CX7miisP4  (ED25519)
3072 SHA256:4dPhUdWTi5j/vWe+kpBTl9wUbtgzQAq8Wx8verdqoUs  (RSA)
```

They are reference only — `config.shared` sets `StrictHostKeyChecking no` and
`UserKnownHostsFile /dev/null` for `*.ts.net`, so tailnet SSH never records a
host key and nothing will prompt you to re-accept one.

## The rename

Have the Tailscale admin console open in a browser tab before starting.

**1. Snapshot the before-state** (so rollback has something to compare against):

```sh
hostnamectl
tailscale status | head -1
tailscale ip -4
```

**2. Rename the OS:**

```sh
sudo hostnamectl set-hostname paperweight
```

No `/etc/hosts` change. There is no `127.0.1.1` line today and NSS `myhostname`
resolves the local hostname fine; adding one just creates a second place the
name lives for the next rename to forget.

**3. Rename the Tailscale node:**

```sh
sudo tailscale set --hostname=paperweight
```

Both sides are set explicitly rather than letting the node name follow the OS
hostname implicitly. Implicit following works only while the name has never been
hand-edited in the admin console — if it ever was, the client-reported hostname
is silently ignored and you would be left thinking the rename worked.

## Verification

Every line of this should be green before you call it done.

```sh
hostnamectl | head -2                    # Static hostname: paperweight
tailscale status | head -1               # 100.106.2.101  paperweight  ...
tailscale ip -4                          # 100.106.2.101, unchanged
tailscale status --json | grep -m1 DNSName   # paperweight.corgi-hammerhead.ts.net.
tailscale serve status                   # No serve config
```

- **No `-1` suffix** on the node name. `chonky` / `chonky-1` both exist in the
  tailnet, so the failure mode is real — it means a stale node holds the name.
  Not expected here, `paperweight` is unclaimed. If it happens anyway: find and
  delete the offending node in the admin console, then re-run step 3. Failing
  that, rename in the console directly and accept that this pins the name and
  permanently decouples it from the OS hostname.
- **Exit node still advertised** — `tailscale status --json | grep -A3
  AdvertiseRoutes` should still show `0.0.0.0/0` and `::/0`. This one fails
  quietly and you would not notice for a week.
- **Ollama on the new name:** `curl -s http://paperweight:11434/api/tags | head -c 200`
- **From another machine** (cupcake), after it has pulled dotfiles:
  `ssh paperweight hostname` and `ssh am-jallen hostname` — both should print
  `paperweight`.

## Rollback

Same two commands, old name:

```sh
sudo hostnamectl set-hostname am-jallen
sudo tailscale set --hostname=am-jallen
```

The prepared config survives a rollback: the legacy `am-jallen` alias is
IP-based, so it keeps working either way. Only `opencode.json` would need its
URL put back.

## Afterwards

- Reboot at your convenience — hygiene, not correctness. Some things read the
  hostname once at start (cups regenerates `/etc/printcap`, which currently
  carries `rm=am-jallen`).
- `ssh` from a machine that has **not** pulled dotfiles still works —
  `CanonicalizeHostname` rewrites any bare name into the tailnet — but it
  connects as the *local* username. On cupcake that means `jallen@paperweight`,
  which fails. Pull dotfiles on cupcake.
- Cosmetic leftovers, harmless, clean up whenever: the `am-jallen` comment in
  `/etc/tsfilter.nft`, `root@am-jallen` in the ssh host key comments, the
  `# am-jallen` label in `git/.config/git/allowed_signers`, and prose mentions
  in `yubikey-ssh.md` / `pacman/configure-system`.
- Delete the legacy `Host am-jallen` block from `config.shared` once nothing
  reaches for the old name.
