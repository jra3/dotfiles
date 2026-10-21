#!/usr/bin/env bats
# Tests for bambu-studio-launch. Run: bats tests/bambu-studio-launch.bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck disable=SC1090
  source "$REPO_ROOT/bambu-studio/.local/bin/bambu-studio-launch"
}

# _gdk_scales: monitor scale [+ size] -> "GDK_SCALE GDK_DPI_SCALE". GDK_SCALE is
# the scale rounded down (it sizes the layout, GTK ignores fractions, and rounding
# 1.6 up to 2 made Bambu too big on a laptop), except on a monitor big enough
# that 2x still leaves a short side of 1080+; GDK_DPI_SCALE never exceeds 1, because fonts
# larger than the layout planned for truncate labels.
@test "gdk_scales: 1.0 is plain 1x" {
  run _gdk_scales 1
  assert_output "1 1"
}

@test "gdk_scales: 1.25 (cupcake) rounds down; fonts stay at layout size, not 1.25" {
  run _gdk_scales 1.25
  assert_output "1 1"
}

@test "gdk_scales: 1.5 rounds down to 1x" {
  run _gdk_scales 1.5
  assert_output "1 1"
}

@test "gdk_scales: 1.6 rounds down to 1x, not up to 2x" {
  run _gdk_scales 1.6
  assert_output "1 1"
}

@test "gdk_scales: 2.5 rounds down to 2x" {
  run _gdk_scales 2.5
  assert_output "2 1"
}

@test "gdk_scales: 2.0 is plain 2x" {
  run _gdk_scales 2
  assert_output "2 1"
}

@test "gdk_scales: 1.6 on a big monitor (DualUp 2560x2880) rounds up to 2x, fonts at 0.8" {
  run _gdk_scales 1.6 2560 2880
  assert_output "2 0.8"
}

@test "gdk_scales: 1.6 on a laptop panel (2880x1920) still rounds down" {
  run _gdk_scales 1.6 2880 1920
  assert_output "1 1"
}

@test "gdk_scales: integer scale never rounds up, however big the monitor" {
  run _gdk_scales 2 7680 4320
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

@test "monitor: reports scale and physical size" {
  hyprctl() { echo '[{"focused":true,"scale":1.6,"width":2560,"height":2880}]'; }
  run _monitor
  assert_output "1.6 2560 2880"
}

@test "--print reports the env without launching" {
  hyprctl() { echo '[{"focused":true,"scale":1.6,"width":2880,"height":1920}]'; }
  run main --print
  assert_success
  assert_output "GDK_SCALE=1 GDK_DPI_SCALE=1"
}

@test "--print rounds up on a big monitor" {
  hyprctl() { echo '[{"focused":true,"scale":1.6,"width":2560,"height":2880}]'; }
  run main --print
  assert_success
  assert_output "GDK_SCALE=2 GDK_DPI_SCALE=0.8"
}
