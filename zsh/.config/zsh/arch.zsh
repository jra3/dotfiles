# Arch Linux specific configuration

# Omarchy defaults
[[ -f ~/.local/share/omarchy/default/bash/envs ]] && source ~/.local/share/omarchy/default/bash/envs
[[ -f ~/.local/share/omarchy/default/bash/aliases ]] && source ~/.local/share/omarchy/default/bash/aliases
[[ -f ~/.local/share/omarchy/default/bash/functions ]] && source ~/.local/share/omarchy/default/bash/functions

# Environment setup
[[ -f "$HOME/.local/bin/env" ]] && . "$HOME/.local/bin/env"

# Editor
export EDITOR="emacsclient -nw"
e() {
    emacsclient -n "$@"
    hyprctl dispatch focuswindow "class:^(emacs)$"
}

# fzf
if command -v fzf &>/dev/null; then
    source /usr/share/fzf/completion.zsh 2>/dev/null
    source /usr/share/fzf/key-bindings.zsh 2>/dev/null
    bindkey -r '^T'
    bindkey '^Xt' fzf-file-widget

    export FZF_CTRL_R_OPTS="
        --preview 'echo {}'
        --preview-window=down:3:wrap
        --bind='ctrl-y:execute-silent(echo -n {2..} | wl-copy)+abort'
        --header='Press CTRL-Y to copy command to clipboard'
    "
fi

# Telepresence: connect with VNAT so cluster CIDRs are NAT'd into the
# virtualSubnet (198.18.0.0/16) instead of claiming the Tailscale CGNAT
# range (100.64.0.0/10). Avoids the tel0/tailscale0 routing conflict.
alias tp='telepresence connect --vnat all'

# Unix timestamp (GNU date)
ut() {
    if [ $# -eq 0 ]; then
        date +%s
    else
        date -d "@$1" -Iseconds
    fi
}
