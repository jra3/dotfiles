# `gh prs --tree` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `--tree`/`-t` flag to `gh-prs` that renders the Graphite stack tree on the left with right-justified per-PR status (CI glyph + colored PR number + unresolved-thread count).

**Architecture:** New code lives in the existing `gh/.local/bin/gh-prs` bash script. The script's bottom-of-file dispatch is wrapped in a `main` function with a source-guard so the renderer helpers can be unit-tested by sourcing the script. Tests live in `tests/gh-prs.bats` using the **bats** framework (`bats`, `bats-assert`, `bats-support` from the Arch `extra` repo). Renderer is built from three pure functions (`_extract_branch_name`, `_format_pr_cell`, `_render_tree`) plus a runtime wrapper (`fetch_tree`) that calls `gt ls` and the existing GraphQL pipeline.

**Tech Stack:** bash 5+, awk, jq, gh CLI, Graphite (`gt`), bats-core 1.13+, bats-assert 2.2+, bats-support 0.3+.

---

## Pre-flight

The bats packages must be installed before tests can run. They've been added to `pacman/packages-arch.txt`. If not yet installed:

```bash
sudo pacman -S --needed bats bats-assert bats-support
```

Verify: `bats --version` should print `Bats 1.13.0` (or newer).

The Arch packages place loadable helpers at `/usr/lib/bats-support` and `/usr/lib/bats-assert`. The plan uses `bats_load_library` (bats ≥ 1.7) which searches `BATS_LIB_PATH` and falls back to `/usr/lib`.

---

## File Structure

| File | Responsibility |
|---|---|
| `gh/.local/bin/gh-prs` (modify) | Adds new helpers, `fetch_tree`, `--tree` flag, source-guard, and a `main` function wrapping the existing dispatch. |
| `tests/gh-prs.bats` (create) | Bats test file. Sources `gh-prs` in `setup()`, exercises the new helpers, and runs `gh-prs` as a subprocess for arg-parse error tests. |

Tests live at the repo root in `tests/` so they aren't deployed by `stow`. The repo already has `scripts/` at the top level (not a stow package), so this convention exists.

---

## Task 1: Wrap dispatch in `main`, add source-guard, set UTF-8 locale

**Goal:** Make the script sourceable so tests can call its functions, and ensure multi-byte glyph widths work correctly.

**Files:**
- Modify: `gh/.local/bin/gh-prs`

- [ ] **Step 1: Read the current script structure**

Run: `cat gh/.local/bin/gh-prs | head -20 && echo --- && tail -20 gh/.local/bin/gh-prs`

You should see arg parsing at the top and the `if [[ $WATCH -eq 1 ]]; then ... else fetch_prs; fi` dispatch at the bottom.

- [ ] **Step 2: Add LC_ALL near the top**

Edit `gh/.local/bin/gh-prs`. Immediately after the shebang comment block (before `WATCH=0`), add:

```bash
# Ensure ${#var} counts characters (not bytes) for multi-byte glyphs.
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
```

- [ ] **Step 3: Wrap the bottom dispatch in `main()` with a source-guard**

Replace the bottom dispatch (the `if [[ $WATCH -eq 1 ]]; then ... fi` block) and the entire arg-parsing `while [[ $# -gt 0 ]]; do ... done` block with a `main` function. Move both into it. The end of the file becomes:

```bash
main() {
  WATCH=0
  INTERVAL=15
  SHOW_BRANCH=0

  while [[ $# -gt 0 ]]; do
    case $1 in
      --watch|-w)
        WATCH=1
        if [[ ${2:-} =~ ^[0-9]+$ ]]; then
          INTERVAL=$2
          shift
        fi
        shift
        ;;
      --branch|-b)
        SHOW_BRANCH=1
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  if [[ $WATCH -eq 1 ]]; then
    # Enter alternate screen buffer + hide cursor; restore both on exit.
    printf '\033[?1049h\033[H'
    tput civis
    trap 'tput cnorm; printf "\033[?1049l"; exit 0' INT TERM EXIT
    while true; do
      output=$(fetch_prs)
      printf '\033[H\033[2J'  # home + clear screen
      printf '\033[90m[%s] Refreshing every %ss - Ctrl+C to stop\033[0m\n\n' "$(date +%H:%M:%S)" "$INTERVAL"
      echo "$output"
      sleep "$INTERVAL"
    done
  else
    fetch_prs
  fi
}

# Only run main if executed directly, not when sourced (e.g. by tests).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  git rev-parse --git-dir >/dev/null 2>&1 || { echo "Not in a git repository" >&2; exit 1; }
  main "$@"
  exit $?
fi
```

