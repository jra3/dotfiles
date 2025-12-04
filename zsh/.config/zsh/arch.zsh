# Arch Linux specific configuration

# Omarchy defaults
[[ -f ~/.local/share/omarchy/default/bash/aliases ]] && source ~/.local/share/omarchy/default/bash/aliases
[[ -f ~/.local/share/omarchy/default/bash/functions ]] && source ~/.local/share/omarchy/default/bash/functions
[[ -f ~/.local/share/omarchy/default/bash/envs ]] && source ~/.local/share/omarchy/default/bash/envs

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

    export FZF_CTRL_R_OPTS="
        --preview 'echo {}'
        --preview-window=down:3:wrap
        --bind='ctrl-y:execute-silent(echo -n {2..} | wl-copy)+abort'
        --header='Press CTRL-Y to copy command to clipboard'
    "
fi

# SSH agent
if [[ -z "$SSH_AUTH_SOCK" ]]; then
    eval "$(ssh-agent -s)" > /dev/null
fi

# Unix timestamp (GNU date)
ut() {
    if [ $# -eq 0 ]; then
        date +%s
    else
        date -d "@$1" -Iseconds
    fi
}
