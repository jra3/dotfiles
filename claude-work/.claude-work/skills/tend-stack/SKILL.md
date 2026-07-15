---
name: tend-stack
description: "Tend graphite stacks — repeatedly scan an anchor branch and ALL its upstack dependents (or every stack you own, with --all) for PR review feedback and CI failures, resolve already-addressed threads, fix the rest bottom-up via /address-pr-feedback and /fix-pr, restack and auto-submit as it goes. Loops internally to convergence; fixes the anchor in place when run from a worktree; stages a pre-analyzed parked subagent for judgment calls and conflicts. Parallelizes every independent phase. Subsumes the per-PR babysitter."
user_invocable: true
arguments: "[branch-name | --all | --dry-run]"
allowed-tools: "Bash(command:*), Read, Glob, Grep, Edit, Write, Agent, SendMessage, Skill, TodoWrite, TaskCreate, TaskUpdate, TaskList"
---

# Tend Stack

Tend the graphite stack that grows **upward** from an anchor branch: repeatedly fix every in-scope branch with unresolved PR review feedback or failing CI — bottom-up — until the in-scope stack is clean or only human-judgment / unresolvable-conflict items remain. Fixing is delegated to `/address-pr-feedback` and `/fix-pr`; this skill owns the scope, the parallel scan, the sweep loop, the graphite reconcile/submit seam, and the escalation of judgment calls.

## Worktree contract

This skill follows the shared **Orchestrator contract** — read
[`../_pr-tending/worktree-contract.md`](../_pr-tending/worktree-contract.md) (Part B) before any
worktree or dispatch operation. Canonical there: the checkout-type dispatch table, the
orchestrator→leaf dispatch pattern (`isolation:"worktree"` subagent driving a leaf in
`--current-worktree`), the divergence guard, and the submit policy. **This skill never calls
`EnterWorktree`** — all worktrees come from subagent isolation. This file documents tend-stack's
specifics; the contract is the source of truth for the shared mechanics.

## The ideas that define this skill

### 1. Anchor + upstack is the scope — the anchor is the floor

The provided (or inferred) branch is the **anchor**. A graphite stack grows *upward*: each branch is created **on top of** another, so the anchor's **upstack dependents are its children** — the branches whose base is the anchor, then *their* children, transitively. That whole upstack, **plus the anchor itself**, is in scope.

- **The anchor is a hard floor.** Branches *below* the anchor (downstack ancestors) are **out of scope entirely** — never scanned, fixed, restacked, or submitted.
- **In scope = `{anchor} ∪ upstack(anchor)`.**
- **Fix bottom-up = anchor-first.** The anchor is the lowest in-scope branch, so each parent is fixed before its children restack onto it.

### 2. It loops internally — one invocation sweeps to convergence

Not one-branch-per-invocation, and no need to wrap in `/loop`. The skill runs an internal **sweep loop**: each round re-derives the in-scope stack, re-scans, fixes what it can, reconciles, auto-submits, and loops again. It keeps sweeping until a full round finds nothing actionable (**clean**), or the only thing left is blocked on a human (**stuck**). Auto-submit (below) is what gives later rounds fresh CI signal to converge on. Wrap in `/loop` only to catch feedback/CI that arrives *after* convergence.

### 3. Parallelize whenever it is possible

**Default to parallel.** The *only* coupling that forbids it is the **rebase chain**: a child's commits sit on top of its parent's, so a fixed parent must be restacked before its child. Everything else fans out — scan, classify, stale-thread resolution, and every fix (each in its own isolated worktree). The single reconcile restack is the one serial, rebase-coupled step.

| Phase (each round) | Work | Concurrency |
|-------|------|-------------|
| **Scan** | CI state + unresolved-thread count + divergence per in-scope branch | **Parallel** — read-only, batched |
| **Classify** | Per branch with issues: read threads + code (+ CI logs) → fix plan | **Parallel** — one read-only subagent per branch |
| **Resolve-stale** | Resolve threads already addressed by prior commits | **Parallel** — pure GraphQL |
| **Fix** | Branches needing code/CI changes | **Parallel** across branches — anchor in place first (if in a worktree), then the rest fan out as isolated subagents (Step 5) |
| **Reconcile + submit** | `gt sync` + bottom-up restack + scoped submit | **Sequential** — the one rebase-coupled step |

