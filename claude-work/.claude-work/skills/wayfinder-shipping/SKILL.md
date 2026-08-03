---
name: wayfinder-shipping
description: Turn a Wayfinder execution map's work into reviewable PRs — build the whole map on one branch named for the map ticket, and publish it incrementally into a linear stack by advancing a horizon between published work and prototype. Use whenever a /wayfinder map carries execution (its Notes override is on and tickets produce code), when deciding whether work is ready to publish, when splitting prototype work into PRs, when grouping or ordering a stack for review, when review feedback arrives on a map's open PRs, or before opening any of a map's PRs for review. Also covers what may and may not change after publish.
---

# Shipping a map's code

Layers on top of the `wayfinder` skill — it does not replace it. `/wayfinder` charts and works
the map; this covers what happens to the **code** a map produces.

Applies to **execution** maps — the Notes override is on and tickets build, not just decide.
A planning-only map never gets here.

The trap: tickets are session-sized and created as fog clears, so they arrive in **discovery
order**. That's the worst order to review in. Ship them as PRs one-for-one and you've handed
someone a build log and called it a review.

So build and review stay separate — but they run **concurrently**, separated by a line that
moves.

## The horizon

The build branch is not a phase. It is a **region**, and it is always the tip of the stack:

```
  build branch          ← prototype: mutable, CI-dark, no PR
━━━━━━━━━━━━━━━━━━━━━━━ the horizon
  PR #3                 ← published: shape committed, under review
  PR #2
  PR #1
  main
```

**Above the horizon** is prototype: freely mutable, no PR, nobody's problem but yours. **Below
it** is published: cut into PRs, under review, merging. Publishing is the single act of
**advancing the horizon** — converting hardened work into review.

Everything else here is either *what may cross*, *when*, or *what the rules are on each side*.

### Vocabulary

These are the terms. If you find yourself reaching for one that isn't here, that's a signal the
model doesn't cover what you're doing — say so rather than inventing a word.

**Structure**

