---
name: tend-stack
description: "Tend the current graphite stack — find the downstack-most branch with PR review feedback or CI failures, fix it via /address-pr-feedback and/or /fix-pr, then gt sync and restack the upstack locally. Handles one branch per run; re-runnable and /loop-friendly."
user_invocable: true
arguments: "[branch-name | --dry-run]"
allowed-tools: "Bash(command:*), Read, Glob, Grep, Edit, Write, EnterWorktree, ExitWorktree, Skill, TodoWrite"
---

# Tend Stack

Walk the graphite stack that contains the current branch, find the **downstack-most** branch that has unresolved PR review feedback or failing CI, fix it by delegating to `/address-pr-feedback` and/or `/fix-pr`, then `gt sync` and restack the upstack so the rebase propagates to children.

**One branch per invocation.** The skill fixes a single branch — the one closest to trunk with issues — then exits. Fixing the base first is what makes restacking the children meaningful. Re-run (or wrap in `/loop`) to walk up the stack one branch at a time until it's clean.

## Arguments

- _(none)_ — auto-select the downstack-most branch with issues in the stack containing the current branch.
- `<branch-name>` — tend exactly this branch. Step 1 **resolves** it first (local / remote / worktree / open PR) and anchors stack discovery on it, so this works even when you're sitting on `main` or in another stack. If the branch doesn't exist or has no open PR, the skill stops with a precise diagnosis instead of silently finding nothing.
- `--dry-run` — run discovery and selection, print the plan, then stop without touching anything.

## How this composes with the sub-skills

This skill **delegates** the actual fixing; it does not reimplement it. Know what each sub-skill owns:

- **`/address-pr-feedback <PR#>`** creates its **own** worktree, addresses unresolved review threads, `git push`es, resolves the threads, watches CI, and cleans up. Note it uses a plain `git push` (graphite-unaware) — that's exactly why this skill runs `gt sync` afterward to repair the stack.
- **`/fix-pr`** (no arg) runs in the **foreground** and requires you to already be in a worktree checked out on the target branch. It diagnoses CI, fixes the root cause, verifies locally, `gt submit`s, and watches CI (loops up to 3×).

Because both paths call `EnterWorktree` (which refuses to nest) and `/fix-pr` needs a worktree, **this skill must run from the main checkout, not from inside a worktree.** Step 0 enforces that.

## Execution

Track progress with TodoWrite. Execute in order; stop and report on any unexpected failure.

### Step 0: Ensure you are in the main checkout, not a worktree

```bash
TOPLEVEL="$(git rev-parse --show-toplevel)"
echo "$TOPLEVEL"
```

If the path contains `/.claude/worktrees/`, you are nested in a worktree. Call `ExitWorktree(action: "keep")` to return to the main checkout (this preserves the worktree and its branch), and tell the user you did so. The sub-skills and the foreground `/fix-pr` path can only create worktrees from a non-nested checkout.

Do **not** discard the worktree — `keep` only. If `ExitWorktree` refuses because of uncommitted changes, stop and ask the user to commit or stash first.

### Step 1: Resolve the anchor branch and identify its stack

First decide which branch anchors the stack — **don't assume it's HEAD**:

- **No argument** — anchor on the current branch: `BRANCH="$(git rev-parse --abbrev-ref HEAD)"`. If that is `main`/trunk, there is no stack to tend — report and stop.
- **`<branch-name>` argument** — *resolve* it before anything else; don't assume it exists or that it belongs to the current branch's stack:

  ```bash
  ARG="<branch-name>"
  git worktree list --porcelain | grep -qF "branch refs/heads/$ARG" && echo "IN_WORKTREE"
  git show-ref --verify --quiet "refs/heads/$ARG" && echo "LOCAL"
  git ls-remote --heads origin "$ARG" | grep -q . && echo "REMOTE"
  gh pr list --state open --head "$ARG" --json number --jq '.[0].number // "NO_PR"'
  ```

  Classify the result — these are the only valid outcomes:

  | Resolution | Action |
  |------------|--------|
  | Open PR exists (wherever the branch lives, including another worktree) | Set `BRANCH="$ARG"` and anchor discovery here. A worktree-resident branch is **fine** — the sub-skills make their own worktrees, and Step 5 already handles "checked out elsewhere." |
  | Branch exists (local/remote/worktree) but **no open PR** | **Stop.** "Branch exists but has no open PR — run `gt submit` to create one. `tend-stack` only tends branches that already have a PR." |
  | **No such branch anywhere** | **Stop.** If `$ARG` looks like a Linear *suggested* name (`<login>/eng-NNNN-…`), say so: the work likely hasn't started (confirm via the issue status if useful). Point the user at `/wt` to check out an existing branch, or at starting the work. `tend-stack` does **not** create branches — that would break `styleguide:single-responsibility`. |

