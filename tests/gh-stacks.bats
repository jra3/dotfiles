#!/usr/bin/env bats
# Tests for gh-stacks. Run: bats tests/gh-stacks.bats
#
# Covers the pure functions only - no network. The fetch/group layer needs live
# GraphQL and is exercised by running the tool.

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # Source gh-prs from the repo, not ~/.local/bin, so tests do not depend on
  # the package being stowed.
  export GH_PRS="$REPO_ROOT/gh/.local/bin/gh-prs"
  # Point at a path that cannot exist, so sourcing never reads the real
  # allowlist and tests are identical on every machine.
  export GH_STACKS_CONFIG="$BATS_TEST_TMPDIR/repos-absent"

  # shellcheck disable=SC1090
  source "$REPO_ROOT/gh/.local/bin/gh-stacks"
}

# --- _threads_cell ---------------------------------------------------------
# Fixed 7 display columns so the diff and title columns cannot drift.

@test "threads_cell: zero counts render blank, not 0" {
  run _threads_cell 0 0
  assert_success
  assert_output '       '
}

@test "threads_cell: both counts present" {
  run _threads_cell 3 2
  assert_success
  assert_output '🤖3 🍖2'
}

@test "threads_cell: bot only leaves the human slot blank" {
  run _threads_cell 1 0
  assert_success
  assert_output '🤖1    '
}

@test "threads_cell: human only leaves the bot slot blank" {
  run _threads_cell 0 1
  assert_success
  assert_output '    🍖1'
}

@test "threads_cell: counts above 9 clamp to ! so the column cannot widen" {
  run _threads_cell 12 0
  assert_output '🤖!    '
  run _threads_cell 0 16
  assert_output '    🍖!'
  run _threads_cell 10 10
  assert_output '🤖! 🍖!'
}

@test "threads_cell: every variant is exactly 7 display columns" {
  # Emoji are one character but two columns; a naive ${#s} would pass here
  # while the rendered rows drifted, so measure with _visible_width.
  for pair in "0 0" "3 2" "1 0" "0 1" "12 0" "0 16" "9 9" "10 10"; do
    # shellcheck disable=SC2086
    local cell; cell=$(_threads_cell $pair)
    local w; w=$(_visible_width "$cell")
    [[ "$w" == "7" ]] || {
      echo "pair='$pair' cell='$cell' width=$w want 7"; return 1
    }
  done
}

# --- _visible_width --------------------------------------------------------

@test "visible_width: emoji count as two columns" {
  run _visible_width '🤖3'
  assert_output '3'      # one 2-column emoji + one 1-column digit
}

@test "visible_width: geometric CI glyphs stay single-width" {
  # ● ◐ ✗ are outside the emoji range on purpose - counting them as 2 would
  # over-pad every CI row.
  run _visible_width '●#4'
  assert_output '3'
  run _visible_width '◐✗'
  assert_output '2'
}

@test "visible_width: ANSI and OSC8 sequences are not counted" {
  run _visible_width $'\e[32m●\e[0m'
  assert_output '1'
}

# --- _diff_cell ------------------------------------------------------------

@test "diff_cell: fixed 11 columns for up to 4-digit sides" {
  for pair in "3 0" "294 118" "1601 108" "636 2903" "9999 9999"; do
    # shellcheck disable=SC2086
    local cell; cell=$(_diff_cell $pair)
    local w; w=$(_visible_width "$cell")
    [[ "$w" == "11" ]] || { echo "pair='$pair' width=$w want 11"; return 1; }
  done
}

@test "diff_cell: 5-digit sides widen the row rather than truncate the count" {
  # Inherited from gh-prs, and deliberate: a diff is real information, so an
  # oversized one pushes the title right instead of being clipped to a lie.
  # Unlike the 🤖/🍖 counts, which clamp to ! precisely because their exact
  # magnitude matters less than the column staying put.
  local w; w=$(_visible_width "$(_diff_cell 12345 67890)")
  [[ "$w" == "13" ]] || { echo "width=$w want 13"; return 1; }
}

@test "diff_cell: keeps the slash in a stable column" {
  local a b apre bpre
  a=$(_diff_cell 294 118 | sed -E $'s/\e\\[[0-9;]*m//g')
  b=$(_diff_cell 3 0     | sed -E $'s/\e\\[[0-9;]*m//g')
  [[ "$a" == *"+294"* ]]
  apre=${a%%/*}; bpre=${b%%/*}
  # '/' lands at the same index in both, which is what aligns the rows.
  [[ "${#apre}" == "${#bpre}" ]]
}

# --- allowlist config ------------------------------------------------------

@test "load_repos: missing config yields an empty allowlist" {
  GH_STACKS_CONFIG="$BATS_TEST_TMPDIR/nope" _load_repos
  [[ "${#REPOS[@]}" == "0" ]]
}

@test "load_repos: comments, blank lines and whitespace are ignored" {
  cat > "$BATS_TEST_TMPDIR/repos" <<'EOF'
# a comment
   owner/one

owner/two   # trailing comment
EOF
  GH_STACKS_CONFIG="$BATS_TEST_TMPDIR/repos" _load_repos
  [[ "${#REPOS[@]}" == "2" ]]
  [[ "${REPOS[0]}" == "owner/one" ]]
  [[ "${REPOS[1]}" == "owner/two" ]]
}

@test "load_repos: keeps a final line with no trailing newline" {
  printf 'owner/one\nowner/two' > "$BATS_TEST_TMPDIR/repos"
  GH_STACKS_CONFIG="$BATS_TEST_TMPDIR/repos" _load_repos
  [[ "${#REPOS[@]}" == "2" ]]
}

@test "repo_quals: empty allowlist produces no qualifiers (unfiltered view)" {
  REPOS=()
  run _repo_quals
  assert_output ''
}

@test "repo_quals: bare owner/name becomes a repo: qualifier" {
  REPOS=(owner/one owner/two)
  run _repo_quals
  assert_output ' repo:owner/one repo:owner/two'
}

@test "repo_quals: an entry containing a colon passes through verbatim" {
  REPOS=(org:acme owner/one)
  run _repo_quals
  assert_output ' org:acme repo:owner/one'
}

# --- _pr_cell --------------------------------------------------------------

@test "pr_cell: right-aligns so PR numbers of differing width end level" {
  local wide narrow
  wide=$(_pr_cell 4549 pending https://example/1)
  narrow=$(_pr_cell 1 pending https://example/1)
  [[ "$(_visible_width "$wide")" == "$(_visible_width "$narrow")" ]]
}

@test "pr_cell: draft state renders dim" {
  run _pr_cell 4703 draft https://example/1
  assert_output --partial $'\e[90m#4703'
}