Note: the `git rev-parse` check that previously lived at the top moves into the source-guard so sourcing the script for tests does NOT require being in a git repo.

- [ ] **Step 4: Remove the original top-level `git rev-parse` check and the original arg-parsing/dispatch**

Verify with: `grep -n "git rev-parse" gh/.local/bin/gh-prs` — should appear only inside the source-guard at the bottom.

- [ ] **Step 5: Smoke-test the script still works**

Run: `cd ~/am/overlook && gh-prs | head -5`

Expected: same table output as before, no errors.

- [ ] **Step 6: Verify sourcing works without side effects**

Run: `bash -c 'source gh/.local/bin/gh-prs && declare -f fetch_prs >/dev/null && echo OK'`

Expected: prints `OK` and exits 0. No PR fetch happens because `main` is not called when sourced.

- [ ] **Step 7: Commit**

```bash
git add gh/.local/bin/gh-prs
git commit -m "Refactor gh-prs to be sourceable for testing

Wraps the entry-point dispatch in main(); a BASH_SOURCE guard runs
main only when the script is executed directly. Sets LC_ALL so
\${#var} counts characters (needed for the upcoming tree renderer's
multi-byte glyphs)."
```

---

## Task 2: Bats test scaffold

**Goal:** A runnable bats test file that sources `gh-prs` in `setup()`. Initially empty of feature tests; we'll add them in subsequent tasks.

**Files:**
- Create: `tests/gh-prs.bats`

- [ ] **Step 1: Verify bats is installed**

Run: `bats --version`

Expected: prints `Bats 1.x.y`. If not installed: `sudo pacman -S --needed bats bats-assert bats-support`.

- [ ] **Step 2: Write the scaffold**

Create `tests/gh-prs.bats`:

```bash
#!/usr/bin/env bats
# Tests for gh-prs. Run: bats tests/gh-prs.bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  GHPRS_BIN="$REPO_ROOT/gh/.local/bin/gh-prs"
  # shellcheck disable=SC1090
  source "$GHPRS_BIN"
}

@test "scaffold: bats harness loads and gh-prs sources cleanly" {
  declare -f fetch_prs >/dev/null
}
```

- [ ] **Step 3: Run the test**

Run: `bats tests/gh-prs.bats`

Expected:
```
gh-prs.bats
 ✓ scaffold: bats harness loads and gh-prs sources cleanly

1 test, 0 failures
```

If `bats_load_library bats-support` fails with "library not found", set `BATS_LIB_PATH=/usr/lib` and re-run, or replace the two `bats_load_library` lines with:

```bash
load '/usr/lib/bats-support/load'
load '/usr/lib/bats-assert/load'
```

- [ ] **Step 4: Commit**

```bash
git add tests/gh-prs.bats
git commit -m "Add bats scaffold for gh-prs tests

Loads bats-support and bats-assert, sources gh-prs in setup().
Empty test placeholder confirms the harness wires up correctly."
```

---

## Task 3: `_extract_branch_name` helper

**Goal:** Pure function that pulls the branch name out of a `gt ls` line. Strips leading tree drawing characters and trailing parenthesized annotations.

**Files:**
- Modify: `gh/.local/bin/gh-prs`
- Modify: `tests/gh-prs.bats`

- [ ] **Step 1: Write the failing tests**

In `tests/gh-prs.bats`, replace the scaffold `@test` with these:

```bash
@test "extract_branch_name: simple branch on its own row" {
  run _extract_branch_name '◯    main'
  assert_success
  assert_output 'main'
}

@test "extract_branch_name: indented child branch" {
  run _extract_branch_name '│ ◯  john/eng-4624-anvil-06a-pr2-onboarding-endpoint'
  assert_success
  assert_output 'john/eng-4624-anvil-06a-pr2-onboarding-endpoint'
}

@test "extract_branch_name: current branch with merge connector and annotation" {
  run _extract_branch_name '◉─┘  john/eng-4598-anvil-05c-pr3-admin-package (needs restack)'
  assert_success
  assert_output 'john/eng-4598-anvil-05c-pr3-admin-package'
}

@test "extract_branch_name: branch with tracking annotation" {
  run _extract_branch_name '◯    john/eng-4601-anvil-05c-prisma-evaluators (eng-4601-fix)'
  assert_success
  assert_output 'john/eng-4601-anvil-05c-prisma-evaluators'
}
```