Then confirm the anchor branch is graphite-tracked:

```bash
graphite log short 2>&1 | grep -F "$BRANCH" || echo "NOT_TRACKED"
```

If the branch is not tracked by graphite (e.g. it was fetched via `/wt`), the sync/restack seam can't run — report that and stop.

Reconstruct the stack from open PRs, which gives you the parent/child chain, the author, and the PR number in one query:

```bash
gh pr list --state open --json number,headRefName,baseRefName,title,url,author,isDraft --limit 200
```

Build a graph where each PR's `baseRefName` is the parent of its `headRefName`. The **current stack** is the connected component (following base→head links, excluding trunk `main`) that contains `$BRANCH`. Order branches by depth from trunk: depth 1 is the branch whose base is `main`.

**Scope to your own work.** Get your login with `gh api user --jq .login` and, by default, consider only branches whose PR `author.login` matches it. This guards against tending a teammate's branch in a shared stack. If the stack is intentionally collaborative, note the skip and relax the filter.

Branches without an open PR cannot have feedback or CI and are skipped.

### Step 2: Detect issues per candidate branch

For each branch in the stack (in trunk→tip order), determine whether it has issues:

**CI failure** — any check in a failing/error state (pending does not count as a failure for selection):

```bash
gh pr checks <PR#> --json name,state,bucket 2>/dev/null || gh pr checks <PR#>
```

Treat `bucket: "fail"` (or a `fail`/`error` row in the text output) as a CI failure.

**Unresolved review feedback** — at least one unresolved review thread:

```bash
gh api graphql -f query='
query {
  repository(owner: "OWNER", name: "REPO") {
    pullRequest(number: PR_NUMBER) {
      reviewThreads(first: 100) { nodes { isResolved } }
    }
  }
}' --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)] | length'
```

A non-zero count means the branch has feedback. (Get `OWNER`/`REPO` via `gh repo view --json owner,name -q '.owner.login + "/" + .name'`.)

### Step 3: Select the branch

Among branches with at least one issue (feedback or CI failure), pick the **downstack-most** — smallest depth from trunk. If a `<branch-name>` argument was given, it was already resolved and validated in Step 1 — tend that branch.

If no branch has issues, report "stack is clean — nothing to tend" and stop.

If `--dry-run`, print the selected branch, its PR, what issues it has, and the planned actions, then stop.

### Step 4: Address review feedback (if any)

If the selected branch has unresolved feedback, invoke `/address-pr-feedback <PR#>`. It owns its worktree, pushes the fixes, resolves the threads, and watches CI.

- If it reports CI green afterward and the branch had no separate CI failure, the branch is done — go to Step 6.
- If it reports CI **failed**, it leaves its worktree behind. Note the path; you will re-fix CI in Step 5 (which uses a fresh worktree), so this leftover can be cleaned up at the end with `git worktree remove --force <path>`.

### Step 5: Fix CI (if still failing)

Re-check `gh pr checks <PR#>`. If CI is still failing (or the branch had only a CI issue), run the foreground `/fix-pr` path:

