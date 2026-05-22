---
name: address-pr-feedback
description: "Address PR review feedback: checkout in worktree, fix comments, resolve threads, push, verify CI, clean up"
user_invocable: true
arguments: <PR-number>
allowed-tools: "Bash(command:*), Read, Glob, Grep, Edit, Write, EnterWorktree, ExitWorktree"
---

# Address PR Review Feedback

Check out a PR into an isolated git worktree, address all unresolved review comments, resolve threads on GitHub, push the fixes, and clean up after CI passes.

## Arguments

- `$ARGUMENTS` — the PR number (e.g., `1234`), optionally preceded by the `--current-worktree` flag.
- **`--current-worktree`** — opt-in mode: run in the *current* worktree instead of creating a fresh one. Switches this worktree to the PR branch in place and restores the original branch on exit; no `EnterWorktree`/`ExitWorktree`. Used by `/tend-stack`, which drives this skill from inside an existing worktree where `EnterWorktree` can't nest.

## Execution Steps

Execute these steps in order. Stop and report errors if any step fails.

### Step 1: Validate Input

Parse `$ARGUMENTS`:

- Detect the `--current-worktree` flag. If present, set **current-worktree mode** (changes Steps 4, 9, and 10) and drop the flag from the arguments.
- Extract the PR number from what remains. It must be a positive integer. If not, tell the user: "Usage: /address-pr-feedback [--current-worktree] <PR_NUMBER>" and stop.

### Step 2: Detect Repository

```bash
gh repo view --json owner,name -q '.owner.login + "/" + .name'
```

Split the result into OWNER and REPO variables. If this fails, tell the user: "Could not detect GitHub repository. Ensure `gh` is authenticated and you're in a git repo."

### Step 3: Fetch PR Metadata

```bash
gh pr view $PR_NUMBER --json headRefName,baseRefName,title,url,state,number
```

- If the PR state is not `OPEN`, tell the user: "PR #$PR_NUMBER is $STATE, not open." and stop.
- Save `headRefName` — this is the branch name on the remote.
- Save `title` for status messages.

### Step 4: Check Out the PR Branch

**Default mode** — create an isolated worktree with Claude Code's built-in `EnterWorktree` tool. This triggers the project's `WorktreeCreate` hook, which copies `.env`, `CLAUDE.local.md`, `.claude/settings.local.json`, and runs `pnpm install`.

```
EnterWorktree(name: "pr-$PR_NUMBER")
```

Then check out the PR branch inside the worktree:

```bash
gh pr checkout $PR_NUMBER
```

**Current-worktree mode** — do **not** call `EnterWorktree`. Switch the current worktree to the PR branch (the saved `headRefName`) in place:

```bash
ORIG_BRANCH="$(git rev-parse --abbrev-ref HEAD)"   # remember where to return
git fetch origin "$HEAD_REF"
git switch "$HEAD_REF"
```

If `git switch` fails because the branch is checked out in another worktree, **do not** force-release that checkout. Print `Skipped PR #$PR_NUMBER ($HEAD_REF): checked out in another worktree (<path>).` and stop — the worktree never switched, so there is nothing to restore.

Either way, confirm you are on the correct branch:

```bash
git log --oneline -3
```

### Step 5: Fetch Unresolved Review Threads

Use the GraphQL API to fetch all review threads. Replace OWNER, REPO, and PR_NUMBER with actual values:

```bash
gh api graphql -f query='
query {
  repository(owner: "OWNER", name: "REPO") {
    pullRequest(number: PR_NUMBER) {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          startLine
          diffSide
          comments(first: 10) {
            nodes {
              body
              author { login }
              createdAt
            }
          }
        }
      }
    }
  }
}'
```

Filter to only **unresolved** threads (`isResolved: false`).