- [ ] **Step 2: Run the tests — they should fail**

Run: `bats tests/gh-prs.bats`

Expected: 4 failures (`_extract_branch_name: command not found`).

- [ ] **Step 3: Implement `_extract_branch_name`**

In `gh/.local/bin/gh-prs`, add this function above `fetch_prs()`:

```bash
# Given a `gt ls` line, echo the branch name.
# Strips leading tree-drawing chars/spaces and any trailing " (annotation)".
# Tree chars are multi-byte UTF-8 (◯ ◉ │ ─ ┘ └ ├ etc); since branch names start
# with an ASCII letter, we strip everything up to the first ASCII letter.
_extract_branch_name() {
  printf '%s' "$1" | sed -E 's/^[^A-Za-z]*//; s/ *\([^)]*\) *$//'
}
```

- [ ] **Step 4: Run the tests — they should pass**

Run: `bats tests/gh-prs.bats`

Expected: `4 tests, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add gh/.local/bin/gh-prs tests/gh-prs.bats
git commit -m "Add _extract_branch_name helper for tree renderer

Pulls the branch name out of a gt-ls line by stripping leading tree
drawing characters and any trailing parenthesized annotation."
```

---

## Task 4: `_format_pr_cell` helper

**Goal:** Pure function that returns the right-justified PR cell with CI glyph, colored PR# (with OSC8 hyperlink), and UNRES count. Returns `<visible_width>\t<styled_text>`.

**Files:**
- Modify: `gh/.local/bin/gh-prs`
- Modify: `tests/gh-prs.bats`

- [ ] **Step 1: Write the failing tests**

Append to `tests/gh-prs.bats`:

```bash
@test "format_pr_cell: approved + pass + unres=0 — width and styled bytes" {
  run _format_pr_cell 1234 approved pass 0 'https://g.example'
  assert_success

  # Output is "<width>\t<styled>". Visible cell: "● #1234  -" = 10 chars.
  local width="${output%%$'\t'*}"
  local styled="${output#*$'\t'}"
  local expected_styled
  expected_styled=$'\e[32m●\e[0m \e]8;;https://g.example/1234\e\\\e[32m#1234\e[0m\e]8;;\e\\  \e[90m-\e[0m'

  assert_equal "$width" "10"
  assert_equal "$styled" "$expected_styled"
}

@test "format_pr_cell: changes + fail + unres=2" {
  run _format_pr_cell 9 changes fail 2 'https://g.example'
  assert_success

  # Visible: "✗ #9  2" = 1+1+2+2+1 = 7.
  local width="${output%%$'\t'*}"
  local styled="${output#*$'\t'}"
  local expected_styled
  expected_styled=$'\e[31m✗\e[0m \e]8;;https://g.example/9\e\\\e[35m#9\e[0m\e]8;;\e\\  \e[31m2\e[0m'

  assert_equal "$width" "7"
  assert_equal "$styled" "$expected_styled"
}

@test "format_pr_cell: draft + running + unres=10 (two-digit)" {
  run _format_pr_cell 12 draft running 10 'https://g.example'
  assert_success

  # Visible: "◐ #12  10" = 1+1+3+2+2 = 9.
  local width="${output%%$'\t'*}"
  assert_equal "$width" "9"
}

@test "format_pr_cell: empty review and CI states use neutral defaults" {
  run _format_pr_cell 42 '' '' 0 'https://g.example'
  assert_success
  # Glyph defaults to space (visible width 1), PR# uses default color (0).
  local width="${output%%$'\t'*}"
  # Visible: " #42  -" = 1+1+3+2+1 = 8.
  assert_equal "$width" "8"
}
```

- [ ] **Step 2: Run the tests — they should fail**

Run: `bats tests/gh-prs.bats`

Expected: 4 new failures (`_format_pr_cell: command not found`).