- **horizon** — the boundary between published and prototype.
- **prototype region** — everything on the build branch above the horizon.
- **spine** — the chain of published PRs from `main` up to the horizon.
- **slab** — **one PR's worth of files**: the unit that crosses the horizon. A slab is a set of
  paths, grouped by layer (see [Order](#order)). One slab becomes exactly one PR. A slab may
  contain paths from several tickets, and one ticket's paths may span several slabs.

**Acts**

- **publish** — cut a slab into a PR, advancing the horizon past it.
- **amend** — change what a published PR *contains*. Free, expected, unremarkable: review
  responses, bug fixes, renames, a better implementation of the same thing.
- **re-cut** — change the *shape*: move work between PRs, split or fold a published PR,
  re-parent the spine.

Everything else you'll see used as a fixed phrase — **straddler**, **green set**, **tending
session**, **fog gate**, **Stack Brief** — is not a fifth coinage. Each is read directly off
words already defined here (a ticket that *straddles* the horizon; the set of checks that must
be *green*; a session spent *tending* the spine) or off the base skill's own vocabulary
(**fog**, **frontier**). None of them needs its own entry to be unambiguous.

At publish you commit to the **shape, not the contents**. Amending keeps that commitment;
re-cutting breaks it. Re-cutting's cost is a **gradient**:

| State | Cost of re-cutting |
|---|---|
| Nobody's looked yet | Cheap — [un-split](#backing-a-slab-out) and re-cut. Discount review bots (`claude`, `codex`); a bot pass is not someone's attention. |
| A human has looked | They spent attention on the shape you committed to; re-cutting spends it for them. Doable — costs a heads-up and a brief update. Needs a better reason than tidiness. |
| Merged | The commitment is discharged. Not re-cuttable — the only move is new work above the horizon that supersedes it. |

## Setup precondition

Verify once per workspace, before relying on any status automation below:

- Linear's GitHub integration auto-transitions are **on**.
- They target `In Review` on PR open and `Done` on merge.
- They pick up **bare identifiers** in a PR description (rather than requiring `Fixes ENG-1234`).

If any is false, every transition below degrades to manual — which works, but only if you know
to do it.

## Build: one branch

The whole map goes on a single branch named for the **map** ticket — not the children. No
per-ticket branches, no restacking the map's own work while it's open.

- **One map = one branch = one worktree.** Sessions cannot overlap.
- **The branch must be tracked by Graphite** — `gt track --parent main` — or `gt sync` silently
  skips it and drift accumulates. `EnterWorktree` names branches `worktree-<name>`, so rename
  to the map ticket's Linear branch *and then* track.
- **It has no PR and is never submitted.** Push it with plain `git push origin <build-branch>`
  for backup — that push is the only part graphite isn't involved in.
- **`gt sync` on a cadence**, not just at the end, so the split isn't fighting drift.

This is what makes late work stop hurting. While a change is above the horizon, a rename is
just a rename, a follow-up fix is a commit, and moving a shared type to its right owner is an
edit. None of it is a restack.

## What may cross: the gate

**The horizon trails the frontier, and never crosses into fog.**

A slab may cross only when no open `Todo` ticket **and no `Not yet specified` patch** could
plausibly redefine what it introduces. The frontier is where discovery is happening; the
horizon is where certainty has hardened. If a fog patch might still reshape a contract, that
contract stays above the line.

Two hard constraints ride alongside that judgment:

- **Self-containment.** Every published PR builds, tests, and lints on its own.
- **Vocabulary floor.** Nothing publishes before the map's vocabulary is settled. If the map
  produces `CONTEXT.md` glossary or ADR changes, **they lead**. If it produces none, the
  [order](#order) simply starts at its second entry.

The floor genuinely delays the first publish on a fog-heavy map, because vocabulary is the
thing fog most often reshapes. That's the cost of not renaming a concept out from under a
reviewer. "Settled" means no open ticket is likely to rename it — not that you're certain.

## When: greedy

Publish at the end of any session where a slab passes the gate. Don't accumulate, don't soak.

Greedy serves both goals with one behaviour: shortest feedback latency and smallest review
batches fall out together. And **reshaping a published PR is cheapest when the horizon is
shallow** — few PRs below to cascade over, little prototype above to re-point. Publishing early
is self-protecting.

Greedy **cannot scramble dependency order.** A split PR must stand alone, and `gt split` only
lifts *below* the tip, so a wiring slab can't cross while the foundation it calls is still
above the horizon.

It *can* place independent work higher than ideal. `gt split` always creates a parent of the
branch you run from, so across sessions, position is chronological — an independent leaf
discovered in session 7 lands above a foundation published in session 3, and can't merge until
that foundation does. Accept it. Within a single publish check, order slabs by the list below;
across checks, chronology wins. If a misplacement genuinely matters, it's a re-cut, priced by
the gradient.

### Order

Think in **merge order**. The PR nearest `main` merges first; the build branch is always last.

1. **`CONTEXT.md` glossary and ADR changes** — if the map produces any, they lead. They define
   the words every later PR is written in, and they merge on their own risk-free.
2. **Independent leaves, or not-yet-wired code** — nothing depends on them.
3. **Foundation / contract.**
4. **Consumers**, in dependency order.
5. **Wiring and surface.**

Independent work goes **early in this same chain** — not on a second branch off `main`. It
merges first either way, and one spine stays one spine.

Two links that look real and aren't:

- **Chronology.** Built later doesn't mean depends on. Check for actually-shared files.
- **Registration collisions** — barrels, module registries, step tables. That's a conflict to
  absorb, not a dependency. A thing's registration line ships in the PR that introduces it.

## Linear carries the horizon

Status carries the **ship** axis. The assignee carries the claim, exactly as the base skill says.

| State | Meaning |
|---|---|
| `Todo`, unassigned, unblocked | Frontier — takeable |
| `Todo`, assigned | Claimed, being built |
| `In Progress` | **Built and green, above the horizon** (prototype) |
| `In Review` | **Entirely below the horizon** |
| `Done` | Merged |

This ladder applies **only to tickets that produce code**. A ticket whose `## Paths` manifest is
**empty** — most `grilling` and `research` tickets, and any `prototype` whose artifact never
landed on the build branch — has nothing to ship, so it closes at resolution and goes straight
to `Done`, exactly as the base skill says. The manifest is the discriminator, not the ticket
type.

For a code-producing ticket: it reaches `In Review` only when **every** path it produced is
below the horizon. A ticket whose work straddles the line stays `In Progress` — see
[PR description](#2-pr-description), where that rule enforces itself.

**A pile of straddlers means the horizon is cutting through live work.** Publish later, or at a
different seam.

## The session: tend → build → publish check

Every session, in that order. The base skill's one-ticket-per-session limit still holds.

### 1. Tend

**Before syncing**, check every spine PR for a closed-but-unmerged state — `gt sync` offers to
delete branches for PRs that are merged **or closed**, and under `-d`/`-f` it doesn't prompt at
all:

```bash
gh pr list --head <build-branch> --state all --json number,headRefName,state
```

A closed (not merged) PR mid-spine means a reviewer rejected that slab outright — decide its
fate now (re-cut it back above the horizon, or revive the PR) before anything can delete the
branch out from under you.

Only once that's clear, sync and restack:

```bash
gt sync -d --no-interactive
```

`-d` is now safe — anything closed has already been dealt with, so auto-deleting merged
branches is exactly what you want. Then **check** the spine itself, per PR:

```bash
gh pr view <n> --json state,reviewDecision,reviews,comments,statusCheckRollup
```

Do not run `/tend-stack` to convergence here — that loop is unbounded and will eat a session
that has one ticket's worth of budget.

**Nothing hard-blocks building.** The cost of building on contested ground is yours to accept.
The agent owes you one sentence at the top of the session — *"heads up: you're about to build
on ENG-NNNN's contract, which has an open thread"* — and then gets out of the way.

Every open thread gets a **disposition**. "Still open" is not one of them.

- **amend now** — it pulls on something this session will build on.
- **amend later** — real, deliberately deferred, touches nothing above it.
- **reply / decline** — you disagree; the thread carries it, no code moves.
- **ticket it** — the feedback raised a *question the map hasn't answered*. Not a fix, a
  decision. It becomes a map ticket or a line in `Not yet specified`.

An *amendment* is mechanical and stays off the map. A *question surfaced by review* is exactly
what the map is for. Reviewers finding fog is a good outcome and it needs somewhere to land.

Tend with **`gt submit --update-only --no-interactive`** — it pushes only branches that already
have PRs, so it structurally cannot mint one for the build branch.

**Re-verify green after any restack.** A restack that produced no conflict can still break the
build — a trunk rename lands cleanly and fails at compile. If `gt sync` moved anything, run the
green set before trusting the spine.

If the spine needs real work, say so as the session's first act and make it a **tending
session**. A map with several PRs under review is a map whose next unit of work is review, not
code.

### 2. Build

One ticket. It resolves when its commit is on the branch and the branch is **green** — the
green set being:

```bash
make build-typescript && make test && make lint.full   # slowest last
```

The prototype region is **CI-dark** — no PR means no pipeline — so this is the only gate above
the horizon. `check-types` alone is not enough: the build catches what it misses, and typeaware
lint catches missing imports.

**If it isn't green, the ticket doesn't resolve.** It stays `Todo`+assigned and the session ends
red. Say so explicitly — the next session's build step starts by making it green, and inherits
no new ticket until it is.

Post the resolution as a comment on the ticket:

```markdown
## Answer

<what was built, one paragraph>

## Paths

app/packages/foo/src/bar.ts
app/packages/foo/src/baz.ts
```

The `Paths` manifest is what everything downstream reads: straddler detection, the PR
description's ticket list, and the brief. It survives `gt squash`, which git history does not.
**A ticket that produced no code writes `## Paths` with nothing under it** — that empty
manifest is what routes it to `Done` at resolution.

Move the ticket to `In Progress` and append its line to the map's `Decisions so far` **now**, at
build — not at close.

### 3. Publish check

Runs at the end of **every** session — including pure-tending ones. A tending session can make
a slab eligible without building anything: ruling a ticket out of scope, or dispositioning a
thread as "ticket it" and resolving the fog it named, both clear the gate. If the check only
ran after a build, those would go unnoticed, and the map's final slab would have no trigger at
all.

**Most sessions publish nothing** — the gate says no. That is the check working, not failing.

1. **Manifests.** Collect `## Paths` from every `In Progress` ticket's resolution comment.
2. **Candidates.** Diff the build branch against the lowest unpublished point — the branch below
   it in the stack, or `main` on the first publish. Group the unpublished paths into slabs by
   the [order](#order).
3. **Fog gate.** Read the open `Todo` ticket Questions and the map's `Not yet specified`. Could
   resolving any of them redefine these paths? Judgment over two short texts.
4. **Self-containment.** Cut the split, then run the **whole green set** on the split branch —
   unscoped, exactly as written. Scoping the turbo filter to the slab's own packages defeats
   the check, whose entire point is that nothing above compensates for what's missing.
   - Fails → **widen the slab and return to step 3.** Widening pulls in paths that were never
     fog-gated, so they need the gate before they cross. If widening far enough to compile
     would necessarily cross the fog line, **the fog wins** — [back the slab out](#backing-a-slab-out)
     and let it harden.
5. **Publish** — the runbook below.

## Publishing a slab

Do these in order: **write** the brief and the PR description first, **then** run the split —
its last command attaches the description you already wrote, so nothing is ever pushed without
one.

### 1. The Stack Brief

A **Linear doc on the map**, not a PR comment — the base PR merges and would take a PR-hosted
brief with it, and this document changes at every publish.

It carries the **published spine only**. Work above the horizon is already enumerated live in
the map's `In Progress` column; a second copy goes stale the moment a ticket lands. Graphite
renders the mechanical spine into every PR body, so the brief carries **narrative only**.

```markdown
# Stack Brief — <map name>

Build branch: `john/eng-NNNN-…` · Map: <link>

## Horizon

Published through **<PR title>** (#N). Everything above it is still prototype — built, not cut.
See the map's In Progress column. **This stack will grow.**

## Published spine — merge order

1. **<PR title>** (#N) — <what it changes>. Separate because <why>. `merged`
2. **<PR title>** (#N) — <what it changes>. Separate because <why>.
   - Provisional: <residual risk — omit when there is none>
   - Unwired: <what, and which PR lands the wire-up>

## Read order

<merge order unless stated otherwise; which PRs can merge independently>
```

Record the **residual risk**, not the clearance. "Nothing open touches this" is noise; "this
contract's consumers land above the horizon and may pull on its shape" is what a reviewer and
future-you both need.

The horizon line is not optional. Without it a reviewer reasonably reads the last PR as the end
of the story and flags every unwired seam as a miss.

**No PR opens for review until the brief exists.** Published PRs open **ready for review**, not
draft — early feedback is the whole point of the horizon, and a draft doesn't get any. The green
set plus step 4 is what satisfies "untested work defaults to draft"; it isn't bypassed, it's
met.

FUSE quirk: a new Linear doc takes its title from the **first body line**, not the filename.
Create it, then fix the `title:` frontmatter.

### 2. PR description

Write this **now**, before the split — the last split command attaches it, so it must already
exist on disk.

```markdown
<details>
<summary>Wayfinder bookkeeping</summary>

Map: <map name + link> · Build branch: `john/eng-NNNN-…`
Tickets completed by this PR: ENG-1234, ENG-1235, ENG-1240

</details>
```

List a ticket in the PR that **completes** it — the one that brings its last remaining path
below the horizon — and **only there**. Never re-list a ticket an earlier PR already carried:
that re-fires Linear's on-open transition and can drag a `Done` ticket back to `In Review`.
Straddlers appear nowhere, so they stay `In Progress`:

> **If you can't list a ticket in a PR description, it isn't below the horizon.**

`<details>`, not an HTML comment — whether Linear's parser reads inside `<!-- -->` is unverified,
and if it doesn't, the automation dies silently and the board rots with nobody noticing.
`<details>` is real text with the same invisibility and no bet.

### 3. The split

Run splits **in merge order — the slab that merges first comes out first** — and run each one
**from the build branch**. `gt split --by-file` is the only non-interactive form; it lifts the
matching files into a new **parent** of the branch you ran from, so each extraction slots in
directly below the build branch and above everything already published.

```bash
gt squash -n                                            # one commit = the tested tree
gt split --by-file -f <path> -f <path> -f <path>        # repeat -f per pattern
gt checkout <build-branch>_split                        # gt rename acts on the CURRENT branch
gt rename <ticket-branch>                               # BEFORE submit
gt submit --no-interactive                              # pushes trunk → here; tip has no PR, so it can't be swept in
gh pr edit <ticket-branch> --body-file <description.md> # attach the bookkeeping block written in step 2
```

`gt submit` creates the PR without the bookkeeping block — graphite's own metadata fills the
body by default — so `gh pr edit` overwrites it with the description you already wrote. Run it
in the same breath as submit; nothing is "opened for review" in a meaningful sense until both
have run.

Four traps:

- **`gt squash` opens `$EDITOR` by default.** `-n` is not optional in an agent session.
- **`gt rename` renames whatever is checked out.** Skip the `gt checkout` and you rename the
  *build branch*, then submit the entire prototype region as one PR — the exact failure this
  skill exists to prevent.
- **Names.** Splits come out as `<branch>_split`, `<branch>_split_split`, …. Rename before
  submitting; renaming a branch that already has a PR requires `--force` and breaks the
  association. Name it for the ticket whose work dominates the slab; where a slab spans several
  tickets evenly, name it for what the slab *is*, not who built it.
- **Shared files.** A file two slabs both touch can't be divided by path, and `--by-hunk` can't
  run non-interactively. Prefer **folding the two slabs into one PR**. If they must separate, do
  a manual pass: let the file land in the lower slab, edit it down on that branch to just the
  lower half, and let the restack carry the remainder up.

Fold aggressively **while work is still above the horizon** — past the horizon there is no
folding, only fix-PRs. This does pull against greedy, which minimises how much sits above the
line at once. Greedy wins on timing; fold within the slab you're about to cut.

## Backing a slab out

The inverse of a split, needed by publish-check step 4 and by the cheap tier of the re-cut
gradient. **From the build branch:**

```bash
gt checkout <build-branch>
gt fold --keep --no-interactive        # add --close if the slab already has a PR
```

`gt fold` folds the current branch into its **parent**; `--keep` retains the current branch's
name. So run from the build branch, it absorbs the split back and the build branch survives
under its own name.

**Running `gt fold` from the split branch instead folds unpublished, un-green code into the
published PR below it.** That is the intuitive move and it is wrong.

## Merging

**Merge as approved.** The spine drains from the bottom while you keep building at the top, so
the stack stays shallow and there's no cascade at the end.

That's safe because of the [order](#order): wiring and surface merge **last**, so everything
merging early is **inert by construction** — it can't reach a user, because the layer that
reaches users is the layer that merges last. If you ever find yourself publishing surface early,
that inversion is the signal to stop and re-examine, not to reach for a flag.

## Endgame

The map closes when the **last PR merges** and every ticket is `Done`. An execution map's
destination is the change *made*, not the change *written*.

So the map has a tail with nothing left to build, where sessions are pure tending — and the
publish check still runs in every one of them, which is what eventually fires the final publish.

The last slab is the remainder of the build branch. Publish it by **renaming the build branch
itself and submitting it** — it has no PR, so the rename is free and no split is needed:

```bash
gt rename <ticket-branch>
gt submit --no-interactive
```

If the map ticket's own branch name is the honest name for that remainder, keep it. The build
branch is the prototype region right up until there is no prototype left.

## Worked example

Three sessions of a map with a `CONTEXT.md` glossary change, a parser, and its caller.

**Session 1.** Builds ENG-1201 (grilling — "what do we call this thing?"). Empty `## Paths` →
closes straight to `Done`. Publish check: nothing built, no slab. Publishes nothing.

**Session 2.** Builds ENG-1202 — glossary entries plus the parser — green, `In Progress`,
manifest `CONTEXT.md`, `packages/foo/src/parse.ts`. Publish check: two slabs. The glossary is
order-1 and no open ticket touches it → crosses. The parser is order-3, but open ticket ENG-1204
("how are malformed inputs surfaced?") could redefine its signature → **stays above**. One
publish: `gt squash -n` → split `CONTEXT.md` → checkout `_split` → rename → submit as PR #1.
Brief created. ENG-1202 straddles, so it appears in no PR description and stays `In Progress`.

**Session 3.** Resolves ENG-1204, builds the caller as ENG-1205. Publish check: with ENG-1204
closed, nothing open touches the parser. Parser and caller both cross. Two splits, in merge
order — parser first (PR #2), then caller (PR #3). ENG-1202's last path lands in PR #2, so PR #2
lists it; PR #3 lists ENG-1205 only. Both flip to `In Review`. Brief updated: horizon now at #3.

Build branch is empty of unpublished work; the next session is pure tending until the PRs merge.

## Overrides to the base wayfinder skill

Mark these as deliberate where they come up — they read as contradictions otherwise.

- **Code-producing tickets do not close at resolution.** They close when their PR merges;
  resolution moves them to `In Progress`. **Tickets with an empty `## Paths` manifest close at
  resolution as normal.**
- **`Decisions so far` appends at build, not at close.** The map is an index *for sessions*, and
  what a session orients against is the build branch, not trunk. Waiting for merge would leave
  a later session blind to everything already built.
- **No parallel sessions.** The base skill expects concurrent sessions on unblocked tickets; one
  map = one branch = one worktree makes that unsafe here. The assignee still carries the claim —
  it just guards against your own next session, not a simultaneous one.
- **Don't wire a blocking edge that would strand a dependent behind review.** Since a
  code-producing ticket stays open until merge, a literal reading of "unblocked when every
  blocker is closed" would stall the map for a review cycle. Most of those edges encode build
  order the single branch already enforces.
- **Bare identifiers in PR descriptions.** The base skill says refer to tickets by name, never
  by bare id. Linear's automation matches on the identifier, so the bookkeeping block uses bare
  ids deliberately. "Fixing" them into named links silently breaks every transition. Everywhere
  a human reads — the brief, the map, narration — names still win.
- **There is a built-but-not-landed half-state**, and it is precisely the prototype region.

## What this costs

- **No folding past the horizon.** A late fix to published work is a fix-PR, not a fold. That's
  the price of early feedback; the gate is what keeps the bill small.
- **The prototype region is CI-dark.** The first real pipeline signal arrives at publish.
- **Sessions get uneven.** Some publish nothing. Some are all tending and no ticket.

Two tells that you're publishing too early: **straddlers piling up in `In Progress`**, and
**fix-PRs landing against already-published files**.
