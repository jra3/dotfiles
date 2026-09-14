#!/usr/bin/env bats
# Tests for bambu-studio-launch. Run: bats tests/bambu-studio-launch.bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck disable=SC1090
  source "$REPO_ROOT/bambu-studio/.local/bin/bambu-studio-launch"
}

# _gdk_scales: monitor scale -> "GDK_SCALE GDK_DPI_SCALE". GDK_SCALE is the
# nearest whole number (it sizes the layout and GTK ignores fractions);
# GDK_DPI_SCALE brings fonts back down to the real scale and never exceeds 1,
# because fonts larger than the layout planned for truncate labels.
@test "gdk_scales: 1.0 is plain 1x" {
  run _gdk_scales 1
  assert_output "1 1"
}

@test "gdk_scales: 1.25 (cupcake) rounds down; fonts stay at layout size, not 1.25" {
  run _gdk_scales 1.25
  assert_output "1 1"
}

@test "gdk_scales: 1.5 rounds up; fonts shrink to 0.75" {
  run _gdk_scales 1.5
  assert_output "2 0.75"
}

@test "gdk_scales: 1.6 (LG SDQHD) is 2x with fonts at 0.8" {
  run _gdk_scales 1.6
  assert_output "2 0.8"
}

@test "gdk_scales: 2.0 is plain 2x" {
  run _gdk_scales 2
  assert_output "2 1"
}

@test "gdk_scales: empty or non-numeric input falls back to 1x" {
  run _gdk_scales ""
  assert_output "1 1"
  run _gdk_scales bogus
  assert_output "1 1"
}

# _monitor_scale reads hyprctl; stub it with a shell function.
@test "monitor_scale: prefers the focused monitor" {
  hyprctl() { echo '[{"focused":false,"scale":1},{"focused":true,"scale":1.6}]'; }
  run _monitor_scale
  assert_output "1.6"
}

@test "monitor_scale: first monitor when none is focused" {
  hyprctl() { echo '[{"focused":false,"scale":1.25}]'; }
  run _monitor_scale
  assert_output "1.25"
}

@test "monitor_scale: 1 when hyprctl is unavailable" {
  hyprctl() { return 127; }
  run _monitor_scale
  assert_output "1"
}

@test "--print reports the env without launching" {
  hyprctl() { echo '[{"focused":true,"scale":1.6}]'; }
  run main --print
  assert_success
  assert_output "GDK_SCALE=2 GDK_DPI_SCALE=0.8"
}