- [ ] **Step 3: Implement `_format_pr_cell`**

In `gh/.local/bin/gh-prs`, add below `_extract_branch_name`:

```bash
# Build the right-side PR cell. Returns "<visible_width>\t<styled_text>".
# Args: pr_num review_state ci_state unres graphite_base
#   review_state ∈ {draft,approved,pending,changes,conflict,""}
#   ci_state ∈ {pass,running,fail,""}
_format_pr_cell() {
  local pr_num=$1 review=$2 ci=$3 unres=$4 base=$5
  local ESC=$'\e'

  local glyph glyph_c
  case "$ci" in
    pass)    glyph='●'; glyph_c=32 ;;
    running) glyph='◐'; glyph_c=33 ;;
    fail)    glyph='✗'; glyph_c=31 ;;
    *)       glyph=' '; glyph_c=0 ;;
  esac

  local pr_c
  case "$review" in
    draft)    pr_c=90 ;;
    approved) pr_c=32 ;;
    pending)  pr_c=33 ;;
    changes)  pr_c=35 ;;
    conflict) pr_c=31 ;;
    *)        pr_c=0 ;;
  esac

  local unres_text unres_c
  if [[ $unres =~ ^[0-9]+$ ]] && (( unres > 0 )); then
    unres_text=$unres; unres_c=31
  else
    unres_text='-'; unres_c=90
  fi

  local link_start="${ESC}]8;;${base}/${pr_num}${ESC}\\"
  local link_end="${ESC}]8;;${ESC}\\"
  local glyph_part="${ESC}[${glyph_c}m${glyph}${ESC}[0m"
  local pr_part="${link_start}${ESC}[${pr_c}m#${pr_num}${ESC}[0m${link_end}"
  local unres_part="${ESC}[${unres_c}m${unres_text}${ESC}[0m"

  local plain="${glyph} #${pr_num}  ${unres_text}"
  printf '%d\t%s %s  %s' "${#plain}" "$glyph_part" "$pr_part" "$unres_part"
}
```

- [ ] **Step 4: Run the tests — they should pass**

Run: `bats tests/gh-prs.bats`

Expected: all tests pass.

If a styled-bytes assertion fails, bats prints a diff between expected and actual; the most likely cause is a mismatched escape sequence in the expected string. The test uses `$'...'` which interprets `\e` as ESC and `\\` as a single backslash. The function builds the same sequence using `${ESC}\\` inside double-quotes (also yielding ESC + single backslash). They should match byte-for-byte.

- [ ] **Step 5: Commit**

```bash
git add gh/.local/bin/gh-prs tests/gh-prs.bats
git commit -m "Add _format_pr_cell helper for tree renderer

Returns visible-width and styled-text (tab-separated) for a PR's
right-side cell: CI glyph + colored PR# (OSC8 link) + UNRES count.
Tests cover four review/CI/UNRES combinations including defaults."
```

---

## Task 5: `_render_tree` orchestrator

**Goal:** Pure function that takes the captured `gt ls` output, a TSV PR-data table, the Graphite URL base, and the terminal width — and emits the joined tree.

**Files:**
- Modify: `gh/.local/bin/gh-prs`
- Modify: `tests/gh-prs.bats`

- [ ] **Step 1: Write the failing test**

Append to `tests/gh-prs.bats`:

```bash
@test "render_tree: joins PR data on matching branches and passes others through" {
  local gt_in='◯    foo
◯    main'
  local pr_in='foo	1234	approved	pass	0'

  # Visible "◯    foo" = 8, cell width = 10, term = 60, pad = 60-8-10 = 42.
  # Line 1 = left + 42 spaces + styled cell. Line 2 (main, no PR) passes through.
  local expected_cell
  expected_cell=$'\e[32m●\e[0m \e]8;;https://g.example/1234\e\\\e[32m#1234\e[0m\e]8;;\e\\  \e[90m-\e[0m'
  local pad
  pad=$(printf '%*s' 42 '')
  local expected="◯    foo${pad}${expected_cell}"$'\n''◯    main'

  run _render_tree "$gt_in" "$pr_in" 'https://g.example' 60
  assert_success
  assert_output "$expected"
}

@test "render_tree: empty gt input produces empty output" {
  run _render_tree '' '' 'https://g.example' 80
  assert_success
  assert_output ''
}

@test "render_tree: branch with no matching PR row passes through unchanged" {
  local gt_in='◯    untracked-branch'
  run _render_tree "$gt_in" '' 'https://g.example' 80
  assert_success
  assert_output '◯    untracked-branch'
}
```

