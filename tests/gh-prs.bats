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
