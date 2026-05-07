# Bitwarden picker via rbw + walker — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Electron `bitwarden-desktop` keybind with a native, keyboard-driven picker (`bw-pick`) backed by `rbw` and `walker` dmenu mode.

**Architecture:** A single bash script `bw-pick` lives in the existing `bitwarden/` stow package. It calls `rbw` for vault operations, drives `walker -d` twice (entry list, then field menu), and pushes the chosen value to the Wayland clipboard via `wl-copy --paste-once` with a 30-second background watchdog clear. The `rbw-agent` is socket-activated by `rbw` itself — no autostart needed. Pure helpers (label formatting, parsing, branching) are factored into `_`-prefixed functions and unit-tested with bats.

**Tech Stack:** bash, rbw 1.15+, walker 2.16+, pinentry-gnome3, wl-clipboard, libnotify (`notify-send`), bats / bats-assert / bats-support.

**Spec:** `docs/superpowers/specs/2026-05-07-bitwarden-rbw-walker-picker-design.md`

---

## File Structure

| Path | Status | Responsibility |
|------|--------|----------------|
| `pacman/packages-arch.txt` | modify | Add `rbw` and `pinentry-gnome3` (alphabetical) |
| `bitwarden/.local/bin/bw-pick` | create | The picker. Contains main flow + `_`-prefixed pure helpers. |
| `tests/bw-pick.bats` | create | Unit tests for the pure helpers (label format/parse, sync-pseudo detection, TOTP-empty branching). |
| `hypr/.config/hypr/bindings.conf` | modify | Replace line 27 (`bitwarden-desktop` → `bw-pick`). |

The user's existing `bitwarden/.local/bin/get-signature` is unchanged — it uses `bw` for attachments which `rbw` does not support.

No README is added; first-run setup is documented as a comment header inside `bw-pick` so it stays next to the code that depends on it.

---

## Task 1: Install rbw and pinentry-gnome3

**Files:**
- Modify: `pacman/packages-arch.txt`

- [ ] **Step 1: Add packages to packages-arch.txt (alphabetical)**

Edit `pacman/packages-arch.txt`. Insert `pinentry-gnome3` after `pandoc-cli` (line 28) and `rbw` after `pyenv` (line 30). Final ordering around the insertions:

```
pandoc-cli
pinentry-gnome3
pnpm
pyenv
rbw
steam
```

- [ ] **Step 2: Install the packages**

Run: `sudo pacman -S --needed rbw pinentry-gnome3`
Expected: both install cleanly; `rbw` from `extra`, `pinentry-gnome3` from `extra`.

- [ ] **Step 3: Verify binaries are on PATH**

Run: `which rbw pinentry-gnome3 walker wl-copy notify-send`
Expected: all five paths print, no "not found".

- [ ] **Step 4: Commit**

```bash
git add pacman/packages-arch.txt
git commit -m "Add rbw and pinentry-gnome3 packages"
```

---

## Task 2: One-time rbw vault setup

**Files:** none — this configures user state under `~/.config/rbw/` and `~/.local/share/rbw/`.

- [ ] **Step 1: Set rbw email and pinentry**

Run:
```bash
rbw config set email theactualjohnallen@gmail.com
rbw config set pinentry pinentry-gnome3
```
Expected: no output. Verify with `rbw config show`; should show those two fields plus default `base_url`.

- [ ] **Step 2: Log in (one-time master password)**

Run: `rbw login`
Expected: pinentry-gnome3 popup asks for master password. After typing it, command exits 0 with no output.

- [ ] **Step 3: Sync the vault**

Run: `rbw sync`
Expected: command takes a few seconds, exits 0 with no output.

- [ ] **Step 4: Verify the vault is readable**

