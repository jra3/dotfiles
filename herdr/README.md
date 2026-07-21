# herdr

Config for [herdr](https://herdr.dev) — a mouse-first terminal multiplexer / "terminal
workspace manager for AI coding agents" (tmux/zellij alternative with worktree, agent,
and remote-attach subcommands).

## What's tracked

Only `.config/herdr/config.toml` — the annotated default emitted by `herdr --default-config`,
with everything commented out except the settings we actively override:

- `[ui] agent_panel_sort = "priority"` — order the agent panel by attention queue.
- `[keys]` — tmux-style bindings mirroring `tmux/.config/tmux/tmux.conf`:
  - `prefix = "backtick"` — same prefix key as tmux.
  - `split_vertical = "prefix+|"` / `split_horizontal = "prefix+minus"` — `|` = side-by-side,
    `-` = stacked (matches tmux `bind | split-window -h` / `bind - split-window -v`).
  - `focus_pane_{left,down,up,right} = "alt+{left,down,up,right}"` — Alt+arrows, no prefix
    (tmux `bind -n M-Arrow select-pane`).

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

herdr itself is not managed by stow — it's a single static binary at `~/.local/bin/herdr`,
installed per the [official installer](https://herdr.dev/docs/install/) (`curl -fsSL
https://herdr.dev/install.sh | sh`) or by downloading the release binary directly.
Update in place with `herdr update`.
