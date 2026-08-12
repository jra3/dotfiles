---
name: gtd
description: Shared helpers for the GTD system in Linear. Not invoked directly — the /gtd-* commands point here.
disable-model-invocation: true
---

Shared home for the GTD system's scripts and reference material. The four `/gtd-*` commands
consult this directory; nothing invokes this skill on its own.

## Where the rules live

Not here. The canonical rules are the **GTD Operating Manual**, a Linear team doc readable at
`~/jra3/linear/teams/GTD/docs/` and editable from the Linear app on a phone. One copy, so a
rule changes in one place. Read it at run time rather than trusting a cached memory of it.

## Scripts

| Script | Does |
|---|---|
| `scripts/gtd-stalled [TEAM]` | Projects with no issue in `Next`/`Doing`/`Waiting`/`Todo`. Defaults to team `GTD`. |

Each is also symlinked into `~/.local/bin`, so John can run it by hand. Edit the copy here —
the one on PATH is a symlink to it.

**Prefer these over ad-hoc counting.** `gtd-stalled` is verified against the API and runs in
~30ms off the FUSE mount with no key and no network. Two commands need the stalled check, and
one implementation that is right beats two that drift.

## Why a script and not a Linear view

Linear cannot express this filter reliably. `projectFilterData` does not round-trip: a filter
that is correct as a live query gets rewritten server-side into one that matches nothing, so a
saved view reports projects as stalled while they hold several active issues. Verified twice.
See `docs/LINEAR-BEHAVIOR.md` in `jra3/linear-fuse`, and jra3/linear-fuse#460.