- [ ] **Step 2: Run the tests — they should fail**

Run: `bats tests/gh-prs.bats`

Expected: 3 new failures (`_render_tree: command not found`).

- [ ] **Step 3: Implement `_render_tree`**

In `gh/.local/bin/gh-prs`, add below `_format_pr_cell`:

```bash
# Render the joined tree.
# Args: gt_output pr_tsv graphite_base term_width
#   pr_tsv has one row per PR, tab-separated: branch \t num \t review \t ci \t unres
#   gt_output is the captured stdout of `gt ls` (no color escapes when piped).
_render_tree() {
  local gt_output=$1 pr_tsv=$2 base=$3 term_width=$4
  local -A prmap=()

  if [[ -n "$pr_tsv" ]]; then
    while IFS=$'\t' read -r branch num review ci unres; do
      [[ -z "$branch" ]] && continue
      prmap[$branch]="${num}	${review}	${ci}	${unres}"
    done <<< "$pr_tsv"
  fi

  [[ -z "$gt_output" ]] && return 0

  local line branch num review ci unres cell_w cell pad left_w
  while IFS= read -r line; do
    branch=$(_extract_branch_name "$line")
    if [[ -n "$branch" && -n "${prmap[$branch]+x}" ]]; then
      IFS=$'\t' read -r num review ci unres <<< "${prmap[$branch]}"
      IFS=$'\t' read -r cell_w cell < <(_format_pr_cell "$num" "$review" "$ci" "$unres" "$base")
      left_w=${#line}
      pad=$(( term_width - left_w - cell_w ))
      (( pad < 2 )) && pad=2
      printf '%s%*s%s\n' "$line" "$pad" '' "$cell"
    else
      printf '%s\n' "$line"
    fi
  done <<< "$gt_output"
}
```

- [ ] **Step 4: Run the tests — they should pass**

Run: `bats tests/gh-prs.bats`

Expected: all tests pass.

If the first assertion fails because of pad width, inspect with:
```bash
bats tests/gh-prs.bats --verbose-run --show-output-of-passing-tests
```
or compare bytes:
```bash
diff <(printf '%s' "$expected") <(printf '%s' "$actual") | cat -A | head
```

- [ ] **Step 5: Commit**

```bash
git add gh/.local/bin/gh-prs tests/gh-prs.bats
git commit -m "Add _render_tree orchestrator

Builds an associative array from the PR TSV, then walks each gt-ls
line: extracts the branch, joins to PR data when present, pads so
the right cell ends at terminal width. Lines without a matching PR
entry pass through unchanged."
```

---

## Task 6: `fetch_tree` runtime

**Goal:** Real-environment wrapper that calls `gt ls`, fetches PR data via the existing GraphQL pattern, then calls `_render_tree`. No automated test (depends on `gh`/`gt` and a real repo).

**Files:**
- Modify: `gh/.local/bin/gh-prs`

- [ ] **Step 1: Add `fetch_tree`**

In `gh/.local/bin/gh-prs`, add a `fetch_tree` function above `main`:

