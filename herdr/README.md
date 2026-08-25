# herdr

Config for [herdr](https://herdr.dev) — a mouse-first terminal multiplexer / "terminal
workspace manager for AI coding agents" (tmux/zellij alternative with worktree, agent,
and remote-attach subcommands).

## What's tracked

`.config/herdr/config.toml` — the annotated default emitted by `herdr --default-config`,
with everything commented out except the settings we actively override — plus the
`.local/bin/herdr-*` helper scripts the `[[keys.command]]` bindings shell out to:

- `[ui] agent_panel_sort = "priority"` — order the agent panel by attention queue.
- `[keys]` — tmux-style bindings mirroring `tmux/.config/tmux/tmux.conf`:
  - `prefix = "backtick"` — same prefix key as tmux.
  - `split_vertical = "prefix+|"` / `split_horizontal = "prefix+minus"` — `|` = side-by-side,
    `-` = stacked (matches tmux `bind | split-window -h` / `bind - split-window -v`).
  - `focus_pane_{left,down,up,right} = "alt+{left,down,up,right}"` — Alt+arrows, no prefix
    (tmux `bind -n M-Arrow select-pane`).

- `[[keys.command]]` — custom commands, each backed by a script in `.local/bin/`:
  - `prefix+f` → `herdr-fork-focused` — fork the focused Claude Code pane into a new tab.
  - `prefix+shift+c` → `herdr-tab-gitroot` — new tab at the git root. Complements the
    built-in `new_tab` (`prefix+c`), which follows the pane cwd. Resolves via
    `git rev-parse --show-toplevel` on the focused pane's `foreground_cwd`, so inside a
    linked worktree it lands on that **worktree's** root, not the main checkout; outside
    a git working tree it falls back to the pane cwd.

  - `prefix+shift+a` → `herdr-adopt-worktrees` — bulk-attach worktree provenance to
    workspaces that are sitting in a worktree checkout but were opened by hand, so they
    are worktrees by convention only. Complements the built-in `open_worktree`
    (`prefix+alt+g`), which picks one interactively. Idempotent, and skips any repo whose
    *main* checkout has no workspace, so it never invents one.

  All three read the focused pane from `herdr pane list` rather than `$HERDR_PANE_ID` —
  `type = "shell"` commands run detached and do not inherit the pane environment.

- `[ui.sidebar.agents]` — one-line agent rows, `["state_icon", "workspace", "tab", "$ctx"]`.
  The default second line (`agent`) is dropped because every pane here is claude, so it
  carried no information. `$ctx` (and `$model`, reported but not rendered) come from
  `claude/.claude/hooks/herdr-blocked-reason.sh`, which also publishes *why* a pane is
  blocked so the ask is readable from the sidebar.

## herdr-eventd

`.local/bin/herdr-eventd` + `.config/systemd/user/herdr-eventd.service` — a user daemon
that routes herdr agent state changes to the desktop. A pane going `blocked` raises a mako
notification carrying the blocked-reason label from the hook above; clicking it focuses
that pane.

It subscribes per-pane to `pane.agent_status_changed` (there is no global agent-status
subscription, and the global `pane.updated` is not emitted on status change), and
reconnects on `pane.agent_detected` to widen the subscription set — a connection accepts
exactly one `events.subscribe`. The script's header comment records the rest of the
measured constraints.

```bash
systemctl --user enable --now herdr-eventd.service
```

  Not mapped (no herdr keybinding equivalent): tmux's `=` copy-mode, `Ctrl-y` paste, and
  `X` kill-session. herdr also has no "double-tap prefix sends a literal backtick" behavior —
  the tmux `bind \` send-key \`` trick has no config analog.

herdr also writes runtime state into `~/.config/herdr/` (`*.sock`, `*.log`, `session.json`).
Those are **not** tracked; stow symlinks only `config.toml` into the existing dir, leaving
the runtime files in place.

## Deploy

```bash
stow herdr
herdr config check          # validate
herdr server reload-config  # apply to a running server (most UI settings apply live)
```

## Regenerate the default baseline

To re-pull the annotated default after a herdr upgrade (then re-apply overrides):

```bash
herdr --default-config > herdr/.config/herdr/config.toml
```

## Install

herdr itself is not managed by stow. **It comes from Omarchy's own pacman repo** —
`omarchy/herdr`, a prebuilt binary at `/usr/bin/herdr` — tracked in
`pacman/packages-arch.txt`. Install/update with `sudo pacman -S herdr` or via
`pacman/install-packages`; a regular `pacman -Syu` keeps it current.

**Do not install the AUR `herdr-bin`.** It is the same upstream binary at the same
version and `Provides: herdr`, so an AUR helper offers to tear out the repo package and
rebuild it — pure churn, and it takes herdr off Omarchy's upgrade path. This repo
tracked `herdr-bin` until 2026-08-25, when a fresh Omarchy 4.0.1 install turned out to
ship `herdr` in the `omarchy` repo already; the AUR entry was dropped from
`packages-aur.txt` that day so `pacman/install-packages` stops offering the swap.

Don't use `herdr update` either — the binary is pacman-managed.
