# macOS specific configuration

export BROWSER='open'

# HOMEBREW_PREFIX is exported by `brew shellenv` in .zshenv. The fallback only
# matters if Homebrew isn't installed at all, in which case every guard below
# simply fails closed. Hardcoding /opt/homebrew would break on Intel Macs.
: "${HOMEBREW_PREFIX:=/opt/homebrew}"

# Homebrew completions
if [[ -d "$HOMEBREW_PREFIX/share/zsh/site-functions" ]]; then
    fpath=("$HOMEBREW_PREFIX/share/zsh/site-functions" $fpath)
fi

# Editor. Arch runs an Emacs daemon via systemd and talks to it with
# emacsclient; there's no such unit here, so call the binary directly.
if [[ -x "$HOMEBREW_PREFIX/bin/emacs" ]]; then
    export EDITOR="$HOMEBREW_PREFIX/bin/emacs -nw"
    export VISUAL="$EDITOR"
    e() { "$HOMEBREW_PREFIX/bin/emacs" -nw "$@"; }
fi

# fzf
if command -v fzf &>/dev/null; then
    source "$HOMEBREW_PREFIX/opt/fzf/shell/completion.zsh" 2>/dev/null
    source "$HOMEBREW_PREFIX/opt/fzf/shell/key-bindings.zsh" 2>/dev/null

    export FZF_CTRL_R_OPTS="
        --preview 'echo {}'
        --preview-window=down:3:wrap
        --bind='ctrl-y:execute-silent(echo -n {2..} | pbcopy)+abort'
        --header='Press CTRL-Y to copy command to clipboard'
    "
fi

# SSH agent: use macOS's own launchd agent.
# This used to hardcode SSH_AUTH_SOCK to 1Password's socket first, which was
# doubly wrong once 1Password went away: it clobbered the perfectly good launchd
# socket macOS already puts in the environment, and if `launchctl getenv` then
# returned nothing you were left with SSH_AUTH_SOCK="" — no agent at all, which
# breaks the ForwardAgent brokering in ssh/.ssh/config.shared. Only ever assign
# a socket that actually exists.
() {
    [[ -S "$SSH_AUTH_SOCK" ]] && return

    local from_launchd="$(launchctl getenv SSH_AUTH_SOCK 2>/dev/null)"
    [[ -S "$from_launchd" ]] && export SSH_AUTH_SOCK="$from_launchd"
}

# Unix timestamp (BSD date)
ut() {
    if [ $# -eq 0 ]; then
        date +%s
    else
        date -u -r "$1" -Iseconds
    fi
}

# PATH additions. Keg-only formulae aren't linked into the Homebrew bin dir, so
# they need an explicit entry — but only if actually installed, otherwise this
# leaves a dead path element in every shell.
[[ -d "$HOMEBREW_PREFIX/opt/postgresql@16/bin" ]] && path=("$HOMEBREW_PREFIX/opt/postgresql@16/bin" $path)

