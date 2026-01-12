# Current Architecture Analysis

## `tmux-new-session` (alias: `tn`)
**Location:** `tmux/.local/bin/tmux-new-session`

Creates a new tmux session with:
- Random name generation (e.g., "cosmic-falcon", "silent-mountain") or custom name as argument
- Window 0: named "claude", auto-launches `claude`
- Window 1: named "main", general purpose
- Starts a dedicated Emacs daemon per session (unique server name stored in `EMACS_SERVER_NAME` env var)
- Attaches to existing session if name already exists

## `tmux-worktree` (alias: `twt`)
**Location:** `tmux/.local/bin/tmux-worktree`

Creates a git worktree + matching tmux session:
- Usage: `twt <branch-name>`
- Creates worktree at `../<repo>-<branch>/` based on main/master
- Same session structure as `tmux-new-session` (claude window, main window, dedicated Emacs daemon)
- Reuses existing worktree/session if already exists

## Notes

Both scripts share a lot of duplicated code (lines 56-101 in `tmux-worktree` mirror `tmux-new-session`).
