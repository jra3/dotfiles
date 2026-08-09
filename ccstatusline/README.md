# ccstatusline

Claude Code's status line. `claude/.claude/settings.json` sets
`statusLine.command` to `npx -y ccstatusline@latest`; this package supplies the
layout that command reads, plus the one custom segment it shells out to.

```
stow ccstatusline
```

## Layout

Two rows (ccstatusline's middle row is intentionally empty):

| Row | Segments |
|---|---|
| top | context % remaining · **PR widget** · git worktree · git branch |
| bottom | session usage · reset timer · ⟨flex⟩ · weekly usage · weekly reset timer |

`colorLevel: 3` (truecolor) — fine in Ghostty.

## The PR widget

`.local/bin/cc-pr-widget` renders `PR #1234 * v 2c` for the current branch:

| Part | Meaning |
|---|---|
| `*` magenta / `x` dim | merged / closed |
| `o` dim | draft |
| `*` green / `!` red / `*` yellow | approved / changes requested / awaiting review |
| `v` `x` `~` | CI passed / failed / pending |
| `Nc` cyan | N inline review comments, `[bot]` authors excluded |

The PR number is an OSC 8 hyperlink — ctrl+click it. Antimetal repos link to
Graphite (stacked diffs live there); everything else links to GitHub, where a
Graphite URL would just 404.

Needs `gh` (authenticated) and `jq`. It stays silent — exit 0, no output — on
`main`/`master`, on a detached HEAD, on a non-GitHub remote, or when the branch
has no PR, so it costs nothing outside a PR workflow.

Results cache for 60s under `$XDG_CACHE_HOME/claude-statusline`, keyed on
**repo + branch**. The repo is part of the key because branch names recur across
checkouts and would otherwise serve each other's stale PR numbers.

## Gotchas

- **`commandPath` is a bare command name, resolved via `PATH`.** ccstatusline
  expands neither `~` nor `$HOME`, and this one `settings.json` is shared
  verbatim by machines whose usernames differ — so it cannot name a
  `/home/<user>` path at all. It does not need to: ccstatusline spawns the
  command through Node, which searches `PATH`, so a bare `cc-pr-widget` resolves
  to whatever `~/.local/bin/cc-pr-widget` this machine stowed. Verified by
  pointing `commandPath` at bare `hostname` and at `/usr/bin/hostname` — both
  render identically. The only requirement is that `~/.local/bin` is on `PATH`,
  which `zsh/.zshrc` sets and uwsm's env preloader exports into the Hyprland
  session — the same mechanism the bare `.desktop` `Exec=` lines in the
  `google-chrome` and `slack` packages already depend on.
- **Directory folding is wanted here** — the opposite of the `emacs` package.
  `~/.config/ccstatusline` becomes a symlink to this package's directory, so when
  ccstatusline's own config TUI rewrites `settings.json` the write lands in the
  repo. Without folding, `settings.json` would be a file symlink that a
  write-temp-then-rename replaces with a regular file, silently unstowing it.
  Do **not** pass `--no-folding` to this package.
- **Editing via the TUI edits the repo.** `npx ccstatusline@latest` with no stdin
  opens its editor; changes show up as a dirty working tree here. That is the
  intended workflow — it is what keeps the two machines from drifting again.