```bash
fetch_tree() {
  local REPO_URL OWNER REPO TERM_WIDTH GRAPHITE_BASE GT_OUT PR_JSON UNRES_JSON QUERY pr_aliases num PR_TSV
  IFS=$'\t' read -r OWNER REPO REPO_URL < <(gh repo view --json owner,name,url -q '[.owner.login, .name, .url] | @tsv')
  GRAPHITE_BASE="https://app.graphite.dev/github/pr/${OWNER}/${REPO}"
  TERM_WIDTH=$(tput cols 2>/dev/null || echo 120)

  GT_OUT=$(gt ls 2>&1) || {
    printf '%s\n' "$GT_OUT" >&2
    echo "Run 'gt track' if this branch is not yet tracked." >&2
    return 1
  }

  PR_JSON=$(gh pr list --author @me --state open \
    --json number,title,isDraft,reviewDecision,mergeable,statusCheckRollup,headRefName,updatedAt)

  pr_aliases=""
  while IFS= read -r num; do
    [[ -z "$num" ]] && continue
    pr_aliases+="    p${num}: pullRequest(number: ${num}) { reviewThreads(first: 100) { nodes { isResolved } } }"$'\n'
  done < <(echo "$PR_JSON" | jq -r '.[].number')

  if [[ -n "$pr_aliases" ]]; then
    QUERY="query { repository(owner: \"${OWNER}\", name: \"${REPO}\") {"$'\n'"${pr_aliases}  } }"
    UNRES_JSON=$(gh api graphql -f query="$QUERY" 2>/dev/null || echo '{}')
  else
    UNRES_JSON='{}'
  fi

  PR_TSV=$(echo "$PR_JSON" | jq -r --argjson unres "$UNRES_JSON" '
    ($unres.data.repository // {}) as $repo |
    .[] |
    (($repo["p\(.number)"].reviewThreads.nodes // [])
      | map(select(.isResolved == false))
      | length) as $unresolved |
    [
      .headRefName,
      (.number | tostring),
      (if .isDraft then "draft"
       elif .mergeable == "CONFLICTING" then "conflict"
       elif .reviewDecision == "CHANGES_REQUESTED" then "changes"
       elif .reviewDecision == "APPROVED" then "approved"
       else "pending" end),
      (if .statusCheckRollup == null or .statusCheckRollup == [] then "pending"
       else (.statusCheckRollup
         | map(select(((.name // .context) // "") | test("^Graphite / mergeability_check$") | not))
         | if length == 0 then "pass"
           elif any(.status == "IN_PROGRESS" or .status == "QUEUED" or .status == "PENDING") then "running"
           elif any(.conclusion == "FAILURE" or .conclusion == "failure") then "fail"
           else "pass" end) end),
      ($unresolved | tostring)
    ] | @tsv')

  _render_tree "$GT_OUT" "$PR_TSV" "$GRAPHITE_BASE" "$TERM_WIDTH"
}
```

The jq filter is the same as `fetch_prs` minus Linear and title, with column order matching `_render_tree`'s expected `branch \t num \t review \t ci \t unres`.

- [ ] **Step 2: Smoke-test from a real repo (manual)**

Run:
```bash
cd ~/am/overlook
bash -c 'source ~/.dotfiles/gh/.local/bin/gh-prs && fetch_tree'
```

Expected: tree output joined with PR cells, similar to:
```
◯    john/eng-4602-anvil-05c-external-dep-evaluators           ◐ #1235  2
◯    john/eng-4601-anvil-05c-prisma-evaluators                 ● #1234  -
...
◯    main
```

If `gt ls` errors, the function should print stderr from gt and the hint message, then return non-zero.

- [ ] **Step 3: Commit**

```bash
git add gh/.local/bin/gh-prs
git commit -m "Add fetch_tree runtime

Calls gt ls, runs the same gh+graphql pipeline as fetch_prs but with
a slimmer jq output (branch, num, review, ci, unres), then renders
via _render_tree."
```

---

## Task 7: `--tree` flag with mutual exclusion

**Goal:** Argument parsing accepts `--tree`/`-t`. Combining it with `--watch` or `--branch` exits non-zero with an error.

**Files:**
- Modify: `gh/.local/bin/gh-prs`
- Modify: `tests/gh-prs.bats`

- [ ] **Step 1: Write failing tests for the error paths**

Append to `tests/gh-prs.bats`:

```bash
@test "cli: --tree --watch is rejected" {
  run "$GHPRS_BIN" --tree --watch
  assert_failure
  assert_output --partial '--tree'
  assert_output --partial '--watch'
}

@test "cli: --tree --branch is rejected" {
  run "$GHPRS_BIN" --tree --branch
  assert_failure
  assert_output --partial '--tree'
  assert_output --partial '--branch'
}
```

- [ ] **Step 2: Run the tests — they should fail**

Run: `bats tests/gh-prs.bats`

Expected: both new tests fail. The `assert_failure` line will fail because the script currently ignores unknown flags and runs normally (exit 0).

- [ ] **Step 3: Add `--tree` parsing and validation in `main`**

Inside `main()`, add `TREE=0` next to the other defaults:

```bash
WATCH=0
INTERVAL=15
SHOW_BRANCH=0
TREE=0
```

