---
name: fix-pr
description: "Diagnose and fix a failing PR: read CI logs, identify root cause, fix in a worktree, verify locally, push via gt submit. Loops on CI failure; cleans up its worktree on exit. With a branch arg, runs in the background via a subagent."
user_invocable: true
arguments: "[branch-name]"
allowed-tools: "Bash(command:*), Read, Glob, Grep, Edit, Write, EnterWorktree, ExitWorktree, Agent"
---

# Fix PR

Diagnose and fix a failing PR by reading CI logs, applying the fix in a worktree, verifying locally, pushing via `gt submit`, and watching CI. If CI fails again, the skill loops back to diagnose. The worktree is cleaned up on exit (success or terminal failure).

## Dispatch

Behaviour depends on the arguments:

- **`--current-worktree` flag present** — run the whole fix-and-watch loop in the *current* worktree, switching it to the target branch in place. No new worktree, no background subagent. The target branch is the non-flag token in `$ARGUMENTS` (or current HEAD if none). Used by `/tend-stack`, which drives this skill from inside an existing worktree where `EnterWorktree` can't nest. See [Current-worktree mode](#current-worktree-mode) below.
- **Branch provided, no flag (`$ARGUMENTS` is a bare branch name)** — the main agent spawns a **background subagent** that owns the whole fix-and-watch loop, including worktree creation and cleanup. The main agent reports the agent ID and exits. See [Background dispatch](#background-dispatch) below.
- **No branch, no flag** — the main agent runs the steps inline in the foreground. The agent must already be in a worktree (per the project's worktree-only policy) or the change must qualify as a config-file exception. No worktree is created and none is cleaned up.

## Background dispatch

When `$ARGUMENTS` is non-empty, run **only** this dispatch — do not perform the steps yourself. Spawn a `general-purpose` subagent in the background, with the full execution prompt below. Then report the agent ID to the user and stop.

```
Agent(
  subagent_type: "general-purpose",
  description: "Fix PR for <branch>",
  isolation: "worktree",
  run_in_background: true,
  prompt: <execution prompt — see template below>,
)
```

`isolation: "worktree"` is essential — the subagent inherits the parent's CWD, so without it a parent that's already in a worktree would force the subagent to nest (and `EnterWorktree` refuses to nest). With isolation, the harness creates a fresh worktree off the parent's HEAD and roots the subagent there.

After the spawn:

1. Print `Spawned background fix-pr agent <id> for branch <branch>. You'll be notified when it completes.`
2. Stop. Do not poll. The harness will surface the result when the subagent finishes.

When the completion notification arrives:

3. Extract `<worktreePath>` from the task-notification.
4. Run `git worktree remove --force <worktreePath>` from the main repo root to drop the now-redundant worktree. The subagent has already committed and pushed via `gt submit`, so the branch's commits are on the remote and the local branch ref is in the shared object DB — nothing is lost. (The harness's `isolation: "worktree"` auto-cleanup only fires for *unchanged* worktrees, which is why this manual step is needed once the subagent has made commits.)
5. Relay the subagent's `<result>` block to the user.

Skip the worktree removal in step 4 only if the subagent reported a *failed* fix and the worktree might still be useful for the user to inspect — in that case, mention the path in the relay so the user can `cd` in and continue manually.

### Subagent execution prompt template

The subagent prompt must be self-contained — the subagent does not have access to `$ARGUMENTS`, this SKILL.md, or the surrounding chat. Embed the literal branch name and the full instructions inline. Use this template (replace `<BRANCH>`):

```
You are running the fix-pr workflow for branch <BRANCH> in the background.

Goal: get CI green on the open PR for this branch, looping if necessary.

Hard rules:
- The harness has already given you an isolated worktree — your CWD on start IS your worktree. Do NOT call `EnterWorktree` (it refuses to nest). Do NOT use `git worktree add`.
- Cleanup is parent-managed — the dispatching agent will run `git worktree remove --force` on your worktree after receiving your completion notification. Just exit cleanly when done. Do NOT call `ExitWorktree`, do NOT try to remove the worktree yourself, and do NOT `cd` out of it before emitting the final report.
- Use `gt submit --no-interactive` (never `git push` + `gh pr create`).
- Never post comments or descriptions to the PR. Just report when done.
- Per styleguide:fix-root-cause, fix the root cause, not the symptom.
- Cap the diagnose→fix→push→watch loop at 3 iterations. On iteration 4, stop and report.

Workflow:

1. Resolve the PR.
   gh pr list --head "<BRANCH>" --state open --json number,url,headRefName,baseRefName,title --limit 1
   If no open PR, exit and report. Stop.

2. Switch your worktree to the target branch.
   - You start in a harness-provided worktree off the parent's HEAD, on a fresh branch (not <BRANCH>).
   - Fetch and switch:
       git fetch origin <BRANCH>
       git switch <BRANCH>
   - If `git switch` fails because the branch is checked out elsewhere, release that checkout first:
       git -C <other-checkout-path> switch --detach
       git switch <BRANCH>
   - Confirm: git rev-parse --abbrev-ref HEAD

3. Loop (max 3 iterations):
   a. gh pr checks "$PR_NUMBER" — if all green, break.
   b. For each failure, fetch logs:
      - Vercel: extract dpl_<id> from targetUrl, run `vercel inspect dpl_<id> --logs 2>&1 | tail -300`. Filter for `error TS`, `error:`, `ELIFECYCLE`, `command finished with error`. (Run `vercel switch antimetal` once if access errors.)
      - GitHub Actions: `gh run view <run-id> --log-failed | tail -300`. Use `gh run view <run-id>` first to find the failing job if needed.
   c. Diagnose root cause (see common-patterns table below).
   d. Apply a surgical fix. Match existing style.
   e. Verify locally:
        cd app
        turbo build --filter=@am/<pkg>^...
        turbo build --filter=@am/<pkg>
        turbo check-types --filter=@am/<pkg>
        turbo lint --filter=@am/<pkg>
      `Cannot find module '@am/*'` is never acceptable — it means you skipped the `^...` build.
      If lint reports prettier issues: `turbo lint:fix --filter=@am/<pkg>` then re-lint.
      If any verification fails, do NOT push. Re-diagnose.
   f. Commit. Amend if the fix is naturally part of the latest commit's intent; otherwise new commit `fix(<pkg>): <reason>`.
   g. Submit: `gt submit --no-interactive` (use `--force` only if you intentionally rebased).
   h. Watch: `gh pr checks "$PR_NUMBER" --watch --fail-fast`.
      - All green → break.
      - A check failed → continue to next iteration.

4. Report exactly:
   PR #<num>: <title>
   Iterations: <n>
   Root cause(s): <one-line per iteration>
   Fix(es): <one-line per iteration>
   Final CI: <pass/fail>
   PR:        https://github.com/antimetal/overlook/pull/<num>
   Graphite:  https://app.graphite.com/github/pr/antimetal/overlook/<num>

Common root-cause patterns:
| Symptom | Likely root cause |
|---|---|
| `error TS2694: Namespace 'X' has no exported member 'Y'` | Upstream rename in a sibling package didn't propagate |
| `error TS2322: Type X is not assignable to Y` | Schema-shape change wasn't applied to the consumer |
| `Cannot find module '@am/*'` | Missing `dist/` — build deps first. Never "pre-existing." |
| `prettier/prettier` errors | `turbo lint:fix --filter=@am/<pkg>` |
| Test failures | Read the assertion: expected vs. actual |

If the diagnosis is "this is a codebase-wide issue affecting 4+ other packages", per feedback_codebase_wide_vs_pr_blockers, stop the loop and report — don't block the single PR.

Per feedback_unsmoke_tested_pr_default_draft, if the fix introduced new logic the user hasn't manually exercised, prefer `gt submit --draft --no-interactive`. Re-pushing a CI-only fix to an already-non-draft PR is fine.

Per feedback_review_resolve_loop_in, do not auto-resolve human review threads. This skill addresses CI only.
```

End of subagent prompt template.

## Current-worktree mode

Triggered by `--current-worktree` in `$ARGUMENTS`. Runs entirely in the current worktree — no `EnterWorktree`, no `git worktree add`, no background subagent. Used by `/tend-stack`, which drives this skill from inside an existing worktree where nested worktree creation isn't possible.

1. Parse the target branch: the non-flag token in `$ARGUMENTS`. If there is none, use current HEAD.
2. Record the starting branch: `ORIG_BRANCH="$(git rev-parse --abbrev-ref HEAD)"`.
3. Switch the current worktree to the target branch (skip if it's already current):
   ```bash
   git fetch origin <BRANCH>
   git switch <BRANCH>
   ```
   If `git switch` fails because the branch is checked out in another worktree, **do not** force-release that checkout. Print `Skipped <BRANCH>: checked out in another worktree (<path>).` and go straight to step 5.
4. Run [Foreground execution](#foreground-execution-no-branch-arg) Steps 1–9 against this branch.
5. **Always restore the starting branch** — on success, terminal failure, the 3-iteration cap, or a skip: `git switch "$ORIG_BRANCH"`. The worktree must end on the branch it began on; this mode never leaves it switched.

## Foreground execution (no branch arg)

If `$ARGUMENTS` is empty, the agent runs the steps below itself, in its current worktree. No worktree is created and none is cleaned up. (Current-worktree mode also routes here, after switching the worktree to the target branch — see above.)

### Step 1: Determine target branch and PR

```bash
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" = "HEAD" ] && { echo "Detached HEAD — pass an explicit branch name"; exit 1; }

gh pr list --head "$BRANCH" --state open --json number,url,headRefName,baseRefName,title --limit 1
```

If no open PR exists for the branch, tell the user and stop.

### Step 2: Read failing CI checks

```bash
gh pr checks "$PR_NUMBER"
```

For each failure, fetch the underlying logs.

**Vercel checks** (`Vercel – overlook`, `Vercel – storybook`, etc.). Extract the deployment ID from the targetUrl (e.g. `dpl_BZTo...`) and inspect:

```bash
# First-time use only:
vercel switch antimetal

vercel inspect dpl_<id> --logs 2>&1 | tail -300
```

Filter for `error TS`, `error:`, `ELIFECYCLE`, `command finished with error` — those are the lines that pinpoint the failure.

**GitHub Actions checks**. Use the run ID from the targetUrl:

```bash
gh run view <run-id> --log-failed | tail -300
```

If the build phase that failed isn't obvious, run `gh run view <run-id>` first to see the job summary.

### Step 3: Diagnose root cause, not symptom

Per `styleguide:fix-root-cause`, identify the *originating* mistake — not the surface error.

Common patterns:

| Symptom | Likely root cause |
|---|---|
| `error TS2694: Namespace 'X' has no exported member 'Y'` | An upstream rename in a sibling package didn't propagate to consumers |
| `error TS2322: Type X is not assignable to Y` | Schema-shape change (e.g. discriminator added/renamed) wasn't applied to the consumer |
| `Cannot find module '@am/*'` | Missing `dist/` — build deps first (CLAUDE.md type-checking protocol). NEVER acceptable to dismiss as pre-existing |
| `prettier/prettier` errors | Run `turbo lint:fix --filter=@am/<pkg>` |
| Test failures | Read the assertion that failed and the expected vs. actual |

If the diagnosis is "this is a codebase-wide issue affecting 4+ other packages", per `feedback_codebase_wide_vs_pr_blockers` propose a sweep — don't block the single PR.

### Step 4: Apply the fix

Edit the failing file(s). Follow `agents.md` "Surgical changes": every changed line must trace back to the root cause. Don't reformat adjacent code or refactor untouched files.

Match the existing style in the file (e.g. naming convention for evaluator bindings, comment density, factory patterns).

### Step 5: Verify locally

Always build dependencies before type-checking (CLAUDE.md type-checking protocol). `Cannot find module '@am/*'` is never acceptable.

```bash
cd app
turbo build --filter=@am/<pkg>^...     # transitive deps first
turbo build --filter=@am/<pkg>          # the package itself
turbo check-types --filter=@am/<pkg>    # explicit type-check
turbo lint --filter=@am/<pkg>           # lint
```

If lint reports prettier/format errors:

```bash
turbo lint:fix --filter=@am/<pkg>
turbo lint --filter=@am/<pkg>           # confirm clean
```

If any verification step fails, return to Step 3 — the diagnosis was incomplete. **Do not** push partial fixes.

### Step 6: Commit

Inspect the diff before committing:

```bash
git diff --stat
git diff
```

Choose between:

- **Amend the latest commit** if the fix is naturally part of that commit's intent — e.g. the latest commit introduced the new types that exposed the bug. This keeps the stack history clean.
  ```bash
  git add <files>
  git commit --amend --no-edit
  ```
- **New commit** with a `fix(<pkg>): <reason>` subject if the fix is conceptually independent.
  ```bash
  git add <files>
  git commit -m "fix(<pkg>): <one-line subject>"
  ```

If creating a new commit, follow the `git-commits` skill conventions (Co-Authored-By trailer, etc.).

### Step 7: Submit via Graphite

Per `feedback_graphite_submit`, **never** use `git push` + `gh pr create` per branch — it breaks Graphite's stack view. Always:

```bash
gt submit --no-interactive
```

If `gt` rejects the submit with "Branch X has been updated remotely" but you've intentionally rebased onto a newer base locally, force the submit:

```bash
gt submit --no-interactive --force
```

Avoid `--stack` unless the user explicitly wants the whole stack force-pushed — siblings may have local-only state the user isn't ready to publish.

If reviewer routing is sensitive (e.g. memory `feedback_anvil_sai_reviewer`), strip the unwanted reviewers after push:

```bash
gh pr edit "$PR_NUMBER" --remove-reviewer antimetal/<team>
```

### Step 8: Watch CI, loop on failure

```bash
gh pr checks "$PR_NUMBER" --watch --fail-fast
```

- **All green** → continue to Step 9.
- **A check failed** → return to Step 2 (re-read failures). Cap the loop at 3 iterations total. On the 4th attempt, stop and hand back to the user — repeated failure means the diagnosis is wrong or the problem is out of scope.

### Step 9: Report

Print a summary:

```
PR #<num>: <title>
Iterations: <n>
Root cause(s): <one-line per iteration>
Fix(es): <one-line per iteration>
Final CI: <pass/pending/fail>
PR:        https://github.com/antimetal/overlook/pull/<num>
Graphite:  https://app.graphite.com/github/pr/antimetal/overlook/<num>
```

Per memory `feedback_pr_writing_user_voice`, do **not** post comments or descriptions to the PR on the user's behalf without explicit approval. Just report.

## Important Notes

- **Worktree-only policy.** Source-code edits must happen in a worktree, never the root. Use `EnterWorktree` (the harness tool), not `git worktree add`. Reading, searching, and git queries are fine in root. **Current-worktree mode** (`--current-worktree`) satisfies this by running inside the caller's existing worktree — it switches that worktree's branch in place and restores it on exit, never touching root and never creating a worktree.
- **Background mode runs in a harness-provided worktree.** When dispatched with a branch arg, the spawn uses `isolation: "worktree"` — the harness creates the worktree and roots the subagent there. The subagent does NOT call `EnterWorktree`/`ExitWorktree`. The harness's auto-cleanup only fires for *unchanged* worktrees, so once the subagent commits and pushes, the worktree is preserved. The parent dispatcher cleans it up explicitly via `git worktree remove --force <worktreePath>` after the completion notification arrives (see [Background dispatch](#background-dispatch)). If a notification is missed (e.g. the user resumes in a different conversation), `git worktree prune` + `git worktree list` shows what's left for manual cleanup.
- **Loop cap.** The diagnose→fix→push→watch loop is capped at 3 iterations. After that, hand back to the user with a clear summary of what was tried.
- **No silent force-push of the whole stack.** Default to single-branch `gt submit`. Force the parent only when you've consciously rebased it onto a newer base.
- **Don't auto-resolve human review threads.** This skill addresses CI, not review feedback. If unresolved threads exist, mention them and let the user resolve (per `feedback_review_resolve_loop_in`). Use `/address-pr-feedback` for review work.
- **Don't dismiss type errors as pre-existing.** Verify on the parent commit before claiming a TS error is unrelated. `Cannot find module '@am/*'` is always a missing build step (CLAUDE.md).
- **Untested PRs default to draft.** If the fix introduced new logic the user hasn't manually exercised, prefer `gt submit --draft` (per `feedback_unsmoke_tested_pr_default_draft`). Re-pushing a CI-only fix to an already-non-draft PR is fine.

## Error Recovery

- **`vercel inspect` returns "You do not have access"**: run `vercel switch antimetal` once.
- **`gt submit` fails for an unrelated parent branch**: read the message; if the parent has been *intentionally* rebased locally, use `--force`. If not, run `gt sync` first.
- **`git switch <BRANCH>` fails with "branch is already checked out"**: another worktree has it. Find it with `git worktree list`, then `git -C <other-checkout-path> switch --detach` and retry.
- **Build fails with `Cannot find module '@am/*'`**: you skipped `turbo build --filter=@am/<pkg>^...`. Run it.
- **Loop hit the 3-iteration cap**: stop and report what was tried and what's still failing. Don't keep flailing.
- **Stale background worktrees accumulate**: `git worktree prune` to drop stale references; `git worktree list` to see what's parked.