Run: `rbw ls | head`
Expected: at least one line of `name<TAB>username<TAB>folder` (rbw's default ls format). If empty, the vault really is empty — investigate before continuing.

- [ ] **Step 5: No commit**

This task changes user state, not repo state.

---

## Task 3: Write the bw-pick script with pure helpers (TDD)

**Files:**
- Create: `tests/bw-pick.bats`
- Create: `bitwarden/.local/bin/bw-pick`

This task implements the pure helpers and their tests. The orchestration `main()` is added in Task 4.

- [ ] **Step 1: Write the failing tests**

Create `tests/bw-pick.bats`:

```bash
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

# _format_entry_label: convert "name<TAB>username<TAB>folder" → display label
@test "format_entry_label: name and username" {
  run _format_entry_label "Gmail	john@example.com	Personal"
  assert_success
  assert_output 'Gmail (john@example.com)'
}

@test "format_entry_label: name only when username empty" {
  run _format_entry_label "Wifi-Home		Personal"
  assert_success
  assert_output 'Wifi-Home'
}

@test "format_entry_label: name only when no username column" {
  run _format_entry_label "API Token"
  assert_success
  assert_output 'API Token'
}

# _parse_entry_label: pull the entry name (and optional username) back out of a display label
@test "parse_entry_label: name and username" {
  run _parse_entry_label 'Gmail (john@example.com)'
  assert_success
  assert_output 'Gmail	john@example.com'
}

@test "parse_entry_label: name only" {
  run _parse_entry_label 'Wifi-Home'
  assert_success
  assert_output 'Wifi-Home	'
}

@test "parse_entry_label: name with parens that are not a username (no @)" {
  run _parse_entry_label 'Bank Account (savings)'
  assert_success
  assert_output 'Bank Account (savings)	'
}

# _is_sync_action: true for the synthetic "↻ Sync vault" line, false otherwise
@test "is_sync_action: matches sync line" {
  run _is_sync_action '↻ Sync vault'
  assert_success
}

@test "is_sync_action: does not match a real entry" {
  run _is_sync_action 'Gmail (john@example.com)'
  assert_failure
}

# _is_blank: empty / whitespace-only field treated as missing
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

# _totp_seconds_remaining: how many seconds until the next 30s rotation boundary
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

@test "totp_seconds_remaining: 30s past boundary wraps" {
  run _totp_seconds_remaining 30
  assert_success
  assert_output '30'
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/bw-pick.bats`
Expected: every test fails with `bw-pick: No such file or directory` (the script doesn't exist yet).

- [ ] **Step 3: Create bw-pick with the pure helpers**

Create `bitwarden/.local/bin/bw-pick`:

```bash
#!/usr/bin/env bash
# bw-pick — keyboard-driven Bitwarden picker for Hyprland.
#
# First-run setup (one-time, per machine):
#   rbw config set email YOUR@EMAIL
#   rbw config set pinentry pinentry-gnome3
#   rbw login
#   rbw sync
#
# Triggered from Hyprland: bindd = SUPER SHIFT, SLASH, Passwords, exec, uwsm-app -- bw-pick
#
# Flow: rbw ls → walker (entry) → walker (field) → wl-copy --paste-once + 30s clear watchdog.

set -euo pipefail

# ---- pure helpers (unit-tested in tests/bw-pick.bats) ----

# Convert a single tab-separated `rbw ls` row into a human display label.
# Input: "name<TAB>username<TAB>folder" (any column may be empty/missing)
# Output: "name (username)" if username present, else "name".
_format_entry_label() {
  local row="$1" name username
  name="$(printf '%s' "$row" | cut -f1)"
  username="$(printf '%s' "$row" | cut -f2)"
  if [[ -n "$username" ]]; then
    printf '%s (%s)\n' "$name" "$username"
  else
    printf '%s\n' "$name"
  fi
}

# Reverse _format_entry_label. Returns "name<TAB>username" — username empty if none.
# A trailing "(...)" group is only treated as a username if it contains '@'
# (so "Bank Account (savings)" stays whole).
_parse_entry_label() {
  local label="$1"
  if [[ "$label" =~ ^(.+)\ \(([^()]*@[^()]*)\)$ ]]; then
    printf '%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  else
    printf '%s\t\n' "$label"
  fi
}

# True if the line is the synthetic sync pseudo-entry.
_is_sync_action() {
  [[ "$1" == "↻ Sync vault" ]]
}

# True if the string is empty or only whitespace.
_is_blank() {
  [[ -z "${1// /}" ]]
}

# Seconds until the next TOTP 30s rotation boundary, given the current epoch second offset.
# Used to tell the user how long the just-copied code is still valid.
_totp_seconds_remaining() {
  local now="$1"
  printf '%d\n' $(( 30 - (now % 30) ))
}

# ---- main flow added in Task 4 ----

# Stub so the script is sourceable for tests without running anything.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "bw-pick: main() not yet implemented (Task 4)" >&2
  exit 1
fi
```

- [ ] **Step 4: Make the script executable**

Run: `chmod +x bitwarden/.local/bin/bw-pick`

- [ ] **Step 5: Run tests to verify they pass**

Run: `bats tests/bw-pick.bats`
Expected: all 14 tests pass.

- [ ] **Step 6: Commit**

```bash
git add bitwarden/.local/bin/bw-pick tests/bw-pick.bats
git commit -m "Add bw-pick helpers and tests"
```

---

## Task 4: Implement the main flow

**Files:**
- Modify: `bitwarden/.local/bin/bw-pick`

This task replaces the stub at the bottom of the script with the orchestration. It is integration-tested manually (the dependencies — `rbw`, `walker`, `wl-copy`, pinentry — are interactive system services that can't be unit-tested usefully).

- [ ] **Step 1: Stow the bitwarden package so `bw-pick` is on PATH**

Run: `cd /home/john/.dotfiles && stow -R bitwarden`
Expected: no errors. Verify with `which bw-pick` → should print `/home/john/.local/bin/bw-pick`.

- [ ] **Step 2: Replace the stub at the bottom of bw-pick with the main flow**

Replace the lines from `# ---- main flow added in Task 4 ----` to end-of-file with:

```bash
# ---- main flow ----

# Notify if libnotify is present, silent otherwise.
_notify() {
  command -v notify-send >/dev/null 2>&1 && notify-send "$@" || true
}

# Hard-fail with a desktop notification if rbw is unconfigured.
_check_rbw_configured() {
  if ! rbw config show 2>/dev/null | grep -q '"email"'; then
    _notify "Bitwarden" "rbw not configured. Run: rbw config set email YOUR@EMAIL && rbw login"
    exit 1
  fi
}

# Build the entry-picker list: one label per `rbw ls` row, plus the sync pseudo-entry.
_build_entry_list() {
  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    _format_entry_label "$row"
  done < <(rbw ls --fields name,user,folder)
  printf '%s\n' '↻ Sync vault'
}

# Pop walker in dmenu mode and return the picked line on stdout.
# Exits non-zero if the user cancels.
_pick() {
  local prompt="$1"
  walker -d -p "$prompt"
}

# Copy a value to the Wayland clipboard with paste-once semantics, plus a 30s
# background watchdog clear in case the user never pastes.
_copy_with_clear() {
  local value="$1"
  printf '%s' "$value" | wl-copy --paste-once
  ( sleep 30 && wl-copy --clear ) >/dev/null 2>&1 &
  disown
}

# Decrypt and copy a single field of the given entry. Username is optional
# disambiguator (empty string = let rbw pick).
_handle_field() {
  local field="$1" name="$2" username="$3"
  local value
  case "$field" in
    Password)
      if [[ -n "$username" ]]; then
        value="$(rbw get "$name" "$username")"
      else
        value="$(rbw get "$name")"
      fi
      _copy_with_clear "$value"
      _notify "Bitwarden" "Password copied (clears in 30s)"
      ;;
    Username)
      if _is_blank "$username"; then
        _notify "Bitwarden" "No username for this entry"
        exit 0
      fi
      _copy_with_clear "$username"
      _notify "Bitwarden" "Username copied"
      ;;
    TOTP)
      if [[ -n "$username" ]]; then
        value="$(rbw code "$name" "$username" 2>/dev/null || true)"
      else
        value="$(rbw code "$name" 2>/dev/null || true)"
      fi
      if _is_blank "$value"; then
        _notify "Bitwarden" "No TOTP for this entry"
        exit 0
      fi
      _copy_with_clear "$value"
      local secs
      secs="$(_totp_seconds_remaining "$(date +%s)")"
      _notify "Bitwarden" "TOTP copied (valid ${secs}s)"
      ;;
    URL|Notes)
      local jq_path
      [[ "$field" == URL ]] && jq_path='.uris[0].uri // ""' || jq_path='.notes // ""'
      if [[ -n "$username" ]]; then
        value="$(rbw get --full "$name" "$username" | jq -r "$jq_path")"
      else
        value="$(rbw get --full "$name" | jq -r "$jq_path")"
      fi
      if _is_blank "$value"; then
        _notify "Bitwarden" "No $field for this entry"
        exit 0
      fi
      _copy_with_clear "$value"
      _notify "Bitwarden" "$field copied"
      ;;
  esac
}

main() {
  _check_rbw_configured

  local entry
  entry="$(_build_entry_list | _pick "Bitwarden")" || exit 0  # user cancelled
  [[ -z "$entry" ]] && exit 0

  if _is_sync_action "$entry"; then
    rbw sync
    _notify "Bitwarden" "Vault synced"
    exit 0
  fi

  local parsed name username
  parsed="$(_parse_entry_label "$entry")"
  name="$(printf '%s' "$parsed" | cut -f1)"
  username="$(printf '%s' "$parsed" | cut -f2)"

  local field
  field="$(printf '%s\n' Password Username TOTP URL Notes | _pick "$entry")" || exit 0
  [[ -z "$field" ]] && exit 0

  _handle_field "$field" "$name" "$username"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
```

- [ ] **Step 3: Re-run unit tests to ensure helpers still pass**

Run: `bats tests/bw-pick.bats`
Expected: all 14 tests still pass (helpers untouched).

- [ ] **Step 4: Manual smoke test — happy path**

Run: `bw-pick` from a terminal.
Expected:
1. Walker pops with vault entries (each shown as `name (username)` or just `name`), plus `↻ Sync vault` at the bottom.
2. Pick a known entry → second walker pops with `Password / Username / TOTP / URL / Notes`.
3. Pick `Password` → notification "Password copied (clears in 30s)", and `wl-paste` returns the password.
4. Wait 35 seconds, run `wl-paste` again → should be empty (or error "no clipboard data").

- [ ] **Step 5: Manual test — sync pseudo-entry**

Run: `bw-pick`, pick `↻ Sync vault`.
Expected: notification "Vault synced", no field menu shown.

- [ ] **Step 6: Manual test — cancellation**

Run: `bw-pick`, then press Escape at the entry picker.
Expected: script exits silently, exit code 0, clipboard untouched.

- [ ] **Step 7: Manual test — entry without TOTP**

Run: `bw-pick`, pick an entry you know has no TOTP, pick `TOTP`.
Expected: notification "No TOTP for this entry", clipboard untouched.

- [ ] **Step 8: Commit**

```bash
git add bitwarden/.local/bin/bw-pick
git commit -m "Implement bw-pick main flow"
```

---

## Task 5: Replace the Hyprland keybind

**Files:**
- Modify: `hypr/.config/hypr/bindings.conf` (line 27)

- [ ] **Step 1: Update the keybind**

In `hypr/.config/hypr/bindings.conf`, line 27 currently reads:
```
bindd = SUPER SHIFT, SLASH, Passwords, exec, uwsm-app -- bitwarden-desktop
```
Change it to:
```
bindd = SUPER SHIFT, SLASH, Passwords, exec, uwsm-app -- bw-pick
```

- [ ] **Step 2: Reload Hyprland**

Run: `hyprctl reload`
Expected: no output, exit code 0.

- [ ] **Step 3: Verify the binding is registered**

Run: `hyprctl binds | grep -A2 SLASH`
Expected: shows `bw-pick` in the dispatcher line, not `bitwarden-desktop`.

- [ ] **Step 4: Manual end-to-end test from keybind**

Press `Super+Shift+/`.
Expected: walker pops with the entry list (same UX as Task 4 step 4, but launched from keybind instead of terminal). Pick an entry + field, paste it somewhere, confirm it works.

- [ ] **Step 5: Commit**

```bash
git add hypr/.config/hypr/bindings.conf
git commit -m "Replace bitwarden-desktop keybind with bw-pick"
```

---

## Self-review notes (verified before committing this plan)

- **Spec coverage:**
  - Architecture diagram → Task 4 (main flow with rbw + walker + wl-copy)
  - First-run setup doc → Task 2 + comment header in `bw-pick` (Task 3 step 3)
  - Edge cases (vault not configured, cancel, no TOTP, sync pseudo-entry, paste-once + watchdog clear) → Tasks 3 + 4 with explicit manual tests
  - Disambiguation `name (username)` → covered in `_format_entry_label` / `_parse_entry_label` tests
  - TOTP rotation seconds → covered in `_totp_seconds_remaining` tests + Task 4 `_handle_field` TOTP branch
  - Keybind replacement → Task 5
  - Package additions → Task 1
- **Open questions from spec, resolved here:**
  - Email in config.json → omitted; `rbw config set email` documented in Task 2 and in the script's comment header. No email gets committed to the repo.
  - rbw package source → confirmed `extra` (not AUR), so `packages-arch.txt`.
  - Notification mechanism → `notify-send` (libnotify) wrapped in `_notify` helper that no-ops when unavailable.
- **No placeholders:** every step has its actual code or command.
- **Type/name consistency:** `_format_entry_label` / `_parse_entry_label` / `_is_sync_action` / `_is_blank` / `_totp_seconds_remaining` / `_check_rbw_configured` / `_build_entry_list` / `_pick` / `_copy_with_clear` / `_handle_field` / `_notify` / `main` — names match between definition, tests, and call sites.