Add a case in the arg loop, between `--branch|-b)` and the `*)` catch-all:

```bash
    --tree|-t)
      TREE=1
      shift
      ;;
```

After the `done` of the arg loop, add validation:

```bash
  if (( TREE == 1 )); then
    if (( WATCH == 1 )); then
      echo "error: --tree and --watch are mutually exclusive" >&2
      return 1
    fi
    if (( SHOW_BRANCH == 1 )); then
      echo "error: --tree and --branch are mutually exclusive" >&2
      return 1
    fi
  fi
```

The `return 1` from `main` propagates via the source-guard's `exit $?`, which we already added in Task 1.

- [ ] **Step 4: Run the tests — they should pass**

Run: `bats tests/gh-prs.bats`

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add gh/.local/bin/gh-prs tests/gh-prs.bats
git commit -m "Add --tree flag with mutual exclusion against --watch/--branch

Tests run gh-prs as a subprocess and assert non-zero exit plus an
error message that mentions both conflicting flags."
```

---

## Task 8: Wire `--tree` into the dispatch + update help

**Goal:** When `TREE=1`, call `fetch_tree`. Update the script's header comment to document the flag.

**Files:**
- Modify: `gh/.local/bin/gh-prs`

- [ ] **Step 1: Dispatch on TREE in `main`**

Replace the existing dispatch block in `main`:

```bash
  if [[ $WATCH -eq 1 ]]; then
    ...
  else
    fetch_prs
  fi
```

with:

```bash
  if (( TREE == 1 )); then
    fetch_tree
  elif [[ $WATCH -eq 1 ]]; then
    # Enter alternate screen buffer + hide cursor; restore both on exit.
    printf '\033[?1049h\033[H'
    tput civis
    trap 'tput cnorm; printf "\033[?1049l"; exit 0' INT TERM EXIT
    while true; do
      output=$(fetch_prs)
      printf '\033[H\033[2J'  # home + clear screen
      printf '\033[90m[%s] Refreshing every %ss - Ctrl+C to stop\033[0m\n\n' "$(date +%H:%M:%S)" "$INTERVAL"
      echo "$output"
      sleep "$INTERVAL"
    done
  else
    fetch_prs
  fi
```

- [ ] **Step 2: Update the script's header usage comment**

At the top of `gh/.local/bin/gh-prs`, change the `Usage:` block to include `--tree`:

```bash
# Usage: gh prs [--watch [SECONDS]] [--branch] [--tree]
#   --watch         Refresh every 15 seconds (default)
#   --watch N       Refresh every N seconds
#   --branch, -b    Show branch names instead of PR titles
#   --tree, -t      Render the Graphite stack tree (`gt ls`) with right-justified
#                   PR# (review-state colored, CI-glyph prefixed) and unresolved-
#                   thread count. Mutually exclusive with --watch and --branch.
```

- [ ] **Step 3: Smoke test the full flow**

Run:
```bash
cd ~/am/overlook
gh prs --tree
```

Expected: tree from `gt ls` with right-justified PR cells. PR# is clickable (Ctrl+click in Ghostty). Branches without PRs show only the tree row.

Verify column alignment by inspecting where the right cell lands relative to the terminal edge.

- [ ] **Step 4: Re-run the full test suite**

Run: `bats tests/gh-prs.bats`

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add gh/.local/bin/gh-prs
git commit -m "Wire --tree into gh-prs dispatch and document in usage

Adds the --tree branch to main's dispatch and updates the header
comment so cat-ing the script shows the new flag."
```

---

## Verification Summary

After all tasks complete, verify:

- [ ] `bats tests/gh-prs.bats` — all tests pass
- [ ] `cd ~/am/overlook && gh prs` — table renderer still works (no regression)
- [ ] `cd ~/am/overlook && gh prs --branch` — branch column renderer still works
- [ ] `cd ~/am/overlook && gh prs --watch 30` — watch mode still works (Ctrl+C to exit)
- [ ] `cd ~/am/overlook && gh prs --tree` — new tree mode works, columns right-justified, links clickable
- [ ] `gh prs --tree --watch` — exits 1 with error
- [ ] `gh prs --tree --branch` — exits 1 with error
- [ ] `cd /tmp && gh prs --tree` — fails gracefully (gt ls reports the issue, fetch_tree returns 1)
