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