If there are no unresolved threads, tell the user: "No unresolved review threads on PR #$PR_NUMBER. Nothing to address." Then run [cleanup](#step-10-cleanup) and stop.

Group threads by file path for efficient processing.

### Step 6: Address Each Review Comment

For each unresolved thread, grouped by file:

1. **Read the file** at the path indicated by the thread.
2. **Read all comments** in the thread to understand the feedback. Pay attention to:
   - The specific line(s) referenced (`line` and `startLine`)
   - Whether it's a suggestion (with code block), a nit, or a blocking concern
   - Bot comments (linters, type checkers) vs human reviewers
3. **Make the code change** that addresses the feedback. For suggestions that include code blocks, apply them. For conceptual feedback, use your judgment.
4. **If a thread cannot be addressed** (e.g., it's a question needing human input, a design disagreement, or a discussion with no actionable change), note it and skip it — do NOT resolve it.
5. **Track** which thread IDs you successfully addressed vs skipped (with reasons).

After addressing all threads in a file, move to the next file.

### Step 7: Commit and Push

Stage all changes and review what you're about to commit:

```bash
git diff --stat
```

If there are no changes (all threads were skipped), report which threads were skipped and why, run [cleanup](#step-10-cleanup), and stop.

Commit and push:

```bash
git add -A
git commit -m "$(cat <<'EOF'
address PR review feedback

Co-Authored-By: Claude Code
EOF
)"
git push
```

If the push fails (e.g., branch protection), report the error. Do NOT force push. Leave the worktree intact for the user to investigate and stop.

### Step 8: Resolve Addressed Threads

For each thread ID that was successfully addressed (NOT skipped), resolve it via GraphQL:

```bash
gh api graphql -f query='
mutation {
  resolveReviewThread(input: {threadId: "THREAD_ID"}) {
    thread { id isResolved }
  }
}'
```

If a resolution fails, log the error but continue with remaining threads.

Report how many threads were resolved vs skipped.

### Step 9: Wait for CI

```bash
gh pr checks $PR_NUMBER --watch --fail-fast
```

This blocks until all CI checks complete.

- **If CI passes**: proceed to cleanup (Step 10).
- **If CI fails**: report which checks failed, then stop.
  - **Default mode**: do NOT call `ExitWorktree`. Tell the user the worktree is preserved for investigation — `ExitWorktree(action: "keep")` returns to the main repo, `ExitWorktree(action: "remove", discard_changes: true)` cleans up.
  - **Current-worktree mode**: leave the worktree on the PR branch — do **not** restore `ORIG_BRANCH`. Tell the user it's parked on `$HEAD_REF` for investigation and they can `git switch "$ORIG_BRANCH"` when done.

### Step 10: Cleanup

Only run this step if CI passed (or if there was nothing to do).

**Default mode** — use Claude Code's built-in `ExitWorktree` tool:

```
ExitWorktree(action: "remove")
```

If `ExitWorktree` refuses due to uncommitted changes (which shouldn't happen since we already committed and pushed), confirm with the user before retrying with `discard_changes: true`.

**Current-worktree mode** — do **not** call `ExitWorktree`. Restore the worktree to the branch it started on:

```bash
git switch "$ORIG_BRANCH"
```

The worktree ends on the branch it began on; this mode never leaves it switched and never removes a worktree.

Either way: do NOT delete the remote branch — it belongs to the PR.

### Step 11: Report Summary

Print a final summary:

```
PR #1234: "Fix auth token handling"

Review threads: 5 addressed, 2 skipped
  - Skipped: src/auth.ts:42 — reviewer question requiring human input
  - Skipped: README.md:10 — design decision, not a code fix

CI: all checks passed
Worktree: cleaned up
```

In current-worktree mode, the `Worktree:` line reads `restored to <ORIG_BRANCH>` instead of `cleaned up`.

## Error Recovery

- **`EnterWorktree` fails**: If a worktree with the same name already exists from a previous interrupted run, use `ExitWorktree(action: "remove", discard_changes: true)` first, then retry `EnterWorktree`.
- **`git switch` fails with "already checked out" (current-worktree mode)**: another worktree has the PR branch. Do not force-release it — skip the PR with a warning (see Step 4).
- **`gh` not authenticated**: Tell user to run `gh auth login`.
- **Push rejected**: Leave worktree intact, report error. Never force push.
- **GraphQL thread resolution fails**: Log the error, continue with remaining threads, report failures at the end.

## Important Notes

- **Default mode uses `EnterWorktree`/`ExitWorktree`** — never raw `git worktree add/remove` via Bash. The built-in tools trigger project hooks (e.g., copying `.env`, running `pnpm install`) and properly manage the session's working directory.
- **Current-worktree mode (`--current-worktree`)** runs inside the caller's existing worktree — it `git switch`es that worktree to the PR branch in place and restores the original branch on exit. No worktree is created or removed. It's the mode `/tend-stack` uses, since that command runs from inside a worktree where `EnterWorktree` can't nest. A PR branch already checked out in another worktree is skipped with a warning, not force-released.
- This command works in ANY GitHub repository. It detects owner/repo automatically.
- Thread resolution happens AFTER pushing, so reviewers see threads resolved only when fixes are on the remote.
- Threads that need human judgment (design questions, clarifications) are intentionally skipped.
- The worktree is only cleaned up after CI passes, ensuring you can investigate failures.
- The remote branch is never deleted — it belongs to the PR lifecycle.
