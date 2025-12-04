# macOS specific configuration

export BROWSER='open'

# Homebrew completions
if [[ -d /opt/homebrew/share/zsh/site-functions ]]; then
    fpath=(/opt/homebrew/share/zsh/site-functions $fpath)
fi

# Editor
export EDITOR='/opt/homebrew/bin/emacs -nw'
export VISUAL='/opt/homebrew/bin/emacs -nw'
e() { /opt/homebrew/bin/emacs -nw "$@"; }

# fzf
if command -v fzf &>/dev/null; then
    source "/opt/homebrew/opt/fzf/shell/completion.zsh" 2>/dev/null
    source "/opt/homebrew/opt/fzf/shell/key-bindings.zsh" 2>/dev/null

    export FZF_CTRL_R_OPTS="
        --preview 'echo {}'
        --preview-window=down:3:wrap
        --bind='ctrl-y:execute-silent(echo -n {2..} | pbcopy)+abort'
        --header='Press CTRL-Y to copy command to clipboard'
    "
fi

# SSH agent (1Password or macOS keychain)
export SSH_AUTH_SOCK=~/Library/Group\ Containers/2BUA8C4S2C.com.1password/t/agent.sock
if [[ ! -S "$SSH_AUTH_SOCK" ]]; then
    export SSH_AUTH_SOCK=$(launchctl getenv SSH_AUTH_SOCK 2>/dev/null)
fi

# Unix timestamp (BSD date)
ut() {
    if [ $# -eq 0 ]; then
        date +%s
    else
        date -u -r "$1" -Iseconds
    fi
}

# PATH additions
path=(/opt/homebrew/opt/postgresql@16/bin $path)

# Aliases
alias claude="$HOME/.claude/local/claude"
