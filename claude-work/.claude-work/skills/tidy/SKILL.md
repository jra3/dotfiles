---
name: tidy
description: Clean up merged branches and stale worktrees. Use when the user types `/tidy` to prune local branches whose PR is merged, remove worktrees on merged branches, and surface ambiguous branches/worktrees for manual review.
---

# tidy — prune merged branches and stale worktrees

A safe-by-default cleanup sweep. It **auto-deletes only what's provably in trunk** — local branches whose PR is MERGED, and worktrees sitting on a merged branch with no uncommitted files. Everything ambiguous — CLOSED-PR branches, no-PR branches, worktrees with uncommitted work — is **reported, never deleted**. Backup branches and active-but-unsubmitted work both look "PR-less," so the bar for automatic deletion is "merged," nothing weaker.

Run the passes in order. After each destructive step, report what changed.

## Pass 1 — merged branches (auto-delete)

`git prune-merged` deletes local branches whose PR is MERGED. It checks PR state via `gh`, so it catches squash-merges that `git branch --merged` misses, and it skips `main`/`master`, the current branch, and any branch checked out in a worktree.

```bash
git prune-merged            # deletes MERGED-PR branches
git prune-merged --closed   # additionally LISTS "closed, review manually: <branch>" — never deletes
```

Report each `pruned …` line. Surface the `closed, review manually:` lines as a list — a closed PR may be reopened, so leave the branch for the user to decide.

## Pass 2 — orphaned no-PR branches (report only)

Pass 1 silently skips branches with **no PR at all**. Some are live work not yet pushed (keep); some are abandoned scaffolds or `backup/*` branches (probably delete). There's no reliable local signal to tell them apart, so all of them are report-only.

Run it under `sh` (see [Why `sh`](#why-sh)):

```bash
sh <<'SH'
cur=$(git symbolic-ref --quiet --short HEAD)
wt=$(git worktree list --porcelain | sed -n 's#^branch refs/heads/##p')
for b in $(git for-each-ref --format='%(refname:short)' refs/heads/); do
  case "$b" in main|master|"$cur") continue;; esac
  printf '%s\n' "$wt" | grep -qxF "$b" && continue   # checked out in a worktree
  st=$(gh pr list --head "$b" --state all --limit 1 --json state --jq '.[0].state' 2>/dev/null)
  [ -n "$st" ] && continue                           # has a PR — pass 1 handled it
  echo "no PR, review manually: $b"
done
SH
```

List the `no PR` branches and ask before deleting any.

## Pass 3 — stale worktrees

For each **linked** worktree (never the main checkout): remove it only when its branch is MERGED and the tree has no uncommitted files. Keep everything else and say why. Run it under `sh` (see [Why `sh`](#why-sh)):

```bash
sh <<'SH'
MAIN=$(git worktree list --porcelain | awk '/^worktree /{sub(/^worktree /,""); print; exit}')
git worktree list --porcelain | awk '
  /^worktree /{sub(/^worktree /,""); p=$0}
  /^branch /{sub(/^branch refs\/heads\//,""); print p"\t"$0}' |
while IFS="$(printf '\t')" read -r path branch; do
  [ "$path" = "$MAIN" ] && continue
  dirty=$(git -C "$path" status --porcelain)
  st=$(gh pr list --head "$branch" --state all --limit 1 --json state --jq '.[0].state' 2>/dev/null)
  if [ "$st" = MERGED ] && [ -z "$dirty" ]; then
    git worktree remove "$path" && echo "REMOVED: $path [$branch] (merged)"
  elif [ "$st" = MERGED ]; then
    echo "KEEP — merged PR but uncommitted files (surface them): $path [$branch]"
  elif [ "$st" = CLOSED ]; then
    echo "REVIEW — PR closed: $path [$branch]"
  else
    echo "KEEP — active: $path [$branch] PR=${st:-none}"
  fi
done
git worktree prune   # clear admin entries for any worktrees deleted out-of-band
SH
```

For a `merged PR but uncommitted files` worktree, show the `git status --porcelain` output verbatim before proposing anything — the only unique content is whatever isn't committed.

Removing a worktree keeps its branch. If that branch's PR was merged, re-run pass 1 to sweep it now that it's no longer worktree-held:

```bash
git prune-merged
```

## Important

- **Auto-delete only MERGED.** Branches: MERGED-PR only. Worktrees: merged branch **and** clean tree only. Everything else is report-only.
- **Never `git branch -D` a no-PR or closed-PR branch** without explicit confirmation — `backup/*` branches and unpushed work both have no PR.

## Why `sh`

Passes 2 and 3 wrap their loops in `sh <<'SH' … SH`. In the user's interactive **zsh**, `git`/`gh` are resolved through mise's `command_not_found_handler`, which itself needs `mise` on `PATH`; inside loop bodies that handler intermittently fails (`command not found: git`), so a dirtiness check can silently return empty and a stale worktree looks clean. `/bin/sh` has no such hook, so the same calls resolve reliably — which is also why pass 1's `git prune-merged` (a `git` alias, run by git in `sh`) is unaffected. Don't "simplify" these blocks back into a bare zsh loop.

## What this skill does NOT do

- Push branches or open PRs — out of scope; it only deletes what's already merged.
- Exit/remove the *current* worktree — that's `/wtx`, which has the interactive clean/dirty gate.
- Delete `backup/*` branches or orphaned scaffolds on its own — it only lists them.