## Composing with the leaf skills

This skill **delegates** fixing; it does not reimplement it.

- **`/address-pr-feedback [--current-worktree] <PR#>`** — addresses unresolved review threads, pushes, resolves them, watches CI.
- **`/fix-pr [--current-worktree] <branch>`** — diagnoses CI, fixes root cause, verifies, `gt submit`s, watches CI (loops up to 3×).

Both expose the unified `--current-worktree` mode (Leaf contract, Part A). tend-stack drives **both** leaves through that single door — never hand-rolled `git switch`.

## Execution

Track progress with TodoWrite. **Setup (Steps 0–1) runs once.** Then enter the **sweep loop** (Steps 2–6), repeating to convergence. Finally report (Step 7). Stop and report on any unexpected failure.

### Step 0: Detect checkout type (do *not* leave it)

```bash
TOPLEVEL="$(git rev-parse --show-toplevel)"
echo "$TOPLEVEL"
```

Determine where you are — this selects the dispatch column (contract table, Part B):

- **In a worktree** (`$TOPLEVEL` contains `/.claude/worktrees/`) → the anchor (if it is the current branch) is fixed **in place** here; reconcile runs here.
- **In root/main** → the anchor goes to a subagent worktree (worktree-only policy forbids editing source in root); reconcile runs in root.

Do **not** pop out of a worktree. tend-stack runs in place from wherever it was invoked.

### Step 1: Resolve the anchor and compute its in-scope stack (anchor + upstack)

Decide the **anchor**:

