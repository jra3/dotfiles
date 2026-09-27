#!/usr/bin/env zsh
#
# Login-shell startup. zsh reads, in order:
#   /etc/zshenv -> ~/.zshenv -> /etc/zprofile -> ~/.zprofile -> /etc/zshrc -> ~/.zshrc
#
# On macOS that middle step is the problem. /etc/zprofile runs
# `eval $(/usr/libexec/path_helper -s)`, which REBUILDS PATH from /etc/paths and
# /etc/paths.d — and it does so by putting the system directories first, then
# appending whatever PATH already contained. So the `brew shellenv` we ran back
# in .zshenv gets demoted: /opt/homebrew/bin lands *behind* /usr/bin, and every
# formula that shadows a system binary (git, python, curl, make, ...) silently
# loses to the ancient Apple copy.
#
# Re-running shellenv here restores Homebrew's precedence, because ~/.zprofile
# is read after /etc/zprofile. It stays in .zshenv as well: .zprofile only runs
# for LOGIN shells, and scripts, git hooks, editors and Claude Code's Bash tool
# are frequently neither login nor interactive — those need .zshenv to have put
# Homebrew on PATH at all.
#
# Ordering note: version-manager shims (pyenv, mise) are prepended later, in
# .zshrc, so they still land ahead of Homebrew and keep working.

if [[ "$OSTYPE" == darwin* ]]; then
    if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
fi

[[ -f ~/.zprofile.local ]] && source ~/.zprofile.local
