# PR-Tending Worktree & Dispatch Contract

Canonical source of truth for how the PR-tending skills work with git worktrees and how
orchestrators dispatch the leaf fixers. The leaf fixers (`fix-pr`, `address-pr-feedback`)
and the orchestrators (`tend-stack`) reference this file. Read the relevant section before
any worktree or dispatch operation; each skill's own SKILL.md documents only its deviations.

This dir has no `SKILL.md`, so it is a resource directory, not a skill — the loader ignores it.

---

## Part A — Leaf contract (`fix-pr`, `address-pr-feedback`)

The two leaf fixers each have the same three operating modes. A mode is selected by the
caller; the leaf must honor the worktree invariants below exactly.

### Modes

1. **Default mode** (PR#/branch arg, no flag) — the leaf **owns** a fresh worktree.
   - `address-pr-feedback <PR#>`: `EnterWorktree(name: "pr-<PR#>")`, fix, push, resolve, watch CI,
     then `ExitWorktree(action: "remove")` after CI passes.
   - `fix-pr <branch>`: spawns a **background** `general-purpose` subagent with
     `isolation: "worktree"`; the subagent runs the fix-and-watch loop; the **dispatcher**
     removes the worktree via `git worktree remove --force <path>` on the completion
     notification (the harness auto-cleanup only fires for *unchanged* worktrees).
   - On a failed fix, the leaf may **keep** its worktree for investigation and report the path.
     This is legal because the worktree is the leaf's own throwaway.

2. **Foreground mode** (`fix-pr`, no arg) — runs in the caller's **current** worktree, on
   current HEAD. Creates and cleans up nothing. The caller must already be in a worktree
   (worktree-only policy) unless the change is a config-file exception.

3. **`--current-worktree <ref>` mode** — the **orchestrator-driven** mode. Runs in the
   caller's existing worktree, switching it to the target ref in place. No `EnterWorktree`,
   no `git worktree add`, no background subagent. Used when the caller is already inside a
   worktree where `EnterWorktree` cannot nest.

### `--current-worktree` invariants (identical in both leaves)

The caller owns the worktree lifecycle, so the leaf must hand it back exactly as received:
**invariant in, invariant out.**

- **Record** `ORIG_BRANCH="$(git rev-parse --abbrev-ref HEAD)"` before switching.
- **Switch in place**: `git fetch origin <ref>` then `git switch <ref>`. This operates on the
  branch's **local** ref (including any unpushed commits) — that is intentional.
- **Skip-if-checked-out-elsewhere**: if `git switch` fails because the ref is checked out in
  another worktree, **do not** force-release it. Print
  `Skipped <ref>: checked out in another worktree (<path>).` and return without switching
  (nothing to restore).
- **Always-restore** — on **every** exit path (success, terminal failure, retry/iteration cap,
  or skip), restore the starting branch: `git switch "$ORIG_BRANCH"`. This mode **never**
  leaves the worktree switched and **never** removes a worktree.
- **Failure surfaces in the report, not in the worktree state.** A failed fix (red CI, cap hit)
  is reported as text (`CI red on <ref>`, etc.); it is *never* communicated by leaving the
  worktree parked on the failing branch. (Parking-for-investigation is a **default-mode**
  affordance only, where the worktree is the leaf's own.)

---

## Part B — Orchestrator contract (`tend-stack`)

### Checkout-type dispatch

An orchestrator never calls `EnterWorktree` for *fixing* (all fixing fans out to subagents).
It runs from wherever it was invoked, and the fix dispatch is checkout-type-aware:

| Invocation | Anchor fix | Other branches | Reconcile |
|---|---|---|---|
| From a **worktree**, no arg (current branch = anchor) | **in place** (current wt, `--current-worktree`) | new isolated subagent worktrees | current wt |
| From **root/main**, no arg (current branch = anchor) | isolated subagent worktree | isolated subagent worktrees | root |
| **`<branch>` arg** (anchor ≠ current branch) | isolated subagent worktree | isolated subagent worktrees | current checkout |

- **Worktree-only policy**: in-place anchor fixing is legal **only** when the current checkout
  is a real worktree. From root, the anchor also goes to a subagent worktree — never hand-edit
  source in root. Reconcile (`gt sync`/`gt restack`) in root is fine; it is git plumbing,
  not source editing.

### Orchestrator → leaf dispatch pattern (the one concurrent door)

To run a leaf fix **concurrently**, spawn one `general-purpose` subagent with
`isolation: "worktree"` (all subagents in a single message), and have each invoke the leaf in
`--current-worktree` mode:

- Feedback → `/address-pr-feedback --current-worktree <PR#>`
- CI → `/fix-pr --current-worktree <branch>`

The subagent is already in its own isolated worktree (off the parent's HEAD), so it must use
`--current-worktree` — never a nested `EnterWorktree`. Never hand-roll `git switch` in the
orchestrator prompt; drive both leaves through the identical `--current-worktree` door. Each
subagent pushes **only its own branch** and must not restack or touch other branches.

### Divergence guard

The leaf fixers operate on a branch's state and may `gt submit --force`. Guard against
clobbering work that exists only locally:

- **Skip + surface** any branch with **unpushed local work that is checked out in another
  worktree** (`local tip ahead of origin/<branch>` AND a `branch refs/heads/<branch>` line in
  `git worktree list --porcelain` pointing elsewhere). Report
  `skipped <branch>: unpushed local work in <worktree>` and exclude it from fixing — but it
  still counts as a parent in the rebase chain.
- **Exemption**: the **current worktree's own branch** (the anchor, when invoked from a
  worktree) is always fixable in place — `--current-worktree` operates directly on that local
  state rather than force-pushing origin over it, so unpushed work is tended, not clobbered.
- A divergence-blocked **parent** halts its **upstack** for that round (you cannot cleanly
  restack children onto a parent you are forbidden to touch).

### Submit policy

When an orchestrator publishes (e.g. after a reconcile restack):

- **Scoped** — submit only in-scope branches (anchor + upstack); never blanket-`--stack` into
  downstack ancestors below the anchor.
- **Draft-preserving** — `gt submit` preserves draft state; never promote a draft.
- **Divergence-gated** — never submit a branch skipped by the divergence guard or checked out
  elsewhere.
- A restacked child's logical diff is unchanged (pure rebase), so republishing it is **not**
  "untested new logic" and does not trip the draft-by-default rule.

### Conflicts and judgment calls

- A **restack conflict** is never auto-resolved by a blanket merge. It is handled by the
  orchestrator's escalation path (stage a worktree + a pre-analyzed parked subagent that drafts
  the resolution) or, at minimum, surfaced and stopped — never silently merged.
- **Judgment-call review threads** are never auto-resolved. Trivial ones are reported;
  substantive ones are escalated. See the orchestrator's tiered judgment handling.
