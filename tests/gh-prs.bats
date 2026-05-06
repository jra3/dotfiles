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

@test "extract_branch_name: branch with multiple trailing annotations" {
  run _extract_branch_name '◯    john/eng-4602-anvil-05c-external-dep-evaluators (needs restack) (eng-4602-fix)'
  assert_success
  assert_output 'john/eng-4602-anvil-05c-external-dep-evaluators'
}

@test "extract_branch_name: handles ANSI-colored gt-ls line" {
  # Simulates `FORCE_COLOR=1 gt ls` output: 24-bit color SGR escapes around glyph and branch name.
  local line=$'\e[38;2;76;203;241m◯\e[39m    \e[38;2;77;202;125mjohn/foo\e[39m'
  run _extract_branch_name "$line"
  assert_success
  assert_output 'john/foo'
}

@test "visible_width: plain text" {
  run _visible_width 'hello'
  assert_success
  assert_output '5'
}

@test "visible_width: ANSI CSI sequences are excluded" {
  run _visible_width $'\e[31mhello\e[0m'
  assert_success
  assert_output '5'
}

@test "visible_width: 24-bit color escapes are excluded" {
  run _visible_width $'\e[38;2;76;203;241m●\e[39m'
  assert_success
  assert_output '1'
}

@test "visible_width: OSC8 hyperlink wrapper is excluded" {
  run _visible_width $'\e]8;;https://example.com\e\\link\e]8;;\e\\'
  assert_success
  assert_output '4'
}

@test "visible_width: gt-ls-style colored line" {
  local line=$'\e[38;2;76;203;241m◯\e[39m    \e[38;2;77;202;125mjohn/foo\e[39m'
  # Visible: "◯    john/foo" = 1+4+8 = 13.
  run _visible_width "$line"
  assert_success
  assert_output '13'
}

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
  # Visible: " #42  -" = 1+1+3+2+1 = 8.
  local width="${output%%$'\t'*}"
  assert_equal "$width" "8"
}

@test "render_tree: joins PR data on matching branches and passes others through" {
  local gt_in='◯    foo
◯    main'
  local pr_in='foo	1234	approved	pass	0'

  # Visible "◯    foo" = 8, cell width = 10, term = 60, pad = 60-8-10 = 42.
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

@test "render_tree: pads correctly when gt-ls input contains ANSI colors" {
  # Simulates colored gt output. Visible width of left side: "◯    foo" = 8.
  local gt_in=$'\e[38;2;76;203;241m◯\e[39m    \e[38;2;77;202;125mfoo\e[39m'
  local pr_in='foo	1234	approved	pass	0'

  # Cell = 10, term = 60, pad = 60 - 8 - 10 = 42. Left side preserved verbatim.
  local expected_cell
  expected_cell=$'\e[32m●\e[0m \e]8;;https://g.example/1234\e\\\e[32m#1234\e[0m\e]8;;\e\\  \e[90m-\e[0m'
  local pad
  pad=$(printf '%*s' 42 '')
  local expected="${gt_in}${pad}${expected_cell}"

  run _render_tree "$gt_in" "$pr_in" 'https://g.example' 60
  assert_success
  assert_output "$expected"
}

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
