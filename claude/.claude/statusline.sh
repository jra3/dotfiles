#!/bin/bash
# Custom Claude Code statusline
# Components: dir (relative to git root), branch, worktree, linear, pr

# Read JSON input from stdin (contains workspace info from Claude Code)
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.workspace.current_dir // empty')

# Exit early if no directory
[[ -z "$CWD" ]] && exit 0

# Colors (using $'...' ANSI-C quoting for escape sequences)
ESC=$'\e'
ORANGE="${ESC}[38;5;214m"
GREEN="${ESC}[32m"
CYAN="${ESC}[36m"
YELLOW="${ESC}[33m"
RED="${ESC}[31m"
RESET="${ESC}[0m"

# Initialize components
DIR_COMPONENT=""
BRANCH_COMPONENT=""
WORKTREE_COMPONENT=""
LINEAR_COMPONENT=""
PR_COMPONENT=""

# Check if we're in a git repo
if git -C "$CWD" rev-parse --git-dir &>/dev/null; then
  GIT_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)
  GIT_DIR=$(git -C "$CWD" rev-parse --git-dir 2>/dev/null)
  GIT_COMMON_DIR=$(git -C "$CWD" rev-parse --git-common-dir 2>/dev/null)

  # === DIRECTORY (relative to git root) ===
  REL_PATH=$(realpath --relative-to="$GIT_ROOT" "$CWD" 2>/dev/null)
  [[ -z "$REL_PATH" || "$REL_PATH" == "." ]] && REL_PATH="."

  # Directory hyperlink
  DIR_COMPONENT="${ESC}]8;;edit://${CWD}${ESC}\\${ORANGE}${REL_PATH}${RESET}${ESC}]8;;${ESC}\\"

  # === GIT BRANCH with status ===
  BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null)
  if [[ -n "$BRANCH" ]]; then
    # Check dirty status
    DIRTY=""
    if ! git -C "$CWD" diff --quiet 2>/dev/null || ! git -C "$CWD" diff --cached --quiet 2>/dev/null; then
      DIRTY="${YELLOW}*${RESET}"
    fi

    # Check ahead/behind upstream
    UPSTREAM=$(git -C "$CWD" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)
    AHEAD_BEHIND=""
    if [[ -n "$UPSTREAM" ]]; then
      AHEAD=$(git -C "$CWD" rev-list --count '@{upstream}..HEAD' 2>/dev/null)
      BEHIND=$(git -C "$CWD" rev-list --count 'HEAD..@{upstream}' 2>/dev/null)
      [[ "$BEHIND" -gt 0 ]] && AHEAD_BEHIND="${RED}↓${BEHIND}${RESET}"
      [[ "$AHEAD" -gt 0 ]] && AHEAD_BEHIND="${AHEAD_BEHIND}${GREEN}↑${AHEAD}${RESET}"
    fi

    BRANCH_COMPONENT=" ${BRANCH}${DIRTY}${AHEAD_BEHIND}"
  fi

  # === WORKTREE indicator ===
  if [[ "$GIT_DIR" != "$GIT_COMMON_DIR" && -n "$GIT_COMMON_DIR" ]]; then
    WORKTREE_COMPONENT=" ⊛"
  fi

  # === LINEAR issue link (no leading space - goes at start) ===
  if [[ -n "$BRANCH" && "$BRANCH" =~ [eE][nN][gG]-([0-9]+) ]]; then
    ISSUE_NUMBER="${BASH_REMATCH[1]}"
    ISSUE_ID="ENG-${ISSUE_NUMBER}"
    LINEAR_URL="https://linear.app/antimetal/issue/${ISSUE_ID}"
    LINEAR_COMPONENT="${ESC}]8;;${LINEAR_URL}${ESC}\\${GREEN}${ISSUE_ID}${RESET}${ESC}]8;;${ESC}\\"
  fi

  # === PR link ===
  PR_URL=$(gh pr view "$BRANCH" --json url -q .url 2>/dev/null)
  if [[ -n "$PR_URL" ]]; then
    PR_NUMBER=$(echo "$PR_URL" | grep -oP '/pull/\K[0-9]+')
    [[ -n "$PR_NUMBER" ]] && PR_COMPONENT=" ${ESC}]8;;${PR_URL}${ESC}\\${CYAN}#${PR_NUMBER}${RESET}${ESC}]8;;${ESC}\\"
  fi
else
  # Not in a git repo - just show directory basename
  DIR_NAME=$(basename "$CWD")
  DIR_COMPONENT="${ESC}]8;;edit://${CWD}${ESC}\\${ORANGE}${DIR_NAME}${RESET}${ESC}]8;;${ESC}\\"
fi

# Output on two lines:
# Line 1: dir/branch/worktree (plain info)
# Line 2: hyperlinks (Linear, PR) - isolated from notifications
LINKS="${LINEAR_COMPONENT}${PR_COMPONENT}"
REST="${DIR_COMPONENT}${BRANCH_COMPONENT}${WORKTREE_COMPONENT}"

# Try multiline output
if [[ -n "$LINKS" ]]; then
  printf '%s\n%s\n' "${REST}" "${LINKS}"
else
  echo "${REST}"
fi
