# `gh prs --tree` design

## Problem

`gt ls` shows the Graphite stack tree clearly but has no PR or CI signal.
`gh prs` shows PR/CI/Linear/UNRES columns but has no stack structure. Today
they're consulted side-by-side. Goal: one view that combines both.

## Solution

Add a `--tree` / `-t` flag to the existing `gh/.local/bin/gh-prs`. The flag
swaps the renderer — all fetch, color, and hyperlink logic is reused.

### Output

```
◯    john/eng-4601-anvil-05c-prisma-evaluators                 ◐ #1235  2
│ ◯  john/eng-4624-anvil-06a-pr2-onboarding-endpoint           ● #1240  -
│ ◯  john/eng-4624-anvil-06a-pr1-anvil-graph-runner            ● #1239  -
◉─┘  john/eng-4598-anvil-05c-pr3-admin-package (needs restack) ✗ #1230  3
◯    main
```

**Left column** — `gt ls` output verbatim. Preserves tree glyphs, the
current-branch marker (`◉`), and annotations like `(needs restack)`.

**Right column, right-justified to terminal width** — `<CI> #<num>  <unres>`:

| Field | Encoding |
|-------|----------|
| CI glyph | `●` pass (green), `◐` running (yellow), `✗` fail (red) |
| PR# | Existing gh-prs review-state colors: grey=draft, green=approved, yellow=pending, magenta=changes-requested, red=conflict. OSC8 hyperlink to Graphite. |
| UNRES | Red count if >0, dim `-` if 0 |

Branches with no PR (e.g. `main`, untracked branches) render only the left
column — no glyph, no PR#, no UNRES.

### Layout

The right column is fixed-width: `glyph(1) + space + #NNNN(5) + 2 spaces +
unres(2)` ≈ 11 chars plus a 2-space gutter. Each gt-ls line is padded with
spaces so the right column ends at `tput cols`. Lines that would overflow
the terminal width keep the gt-ls portion intact and clip the gap (the right
column is not negotiable; the tree never gets cut).

### Branch-name extraction

For each `gt ls` line, strip leading tree characters (`◯ ◉ │ ─ ┘ └ ├` and
spaces) and any trailing ` (annotation)`. The remainder is the branch name,
used as the join key against PR data.

## Behavior

1. **Branch order** comes from `gt ls`, not from `updatedAt`.
2. **Watch mode** is not supported with `--tree` (out of scope for now).
   Passing `--watch --tree` is an error.
3. **Not in a Graphite-tracked stack** is an error: print a hint pointing
   at `gt track` and exit non-zero. No fallback to the table.
4. **`--tree` and `--branch` are mutually exclusive** — the tree already
   shows branch names. Passing both is an error.

## Implementation outline

Existing `gh-prs` already produces a TSV row per PR via its `jq` pipeline
(`number`, `review_state`, `ci_state`, `linear`, `unresolved`, `title`,
`branch`). The `--tree` renderer:

1. Run `gt ls`, capture stdout. If `gt ls` errors (e.g. not in a tracked
   stack), surface its stderr and exit non-zero. `gt` auto-disables color
   when piped, so the captured output is plain text.
2. Reuse the existing PR fetch + jq pipeline to build a `branch -> {pr_num,
   review_state, ci_state, unres}` map (Linear and title are unused here).
3. For each `gt ls` line:
   - Pass the line through unchanged for the left side, but keep a copy of
     the original (with color escapes) for display.
   - Extract the branch name (per the rule above).
   - If the branch is in the PR map, build the right column with the same
     color/hyperlink helpers gh-prs already uses.
   - Compute padding so the right column ends at `tput cols`. Visible-width
     calculation must skip ANSI escapes and OSC8 sequences — the existing
     awk renderer already does this for column padding and can be reused.
   - Print `left + padding + right`.

### File changes

- `gh/.local/bin/gh-prs` — add `--tree`/`-t` parsing, the new renderer
  branch, the gt-ls runner, and the branch-name extractor. The current
  table renderer stays as the default.

## Out of scope

- Watch mode for `--tree`.
- Showing PR title or Linear ID in tree mode (intentionally minimal — the
  tree is already wide).
- Non-Graphite repos.
- Configurable column ordering.