1. `EnterWorktree(name: "<slug>")` where `<slug>` is the branch's last `/`-segment, trimmed to ≤ 64 chars.
2. Switch the worktree to the target branch:
   ```bash
   git fetch origin <BRANCH>
   git switch <BRANCH>
   ```
   If `git switch` fails because the branch is checked out in another worktree, **stop and report** — do not forcibly detach the user's other checkout.
3. Invoke `/fix-pr` (no argument) — it runs its diagnose→fix→submit→watch loop in this worktree.
4. `ExitWorktree(action: "remove")` once it finishes.

### Step 6: Sync and restack the upstack (locally)

From the main checkout, propagate the fix down the stack and rebase the children:

```bash
graphite sync --no-interactive -d
graphite restack --upstack --branch <BRANCH> --no-interactive
```

- `gt sync -d` pulls trunk, auto-deletes merged/closed branches, and restacks every branch it can without conflict.
- The explicit `--upstack` restack guarantees the descendants of the fixed branch are rebased and **surfaces any conflict** `sync` skipped. With `--no-interactive`, a conflict aborts rather than dropping into an interactive rebase — if either command reports a conflict or non-zero exit, **report it and stop. Do not attempt to auto-resolve.**

**Children are restacked locally only — they are not submitted.** Their remote PRs stay behind until the user runs `gt submit` themselves. Do not push the children.

### Step 7: Report

Print a summary:

```
Stack: <trunk>..<tip>  (<n> branches)
Tended: <BRANCH>  (PR #<num>)
  Feedback: <addressed/none>   CI: <fixed/already-green/none>
Sync: <branches deleted, if any>
Restack: upstack restacked locally — run `gt submit` to publish children
Remaining with issues: <list, or "none">

Re-run /tend-stack to handle the next branch, or wrap it in /loop.
```

List the other stack branches that still have issues so the user knows what a re-run will pick up next.

## Important notes

- **Runs from main, leaves you on main.** Step 0 pops you out of any worktree (keeping it). You will end on the main checkout; re-enter your worktree with `EnterWorktree` if you were mid-task.
- **One branch per run, downstack-first.** This is deliberate — fixing the base before restacking children is the only order that makes the restack meaningful. Re-run to walk up.
- **Delegation, not reimplementation.** All fixing goes through `/address-pr-feedback` and `/fix-pr`. This skill only does selection + the graphite sync/restack seam. If you find yourself editing source here, you have drifted from the design.
- **Children restack locally only.** Per the design decision, the upstack is rebased but never auto-submitted. Report what needs `gt submit`; let the user publish.
- **Conflicts stop the run.** A restack conflict is reported, never auto-resolved.
- **Untracked current branch.** If the current branch isn't in graphite (e.g. fetched via `/wt`), there is no stack — report and stop.
- **The branch argument is resolved, not assumed.** Step 1 locates `<branch-name>` (local / remote / worktree / PR) and anchors discovery on it, so a named branch works even from `main`. A branch that doesn't exist, or exists without an open PR, stops the run with a diagnosis — `tend-stack` never creates branches.
- **Don't tend teammates' branches by default.** The author filter in Step 1 scopes to your own PRs unless you explicitly relax it.

## Error recovery

- **`ExitWorktree` refuses (uncommitted changes)**: ask the user to commit/stash, then re-run. Never discard.
- **`git switch <BRANCH>` says "already checked out"**: another worktree holds it. Report the path (`git worktree list`); don't forcibly detach it.
- **`/address-pr-feedback` left a worktree after CI failure**: clean it up with `git worktree remove --force <path>` after Step 5, or mention the path so the user can inspect.
- **`gt sync`/`gt restack` reports a conflict**: stop and report the branch(es); the user resolves manually (`gt restack --upstack` interactively).
- **`gh pr checks` shows only pending**: not a failure — treat as "no CI issue" for selection. The sub-skills' own `--watch` handles in-flight CI.
- **Argument branch doesn't exist anywhere**: likely a Linear *suggested* name for an unstarted issue. Stop and point the user at `/wt` or at starting the work — do not create the branch.
- **Argument branch exists but has no open PR**: stop and tell the user to `gt submit` first; there is no PR to read feedback or CI from.
