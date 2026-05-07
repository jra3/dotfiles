#!/usr/bin/env bats
# Tests for bw-pick. Run: bats tests/bw-pick.bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  BWPICK_BIN="$REPO_ROOT/bitwarden/.local/bin/bw-pick"
  # shellcheck disable=SC1090
  source "$BWPICK_BIN"
}

# _disambiguate_labels: stdin = "name<TAB>user" rows; stdout = display labels.
# Names that occur once are emitted as-is. Names that collide get a "(user)"
# suffix when a user is present (so duplicates remain visually distinct).
@test "disambiguate_labels: unique names emit as-is" {
  run _disambiguate_labels <<EOF
Gmail	john@example.com
Wifi-Home
Bank	checking
EOF
  assert_success
  assert_output "$(printf 'Gmail\nWifi-Home\nBank')"
}

@test "disambiguate_labels: duplicate names get user suffix" {
  run _disambiguate_labels <<EOF
Server	root
Server	john
Gmail	john@example.com
EOF
  assert_success
  assert_output "$(printf 'Server (root)\nServer (john)\nGmail')"
}

@test "disambiguate_labels: duplicate names without users keep raw name" {
  run _disambiguate_labels <<EOF
Untitled
Untitled
EOF
  assert_success
  assert_output "$(printf 'Untitled\nUntitled')"
}

@test "disambiguate_labels: preserves input order" {
  run _disambiguate_labels <<EOF
B	x
A	y
B	z
EOF
  assert_success
  assert_output "$(printf 'B (x)\nA\nB (z)')"
}

# _is_blank: empty / whitespace-only treated as missing.
@test "is_blank: empty string" {
  run _is_blank ''
  assert_success
}

@test "is_blank: whitespace only" {
  run _is_blank '   '
  assert_success
}

@test "is_blank: real value" {
  run _is_blank 'hunter2'
  assert_failure
}

# _totp_seconds_remaining: how many seconds until next 30s rotation boundary.
@test "totp_seconds_remaining: at boundary" {
  run _totp_seconds_remaining 0
  assert_success
  assert_output '30'
}

@test "totp_seconds_remaining: 1s past boundary" {
  run _totp_seconds_remaining 1
  assert_success
  assert_output '29'
}

@test "totp_seconds_remaining: 29s past boundary" {
  run _totp_seconds_remaining 29
  assert_success
  assert_output '1'
}

@test "totp_seconds_remaining: wraps at 30" {
  run _totp_seconds_remaining 30
  assert_success
  assert_output '30'
}