- **`--all`** — tend **every stack you own**, not just one. Pull all your open PRs, build the base→head graph, and split it into connected components (each component = one stack). For each component, the **anchor is its lowest branch** — the one whose `baseRefName` is `main` (or a base that has no open PR, e.g. an already-merged parent), so the anchor is the bottom and scope = the whole component. Run the entire sweep loop (Steps 2–6) for each stack, **one stack at a time** (each stack's reconcile is serial and rebase-coupled; sequencing keeps restacks from interleaving). The escalation cap of 3 is **global across all stacks** in the run. Report per stack, then a combined summary. `--all` ignores the current branch and is the continuous-watch entry point: `/loop tend-stack --all`. Composes with `--dry-run` (preview every stack, touch nothing).
- **No argument** — `ANCHOR="$(git rev-parse --abbrev-ref HEAD)"`. If that is `main`/trunk, there is no stack to tend — report and stop.
- **`<branch-name>` argument** — *resolve* it first; don't assume it exists or belongs to the current stack:

  ```bash
  ARG="<branch-name>"
  git worktree list --porcelain | grep -qF "branch refs/heads/$ARG" && echo "IN_WORKTREE"
  git show-ref --verify --quiet "refs/heads/$ARG" && echo "LOCAL"
  git ls-remote --heads origin "$ARG" | grep -q . && echo "REMOTE"
  gh pr list --state open --head "$ARG" --json number --jq '.[0].number // "NO_PR"'
  ```

  | Resolution | Action |
  |------------|--------|
  | Open PR exists (anywhere) | Set `ANCHOR="$ARG"`. It fixes the **floor**; scope is this branch + everything on top. With an explicit arg the anchor generally isn't the branch you're standing on → it's fixed in a subagent worktree, not in place. |
  | Branch exists but **no open PR** | **Stop.** "Branch exists but has no open PR — run `gt submit` to create one." |
  | **No such branch anywhere** | **Stop.** If `$ARG` looks like a Linear *suggested* name (`<login>/eng-NNNN-…`), say so. Point at `/wt` or starting the work. tend-stack does **not** create branches (`styleguide:single-responsibility`). |

Confirm the anchor is graphite-tracked:

```bash
gt log short 2>&1 | grep -F "$ANCHOR" || echo "NOT_TRACKED"
```

If not tracked, report and stop (the reconcile seam needs it).

> **Use `gt`, never `graphite`.** The `graphite` name is a mise *shim* that fails in
> non-interactive shells (`No version is set for shim: graphite`) — it would make this check
> silently echo `NOT_TRACKED` and every reconcile/submit command below break. `gt` resolves to
> the direct binary and works headless. All `gt` commands here are the direct-binary form.

**Compute in-scope = anchor + full upstack.** Pull open PRs for the chain + metadata:

```bash
gh pr list --state open --json number,headRefName,baseRefName,title,url,author,isDraft --limit 200
```

Build a graph where each PR's `baseRefName` is the parent of its `headRefName`. Then:

1. **Start at `$ANCHOR`** (the floor; always in scope).
2. **Walk upward only** — collect every PR whose `baseRefName` is an in-scope branch, transitively. That is `upstack(anchor)`.
3. **In scope = `{anchor} ∪ upstack(anchor)`.** Anything reachable only *downward* from the anchor is excluded.
4. **Order by depth from the anchor** (anchor = depth 0). This is the **bottom-up fix/restack order**.

> `gt log` gives the same upstack; `gh pr list` is used because it bundles PR number, author, and draft state. On disagreement, trust graphite for parentage and `gh` for PR metadata.

**Scope to your own work.** `gh api user --jq .login`; by default only branches whose PR `author.login` matches you. A teammate's branch in the upstack is skipped for **fixing** but still counts as a parent in the rebase chain. Note any relaxation.

---

## The sweep loop (Steps 2–6, repeated)

Maintain across rounds:

- **`blocked`** — branches whose remaining issues are non-actionable this run (escalated judgment threads, CI failed after `/fix-pr` exhausted retries, divergence-blocked, or hit a restack conflict). **Monotonic** — never re-attempted; this guarantees termination.
- **`failPrints`** — per branch, the set of failing-check names from last round (cheap same-failure fingerprint).
- **`escalations`** — outstanding staged escalations (cap 3).
- **`progressThisRound`** — true if the round resolved ≥1 thread or pushed ≥1 fix.

**Round control:**

1. Re-derive the in-scope set (Step 1's walk) — `gt sync` may have deleted merged branches.
2. **Scan** (Step 2). Work-list = in-scope own-PR branches with ≥1 issue, **excluding `blocked`**, ordered bottom-up.
3. Work-list empty → **converged. Exit** and report.
4. **Classify → Resolve-stale → Fix → Reconcile+submit** (Steps 3–6).
5. Move any branch whose only remaining issues are non-actionable into `blocked`. If a branch's failing-check set equals last round's (`failPrints`), it made no progress → `blocked`.
6. `progressThisRound` false → **stuck. Exit** and report what's blocked. Else loop.
7. **Safety cap:** stop after **5 rounds** regardless, reporting loudly — a runaway guard, not an expected exit.

`--dry-run`: do **one** scan + classify pass (Steps 2–3), print the in-scope set, per-branch issues, divergence, and planned actions, then stop without touching anything or looping.

### Step 2: Scan all in-scope branches — in parallel

Detect issues for **every** candidate branch concurrently (batch the `gh` calls — one message, or one backgrounding shell loop). Never poll one at a time.

**CI failure** — any check in a failing/error state (pending does **not** count):

```bash
gh pr checks <PR#> --json name,state,bucket 2>/dev/null || gh pr checks <PR#>
```

`bucket: "fail"` (or a `fail`/`error` row) = CI failure. Record the failing-check **names** (for the `failPrints` fingerprint).

**Unresolved review feedback** — ≥1 unresolved review thread:

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

(`OWNER`/`REPO` via `gh repo view --json owner,name -q '.owner.login + "/" + .name'`.)

**Divergence** (contract Part B) — flag branches with unpushed local work checked out elsewhere:

```bash
git fetch --quiet origin                # refresh remote-tracking refs first (round 1 has no prior gt sync)
git worktree list --porcelain          # once per round; scan output yourself, no | grep
git rev-list --count origin/<branch>..<branch> 2>/dev/null   # >0 ⇒ local ahead of origin
```

If `origin/<branch>` doesn't exist (branch never pushed), treat the branch as local-only — it has no PR to tend, so it was already skipped.

A branch that is **local-ahead AND checked out in another worktree** is **divergence-blocked**: report `skipped <branch>: unpushed local work in <worktree>`, exclude from fixing, but keep it as a parent in the chain. **Exemption:** the current worktree's own branch (the anchor, when in a worktree) is never divergence-blocked — it's fixed in place on its real local state.

Build the round's **work-list**: in-scope own-PR branches with ≥1 issue, minus `blocked` and divergence-blocked, ordered bottom-up. Empty → converged.

### Step 3: Classify each branch's issues — in parallel (read-only subagents)

For each work-list branch, launch **one read-only subagent** (`Explore` or `general-purpose`), **all in one message**. Each receives the branch, PR number, and unresolved threads, and returns a structured *fix plan*:

- **Per unresolved thread**, classify as:
  - `already-addressed` — current branch code already satisfies the comment (common for `isOutdated`). Include evidence (file + lines). → **resolved** in Step 4, no code change.
  - `clean-fix` — a concrete, unambiguous code change. Include file(s) + precise description/diff.
  - `judgment-trivial` — a bot suggestion the author deliberately skipped, a nit, a non-blocking style preference. → **reported**, not staged, not resolved.
  - `judgment-substantive` — a design question, a partial-fix debate, anything needing the user's decision. → **escalated** (Step 5), not resolved.
- **For a CI failure**, identify the failing checks and likely root cause from the logs.
- Note whether the branch's `clean-fix`/CI changes touch files any *other* work-list branch also changes (a **risk note** only — fixes still run in parallel; coupled conflicts surface at reconcile).

Subagents only **read and report**. Collect all plans before acting.

### Step 4: Resolve already-addressed threads — in parallel

For every `already-addressed` thread across all branches, resolve concurrently (pure GraphQL — independent):

```bash
gh api graphql -f query='
mutation { resolveReviewThread(input: {threadId: "THREAD_ID"}) { thread { id isResolved } } }'
```

(GraphQL resolve is **not** deny-listed, unlike `gh pr review`.) Each resolve = progress. A branch whose only issues were already-addressed is now clean — drop it from the round's remaining work.

### Step 5: Fix the rest — bottom-up, always parallel

Process branches with real work (`clean-fix` threads or CI failures). **No serial path** — the many branches fan out into parallel subagents; the single reconcile restack is the conflict checkpoint. Because deferred restacking means fix *order* doesn't affect correctness, the two sub-steps below run **sequentially** only because the main agent can't foreground-fix and await a subagent batch at once — not because of any rebase coupling.

**5a — Anchor in place, first (only when run from a worktree and the current branch is the anchor).** Fix it **foreground** in the current worktree via the leaf in `--current-worktree` mode — and finish this before 5b, since the main agent runs it itself:
- Feedback → `/address-pr-feedback --current-worktree <PR#>`
- CI → `/fix-pr --current-worktree <branch>`
- Both → run feedback first (it pushes + watches CI), then CI on whatever remains.

This operates on the anchor's real local state (unpushed work and all) and always-restores the worktree to the anchor on exit. (When run from root, or with an explicit `<branch>` arg where the anchor isn't the current branch, the anchor is **not** fixed here — it's just one more branch in 5b.)

**5b — Every remaining branch, in parallel.** Spawn one `general-purpose` subagent per branch with `isolation:"worktree"`, **all in one message**. Each subagent — already in its own isolated worktree — invokes the leaf in `--current-worktree` mode (`/address-pr-feedback --current-worktree <PR#>` or `/fix-pr --current-worktree <branch>`), applies its plan, pushes **only its own branch**, resolves the threads it actually fixed, and reports CI result + skipped judgment threads. Subagents must **not** restack or touch other branches. A branch with both feedback and CI: the subagent runs feedback first, then CI.

**Escalate substantive judgment calls (tiered handling).** For each `judgment-substantive` thread, stage an **escalation** (see *Escalation staging* below) — never auto-resolve it. The branch's other (clean-fix/CI) issues are still fixed; the thread simply stays unresolved pending the user. `judgment-trivial` threads are **reported only**.

A `/fix-pr` that exhausts its retries → note + mark the branch `blocked`. Each pushed fix or resolved thread = progress. Do **not** restack between fixes — all rebasing is deferred to Step 6.

#### Escalation staging

When a blocker needs the user (a `judgment-substantive` thread, or an unresolvable restack conflict from Step 6), stage a **pre-analyzed parked subagent** rather than just reporting:

- **Backpressure: cap 3 outstanding escalations.** If 3 are already open, do **not** stage a fourth — report `3 escalations open — clear one to resume` and stop staging new ones this run.
- Spawn a background `general-purpose` subagent with `isolation:"worktree"` (`run_in_background: true`). Its self-contained prompt: switch the worktree to the branch (`git fetch origin <branch>` + `git switch <branch>`), read the blocking thread(s) / the conflict, do the analysis, **draft a proposed resolution**, then **park** — report the plan and wait. It must **not** push, **not** resolve threads, **not** restack.
- Record `{branch, kind: thread|conflict, agentId, worktreePath}` in `escalations`.
- The worktree lives with the parked subagent; the user re-engages via `SendMessage` to the agent or by `cd`-ing into the worktree path. (Durability is tied to the agent/session — note this when reporting.)

tend-stack never `EnterWorktree`s for escalation — the parked subagent's isolation worktree *is* the staged worktree.

### Step 6: Reconcile + submit — sync, one bottom-up restack, scoped submit

Once the round's fixes are pushed, reconcile from the current checkout in one pass:

```bash
gt sync --no-interactive -d
gt restack --upstack --branch "$ANCHOR" --no-interactive
```

- `gt sync -d` pulls trunk, auto-deletes merged/closed branches, restacks what it can.
- `gt restack --upstack --branch "$ANCHOR"` rebases the anchor + its upstack onto fixed parents and **surfaces any conflict** `sync` skipped. Anchoring at `$ANCHOR` keeps the floor honest — nothing below it is touched.
- **On a conflict / non-zero exit:** abort (the `--no-interactive` restack aborts rather than dropping into interactive rebase). **Stage an escalation** for the conflicting branch (Step 5 *Escalation staging*, `kind: conflict`), mark that branch **and its upstack** `blocked` for the round, and continue. Never blanket-auto-resolve a restack conflict.
- A branch checked out in another worktree can't be restacked — skip it and surface (`reference: restack a stack split across worktrees`).

**Auto-submit the restacked in-scope stack** (contract Part B submit policy). `gt submit --stack`
submits **ancestors too**, which would reach downstack below the anchor — so do **not** use it.
Submit each in-scope branch **narrowly**, bottom-up (anchor first), so the floor is never crossed:

```bash
# for each in-scope branch b in {anchor} ∪ upstack(anchor), depth order, that is NOT
# divergence-blocked or checked out elsewhere:
gt submit --branch "$b" --no-stack --no-interactive
```

- **Scoped** — `--no-stack` submits only `$b`; iterating anchor-upward never touches downstack ancestors. Bottom-up order means each branch's parent base is already published before its child.
- **Draft-preserving** — omit `--draft`; `gt submit` only drafts *new* PRs and never changes an existing PR's draft state, so drafts stay drafts and non-drafts stay non-drafts. Never pass `--draft` here (it would force-draft new PRs).
- **Divergence-gated** — skip any divergence-blocked branch or one checked out elsewhere.
- A restacked child's logical diff is unchanged (pure rebase), so republishing it is **not** untested new logic — it does not trip the draft-by-default rule.

Auto-submit is what feeds the next round fresh CI on the rebased children, letting the loop converge on a green, published, reconciled stack.

### Step 7: Report (once, after the loop exits)

```
Stack: <anchor>↑ (in scope: <n> — anchor + upstack; <m> yours, <k> skipped/teammates)
Rounds: <r>  (exit: clean / stuck / cap)
Tended this sweep:
  #<num> <branch>  — feedback: <resolved / skipped>   CI: <fixed / green / n/a>
  ...
Stale threads resolved (no code): <count>
Reconcile: gt sync (<deleted, if any>) + upstack restack from <anchor> + submit — <clean / CONFLICT on <branch>>
Escalations staged (<count>/3):
  #<num> <branch> — <thread|conflict> — agent <id>, worktree <path> — proposed: <one-line>
Reported judgment (trivial, not staged): <per branch + why>
Needs your attention (blocked):
  - CI fixes that failed after retries (+ worktree path)
  - restack conflicts (see escalations)
  - divergence-blocked branches (unpushed work elsewhere)
Remaining with issues: <none / list>
```

List every escalation, blocked item, and stop condition explicitly. Re-engage a parked escalation via `SendMessage` to its agent.

## Important notes

- **Anchor is the floor; scope grows upward.** Only the anchor and its upstack are tended — never branches below it.
- **Runs in place.** No pop-to-main. From a worktree, the anchor is fixed in place; from root, all fixes go to subagent worktrees. **Never `EnterWorktree`** — isolation subagents own every worktree.
- **One invocation sweeps to convergence**, fed by per-round auto-submit. `/loop` only to catch *new* feedback/CI later.
- **Parallelize whenever possible.** Only the reconcile restack is serial.
- **Delegation, not reimplementation.** All fixing goes through the leaves in `--current-worktree` mode. Hand-editing source here means you've drifted.
- **Divergence guard.** Skip branches with unpushed local work checked out elsewhere; the current worktree's own branch is exempt.
- **Tiered judgment + escalation.** Trivial threads reported; substantive threads and unresolvable conflicts get a staged, pre-analyzed parked subagent (cap 3). Never auto-resolve a judgment thread or blanket-resolve a conflict.
- **Auto-submit is scoped, draft-preserving, divergence-gated.**
- **`--all` tends every stack you own**, one stack at a time, with a global escalation cap of 3 — this is the continuous-watch role (`/loop tend-stack --all`) that replaces the old per-PR babysitter. Single-anchor remains the default.

## Error recovery

- **A branch is skipped as "checked out in another worktree":** distinguish *live work* from a *stale* worktree by divergence (the same `git rev-list --count origin/<branch>..<branch>` from Step 2):
  - **0 ahead of origin** → almost always a **stale `.claude/worktrees/agent-*`** left by a prior subagent, `/fix-pr` background run, or `/wt`. It has no unpushed work but still blocks both the leaf's `--current-worktree` fix *and* the reconcile restack for that branch. Surface the path and clean it up (`/tidy`, or `git worktree remove --force <path>`), then it's tendable on the next round.
  - **ahead of origin** → treat as **live work**; the divergence guard is right to skip it. Never force-detach or remove it.
- **A fix subagent left a worktree after CI failure**: note the path; clean up with `git worktree remove --force <path>` once the user confirms.
- **`gt restack` conflict**: stage an escalation, mark branch + upstack blocked; never auto-resolve.
- **`gt sync`/`gt submit` rejects a branch** ("updated remotely"): if it was intentionally rebased, the reconcile already rebased it locally — re-run the scoped submit; otherwise surface and stop.
- **A branch oscillates** (same failing-check set two rounds running): marked `blocked` via the `failPrints` fingerprint so the run exits via *stuck*, not the round cap.
- **Argument branch doesn't exist**: likely a Linear suggested name; point at `/wt` or starting the work — don't create it.
- **Argument branch exists but has no open PR**: stop; tell the user to `gt submit` first.
